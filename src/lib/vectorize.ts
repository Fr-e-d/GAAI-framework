import type { Env } from '../types/env';

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

// ── Prospect-side semantic query helpers (E06S22) ──────────────────────────

// AC1: build embedding text from prospect requirements
export function buildProspectEmbeddingText(requirements: {
  skills_needed?: string[];
  industry?: string;
  languages?: string[];
}): string {
  const skills = (requirements.skills_needed ?? []).join(', ');
  const industry = requirements.industry ?? '';
  const languages = (requirements.languages ?? []).join(', ');
  return `Skills: ${skills}. Industries: ${industry}. Languages: ${languages}.`;
}

// AC1: query Vectorize index, returns Map<expert_id, cosine_similarity>
// topK should be Math.max(pool.length, 100) to satisfy AC2 (no filtering loss when pool < 100)
export async function queryVectorizeForProspect(
  env: Env,
  vector: number[],
  topK: number,
): Promise<Map<string, number>> {
  const result = await env.VECTORIZE.query(vector, { topK });
  const map = new Map<string, number>();
  for (const match of result.matches) {
    map.set(match.id, match.score);
  }
  return map;
}
