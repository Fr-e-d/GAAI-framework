import { Env } from '../types/env';

export interface ExpertProfile {
  skills?: string[];
  industries?: string[];
  project_types?: string[];
  languages?: string[];
}

export function buildEmbeddingText(profile: ExpertProfile): string {
  const skills = (profile.skills ?? []).join(', ');
  const industries = (profile.industries ?? []).join(', ');
  const projectTypes = (profile.project_types ?? []).join(', ');
  const languages = (profile.languages ?? []).join(', ');
  return `Skills: ${skills}. Industries: ${industries}. Project types: ${projectTypes}. Languages: ${languages}.`;
}

export function upsertExpertEmbedding(
  env: Env,
  ctx: ExecutionContext,
  expertId: string,
  profileData: {
    profile: ExpertProfile;
    rate_min?: number | null;
    rate_max?: number | null;
    availability?: string | null;
  }
): void {
  ctx.waitUntil(
    (async () => {
      try {
        const text = buildEmbeddingText(profileData.profile);

        const result = await env.AI.run('@cf/baai/bge-base-en-v1.5', {
          text: [text],
        }) as { data: number[][] };

        const vector = result.data[0];
        if (!vector || vector.length === 0) {
          console.warn('vectorize: empty embedding returned for expert', expertId);
          return;
        }

        const metadata: Record<string, string | number | boolean> = {
          expert_id: expertId,
        };
        if (profileData.rate_min != null) metadata.rate_min = profileData.rate_min;
        if (profileData.rate_max != null) metadata.rate_max = profileData.rate_max;
        if (profileData.availability != null) metadata.availability = profileData.availability;

        await env.VECTORIZE.upsert([
          {
            id: expertId,
            values: vector,
            metadata,
          },
        ]);
      } catch (err) {
        console.error('vectorize: upsert failed for expert', expertId, err);
      }
    })()
  );
}
