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

// Embed a list of strings via Workers AI, batching in groups of 100 if needed.
// BGE-base-en-v1.5 supports up to 100 texts per call.
export async function embedStrings(ai: Ai, texts: string[]): Promise<number[][]> {
  if (texts.length === 0) return [];
  const BATCH_SIZE = 100;
  const results: number[][] = [];
  for (let i = 0; i < texts.length; i += BATCH_SIZE) {
    const batch = texts.slice(i, i + BATCH_SIZE);
    const result = await ai.run('@cf/baai/bge-base-en-v1.5', {
      text: batch,
    }) as { data: number[][] };
    results.push(...result.data);
  }
  return results;
}

// Compute embeddings for an expert's outcome_tags.
// Returns Record<tag_string, embedding_vector> — stored in D1, not recomputed at match time.
export async function computeTagEmbeddings(
  ai: Ai,
  tags: string[],
): Promise<Record<string, number[]>> {
  if (tags.length === 0) return {};
  const embeddings = await embedStrings(ai, tags);
  const result: Record<string, number[]> = {};
  for (let i = 0; i < tags.length; i++) {
    result[tags[i]!] = embeddings[i]!;
  }
  return result;
}

// Compute outcome alignment scores using pre-computed expert tag embeddings from D1.
// desiredEmbeddings: pre-embedded desired_outcomes vectors (computed once per request, max 5).
// expertEmbeddingsMap: Map<expert_id, Record<tag, vector>> loaded from D1.
// Returns Map<expert_id, alignment_score (0.0–1.0)>.
export function computeAlignmentsFromPrecomputed(
  expertEmbeddingsMap: Map<string, Record<string, number[]>>,
  desiredEmbeddings: number[][],
): Map<string, number> {
  const result = new Map<string, number>();
  if (desiredEmbeddings.length === 0) return result;

  for (const [expertId, tagEmbeddings] of expertEmbeddingsMap) {
    const tagEmbs = Object.values(tagEmbeddings).filter((v) => v.length > 0);
    if (tagEmbs.length === 0) continue;

    let totalMaxSim = 0;
    for (const dEmb of desiredEmbeddings) {
      const maxSim = Math.max(...tagEmbs.map((eEmb) => cosineSimilarity(dEmb, eEmb)));
      totalMaxSim += maxSim;
    }

    result.set(expertId, Math.min(1.0, totalMaxSim / desiredEmbeddings.length));
  }

  return result;
}
