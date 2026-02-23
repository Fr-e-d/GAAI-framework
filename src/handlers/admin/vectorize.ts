import { Env } from '../../types/env';
import { createServiceClient } from '../../lib/supabase';
import { buildEmbeddingText, ExpertProfile } from '../../lib/vectorize';

export async function handleVectorizeReindex(
  request: Request,
  env: Env,
  ctx: ExecutionContext
): Promise<Response> {
  // AC6: Service-key auth
  const authHeader = request.headers.get('Authorization');
  if (authHeader !== `Bearer ${env.SUPABASE_SERVICE_KEY}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabase = createServiceClient(env);

  const { data: experts, error } = await supabase
    .from('experts')
    .select('id, profile, rate_min, rate_max, availability')
    .neq('availability', 'unavailable');

  if (error) {
    return new Response(
      JSON.stringify({ error: 'Failed to fetch experts', details: { message: error.message } }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const total = experts?.length ?? 0;

  ctx.waitUntil(
    (async () => {
      for (const expert of experts ?? []) {
        try {
          const text = buildEmbeddingText((expert.profile as ExpertProfile) ?? {});
          const result = await env.AI.run('@cf/baai/bge-base-en-v1.5', {
            text: [text],
          }) as { data: number[][] };
          const vector = result.data[0];
          if (!vector || vector.length === 0) {
            console.warn('reindex: empty embedding for expert', expert.id);
            continue;
          }
          const metadata: Record<string, string | number | boolean> = {
            expert_id: expert.id,
          };
          if (expert.rate_min != null) metadata.rate_min = expert.rate_min;
          if (expert.rate_max != null) metadata.rate_max = expert.rate_max;
          if (expert.availability != null) metadata.availability = expert.availability;

          await env.VECTORIZE.upsert([{
            id: expert.id,
            values: vector,
            metadata,
          }]);
        } catch (err) {
          console.error('reindex: failed for expert', expert.id, err);
        }
      }
    })()
  );

  return new Response(
    JSON.stringify({ queued: total }),
    { status: 202, headers: { 'Content-Type': 'application/json' } }
  );
}
