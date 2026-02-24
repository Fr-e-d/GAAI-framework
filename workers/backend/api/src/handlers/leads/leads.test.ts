import { describe, it, expect, vi, afterEach } from 'vitest';
import { handleFlagLead } from './flag';
import { handleConfirmLead } from './confirm';
import type { Env } from '../../types/env';
import type { AuthUser } from '../../middleware/auth';

// ── Mock supabase ──────────────────────────────────────────────────────────────

vi.mock('../../lib/supabase', () => ({
  createServiceClient: vi.fn(),
}));

import { createServiceClient } from '../../lib/supabase';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeEnv(): Env {
  return {
    SUPABASE_URL: 'https://test.supabase.co',
    SUPABASE_ANON_KEY: 'test-anon-key',
    SUPABASE_SERVICE_KEY: 'test-service-key',
  } as unknown as Env;
}

function makeUser(id = 'expert-1'): AuthUser {
  return { id, email: 'expert@test.com' };
}

function makeRequest(method = 'POST', body?: Record<string, unknown>): Request {
  const init: RequestInit = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
  }
  return new Request('https://api.callibrate.io/api/leads/lead-1/flag', init);
}

// Build a mock Supabase that supports .from().select().eq().single() chain + .rpc()
function buildLeadMock(opts: {
  lead?: Record<string, unknown> | null;
  leadError?: { message: string } | null;
  rpcResult?: { data: Record<string, unknown> | null; error: { message: string } | null };
  updateResult?: { error: { message: string } | null };
}) {
  const {
    lead = { id: 'lead-1', expert_id: 'expert-1', status: 'pending', created_at: new Date().toISOString(), amount: 8900 },
    leadError = null,
    rpcResult = { data: { success: true, balance_after: 100000 }, error: null },
    updateResult = { error: null },
  } = opts;

  const mockSingle = vi.fn().mockResolvedValue({ data: lead, error: leadError });
  const mockEq = vi.fn().mockReturnValue({ single: mockSingle });
  const mockSelect = vi.fn().mockReturnValue({ eq: mockEq });

  const mockUpdateEq = vi.fn().mockResolvedValue(updateResult);
  const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });

  const mockFrom = vi.fn().mockReturnValue({
    select: mockSelect,
    update: mockUpdate,
  });

  const mockRpc = vi.fn().mockResolvedValue(rpcResult);

  return { from: mockFrom, rpc: mockRpc, _mocks: { mockSingle, mockUpdate, mockUpdateEq, mockRpc } };
}

// ── Flag Lead Tests ───────────────────────────────────────────────────────────

describe('handleFlagLead', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  // ── Test 1: Happy path — flag pending lead within 7-day window ───────────

  it('happy path — flags pending lead, restores credit, returns 200', async () => {
    const mock = buildLeadMock({});
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST', { reason: 'prospect was not serious' });
    const res = await handleFlagLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(true);

    // RPC called with correct params
    expect(mock.rpc).toHaveBeenCalledWith('restore_lead_credit', expect.objectContaining({
      p_expert_id:   'expert-1',
      p_lead_id:     'lead-1',
      p_amount:      8900,
      p_flag_reason: 'prospect was not serious',
    }));
  });

  // ── Test 2: Flag window expired — 422 ────────────────────────────────────

  it('flag window expired — returns 422', async () => {
    const eightDaysAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString();
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'expert-1', status: 'pending', created_at: eightDaysAgo, amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST', { reason: 'expired' });
    const res = await handleFlagLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Flag window expired');
    expect(mock.rpc).not.toHaveBeenCalled();
  });

  // ── Test 3: Wrong owner — 403 ─────────────────────────────────────────────

  it('wrong owner — returns 403', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'other-expert', status: 'pending', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST', { reason: 'test' });
    const res = await handleFlagLead(req, makeEnv(), makeUser('expert-1'), 'lead-1');

    expect(res.status).toBe(403);
    expect(mock.rpc).not.toHaveBeenCalled();
  });

  // ── Test 4: Already flagged — 422 ────────────────────────────────────────

  it('already flagged lead — returns 422 (status not pending)', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'expert-1', status: 'flagged', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST', { reason: 'test' });
    const res = await handleFlagLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Lead status must be pending');
    expect(mock.rpc).not.toHaveBeenCalled();
  });

  // ── Test 5: Already confirmed — 422 ──────────────────────────────────────

  it('already confirmed lead — returns 422 (status not pending)', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST', { reason: 'test' });
    const res = await handleFlagLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Lead status must be pending');
  });

  // ── Test 6: Lead not found — 404 ─────────────────────────────────────────

  it('lead not found — returns 404', async () => {
    const mock = buildLeadMock({
      lead: null,
      leadError: { message: 'not found' },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST');
    const res = await handleFlagLead(req, makeEnv(), makeUser(), 'nonexistent-id');

    expect(res.status).toBe(404);
  });
});

// ── Confirm Lead Tests ────────────────────────────────────────────────────────

describe('handleConfirmLead', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  // ── Test 7: Happy path — confirm pending lead ─────────────────────────────

  it('happy path — confirms pending lead, returns 200', async () => {
    const mock = buildLeadMock({});
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST');
    const res = await handleConfirmLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(true);

    // UPDATE called with confirmed status (AC5)
    expect(mock._mocks.mockUpdate).toHaveBeenCalledWith(expect.objectContaining({
      status: 'confirmed',
    }));
  });

  // ── Test 8: Wrong status (already confirmed) — 422 ───────────────────────

  it('already confirmed lead — returns 422', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'expert-1', status: 'confirmed', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST');
    const res = await handleConfirmLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(422);
    const body = await res.json() as { error: string };
    expect(body.error).toBe('Lead status must be pending');
    expect(mock._mocks.mockUpdate).not.toHaveBeenCalled();
  });

  // ── Test 9: Wrong owner — 403 ─────────────────────────────────────────────

  it('wrong owner — returns 403', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'other-expert', status: 'pending', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST');
    const res = await handleConfirmLead(req, makeEnv(), makeUser('expert-1'), 'lead-1');

    expect(res.status).toBe(403);
    expect(mock._mocks.mockUpdate).not.toHaveBeenCalled();
  });

  // ── Test 10: Flagged lead — 422 ───────────────────────────────────────────

  it('flagged lead — returns 422 (status not pending)', async () => {
    const mock = buildLeadMock({
      lead: { id: 'lead-1', expert_id: 'expert-1', status: 'flagged', created_at: new Date().toISOString(), amount: 8900 },
    });
    vi.mocked(createServiceClient).mockReturnValue(mock as unknown as ReturnType<typeof createServiceClient>);

    const req = makeRequest('POST');
    const res = await handleConfirmLead(req, makeEnv(), makeUser(), 'lead-1');

    expect(res.status).toBe(422);
  });
});
