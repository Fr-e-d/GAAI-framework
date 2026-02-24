// Vectorize embedding helpers (ported from core src/lib/vectorize.ts)
// Adapted to use MatchingEnv instead of core Env.

import type { MatchingEnv } from './env';

export interface ExpertEmbeddingProfile {
  skills?: string[];
  industries?: string[];
  project_types?: string[];
  languages?: string[];
}

export function buildEmbeddingText(profile: ExpertEmbeddingProfile): string {
  const skills = (profile.skills ?? []).join(', ');
  const industries = (profile.industries ?? []).join(', ');
  const projectTypes = (profile.project_types ?? []).join(', ');
  const languages = (profile.languages ?? []).join(', ');
  return `Skills: ${skills}. Industries: ${industries}. Project types: ${projectTypes}. Languages: ${languages}.`;
}

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

// Fire-and-forget: generate embedding + upsert into Vectorize index
export function upsertExpertEmbedding(
  env: MatchingEnv,
  ctx: ExecutionContext,
  expertId: string,
  profileData: {
    profile: ExpertEmbeddingProfile;
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

        const metadata: Record<string, string | number | boolean> = { expert_id: expertId };
        if (profileData.rate_min != null) metadata.rate_min = profileData.rate_min;
        if (profileData.rate_max != null) metadata.rate_max = profileData.rate_max;
        if (profileData.availability != null) metadata.availability = profileData.availability;

        await env.VECTORIZE.upsert([{ id: expertId, values: vector, metadata }]);
      } catch (err) {
        console.error('vectorize: upsert failed for expert', expertId, err);
      }
    })()
  );
}

// Query Vectorize for prospect semantic pre-filter
// Returns Map<expert_id, cosine_similarity>
export async function queryVectorize(
  env: MatchingEnv,
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

// ── Outcome alignment helpers (AC9/E06S37) ────────────────────────────────────

// Dot-product cosine similarity for unit-normalized vectors (BGE model outputs L2-normalized vectors)
function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  for (let i = 0; i < a.length; i++) dot += (a[i] ?? 0) * (b[i] ?? 0);
  return Math.max(0, Math.min(1, dot));
}

// Compute outcome alignment scores for a batch of experts in one Workers AI call.
// Returns Map<expert_id, alignment_score (0.0–1.0)> for experts with non-empty outcome_tags.
// Experts without outcome_tags are not included in the returned map (treated as null by caller).
export async function computeBatchOutcomeAlignments(
  ai: Ai,
  expertOutcomeTagsMap: Map<string, string[]>, // expert_id → outcome_tags
  desiredOutcomes: string[], // prospect's desired_outcomes
): Promise<Map<string, number>> {
  const result = new Map<string, number>();

  if (desiredOutcomes.length === 0) return result;

  // Collect all unique outcome strings across all experts
  const allExpertTagStrings = [...new Set(
    [...expertOutcomeTagsMap.values()].flat()
  )];

  if (allExpertTagStrings.length === 0) return result;

  // One batch embedding call: desired_outcomes first, then all expert tags
  const allStrings = [...desiredOutcomes, ...allExpertTagStrings];
  let embedData: number[][];

  try {
    const embeddingResult = await ai.run('@cf/baai/bge-base-en-v1.5', {
      text: allStrings,
    }) as { data: number[][] };
    embedData = embeddingResult.data;
  } catch (err) {
    console.error('matching: outcome alignment embedding failed', err);
    return result;
  }

  const desiredEmbeddings = embedData.slice(0, desiredOutcomes.length);
  const expertTagEmbeddings = embedData.slice(desiredOutcomes.length);

  // Build lookup: tag string → embedding
  const tagEmbeddingMap = new Map<string, number[]>(
    allExpertTagStrings.map((tag, i) => [tag, expertTagEmbeddings[i] as number[]])
  );

  // For each expert, compute max-pairwise alignment averaged over desired_outcomes
  for (const [expertId, tags] of expertOutcomeTagsMap) {
    if (tags.length === 0) continue;

    const tagEmbs = tags
      .map((t) => tagEmbeddingMap.get(t))
      .filter((e): e is number[] => e != null);

    if (tagEmbs.length === 0) continue;

    let totalMaxSim = 0;
    for (const dEmb of desiredEmbeddings) {
      const maxSim = Math.max(...tagEmbs.map((eEmb) => cosineSimilarity(dEmb, eEmb)));
      totalMaxSim += maxSim;
    }

    result.set(expertId, Math.min(1.0, totalMaxSim / desiredOutcomes.length));
  }

  return result;
}
