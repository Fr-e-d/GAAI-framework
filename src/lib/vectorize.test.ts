import { describe, it, expect, vi, beforeEach } from 'vitest';
import { buildEmbeddingText, upsertExpertEmbedding, buildProspectEmbeddingText, queryVectorizeForProspect } from './vectorize';
import type { Env } from '../types/env';

const mockAi = {
  run: vi.fn(),
};

const mockVectorize = {
  upsert: vi.fn(),
  query: vi.fn(),
};

const mockEnv = {
  AI: mockAi,
  VECTORIZE: mockVectorize,
} as unknown as Env;

const mockCtx = {
  waitUntil: vi.fn((p: Promise<void>) => p),
} as unknown as ExecutionContext;

beforeEach(() => {
  mockAi.run.mockReset();
  mockVectorize.upsert.mockReset();
  vi.mocked(mockCtx.waitUntil).mockReset();
  vi.mocked(mockCtx.waitUntil).mockImplementation((p: Promise<void>) => p);
});

describe('buildEmbeddingText', () => {
  it('formats full profile correctly', () => {
    const result = buildEmbeddingText({
      skills: ['react', 'typescript'],
      industries: ['saas', 'fintech'],
      project_types: ['web apps'],
      languages: ['english', 'french'],
    });
    expect(result).toBe(
      'Skills: react, typescript. Industries: saas, fintech. Project types: web apps. Languages: english, french.'
    );
  });

  it('formats empty profile with empty segments', () => {
    const result = buildEmbeddingText({});
    expect(result).toBe('Skills: . Industries: . Project types: . Languages: .');
  });

  it('formats partial profile (only skills)', () => {
    const result = buildEmbeddingText({ skills: ['python'] });
    expect(result).toBe('Skills: python. Industries: . Project types: . Languages: .');
  });
});

describe('upsertExpertEmbedding', () => {
  it('calls AI and Vectorize with correct args on happy path', async () => {
    const fakeVector = Array(768).fill(0.1);
    mockAi.run.mockResolvedValue({ data: [fakeVector] });
    mockVectorize.upsert.mockResolvedValue(undefined);

    upsertExpertEmbedding(mockEnv, mockCtx, 'expert-123', {
      profile: { skills: ['react'] },
      rate_min: 100,
      rate_max: 200,
      availability: 'available',
    });

    expect(mockCtx.waitUntil).toHaveBeenCalledOnce();
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await bgPromise;

    expect(mockAi.run).toHaveBeenCalledWith('@cf/baai/bge-base-en-v1.5', {
      text: [expect.stringContaining('react')],
    });
    expect(mockVectorize.upsert).toHaveBeenCalledWith([
      {
        id: 'expert-123',
        values: fakeVector,
        metadata: {
          expert_id: 'expert-123',
          rate_min: 100,
          rate_max: 200,
          availability: 'available',
        },
      },
    ]);
  });

  it('AI throws — Vectorize not called, no error propagated', async () => {
    mockAi.run.mockRejectedValue(new Error('AI down'));

    upsertExpertEmbedding(mockEnv, mockCtx, 'expert-456', { profile: {} });
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await expect(bgPromise).resolves.toBeUndefined();

    expect(mockVectorize.upsert).not.toHaveBeenCalled();
  });

  it('Vectorize throws — no error propagated', async () => {
    mockAi.run.mockResolvedValue({ data: [Array(768).fill(0.1)] });
    mockVectorize.upsert.mockRejectedValue(new Error('Vectorize down'));

    upsertExpertEmbedding(mockEnv, mockCtx, 'expert-789', { profile: {} });
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await expect(bgPromise).resolves.toBeUndefined();
  });

  it('AI returns empty vector — Vectorize not called', async () => {
    mockAi.run.mockResolvedValue({ data: [[]] });

    upsertExpertEmbedding(mockEnv, mockCtx, 'expert-000', { profile: {} });
    const [bgPromise] = vi.mocked(mockCtx.waitUntil).mock.calls[0] as [Promise<void>];
    await bgPromise;

    expect(mockVectorize.upsert).not.toHaveBeenCalled();
  });

  it('returns void synchronously and calls waitUntil once', () => {
    mockAi.run.mockResolvedValue({ data: [Array(768).fill(0.1)] });

    const result = upsertExpertEmbedding(mockEnv, mockCtx, 'expert-sync', { profile: {} });
    expect(result).toBeUndefined();
    expect(mockCtx.waitUntil).toHaveBeenCalledOnce();
  });
});

// ── buildProspectEmbeddingText (E06S22) ────────────────────────────────────

describe('buildProspectEmbeddingText', () => {
  it('formats full requirements correctly', () => {
    const result = buildProspectEmbeddingText({
      skills_needed: ['machine learning', 'python'],
      industry: 'fintech',
      languages: ['english'],
    });
    expect(result).toBe('Skills: machine learning, python. Industries: fintech. Languages: english.');
  });

  it('formats empty requirements', () => {
    const result = buildProspectEmbeddingText({});
    expect(result).toBe('Skills: . Industries: . Languages: .');
  });

  it('formats partial requirements (skills only)', () => {
    const result = buildProspectEmbeddingText({ skills_needed: ['deep learning'] });
    expect(result).toBe('Skills: deep learning. Industries: . Languages: .');
  });
});

// ── queryVectorizeForProspect (E06S22) ─────────────────────────────────────

describe('queryVectorizeForProspect', () => {
  it('returns Map of expert_id → cosine similarity', async () => {
    const fakeVector = Array(768).fill(0.1);
    mockVectorize.query = vi.fn().mockResolvedValue({
      matches: [
        { id: 'expert-1', score: 0.92 },
        { id: 'expert-2', score: 0.85 },
        { id: 'expert-3', score: 0.71 },
      ],
      count: 3,
    });

    const result = await queryVectorizeForProspect(mockEnv, fakeVector, 100);

    expect(mockVectorize.query).toHaveBeenCalledWith(fakeVector, { topK: 100 });
    expect(result.size).toBe(3);
    expect(result.get('expert-1')).toBe(0.92);
    expect(result.get('expert-2')).toBe(0.85);
    expect(result.get('expert-3')).toBe(0.71);
  });

  it('returns empty Map when no matches', async () => {
    mockVectorize.query = vi.fn().mockResolvedValue({ matches: [], count: 0 });

    const result = await queryVectorizeForProspect(mockEnv, Array(768).fill(0), 100);

    expect(result.size).toBe(0);
  });
});
