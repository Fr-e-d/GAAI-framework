import { describe, it, expect, vi, beforeEach } from "vitest";

// Mocks must be defined BEFORE imports of mocked modules
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

vi.mock("../app/lib/api.server", () => ({
  apiGet: vi.fn(),
  apiPost: vi.fn(),
  ApiError: class ApiError extends Error {
    constructor(
      public status: number,
      public body: unknown,
      message: string,
    ) {
      super(message);
    }
  },
}));

vi.mock("../app/lib/posthog.server", () => ({
  captureEvent: vi.fn(),
}));

// Mock react-router redirect to produce a testable Response
vi.mock("react-router", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react-router")>();
  return {
    ...actual,
    redirect: vi.fn(
      (url: string) =>
        new Response(null, { status: 302, headers: { Location: url } }),
    ),
  };
});

import { requireSession } from "../app/lib/session.server";
import { apiGet, apiPost } from "../app/lib/api.server";
import { captureEvent } from "../app/lib/posthog.server";
import { loader, action } from "../app/routes/dashboard.leads";

// ── Fixtures ──────────────────────────────────────────────────────────────────

const mockEnv: Env = {
  CORE_API_URL: "http://localhost:8787",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_ANON_KEY: "test-anon-key",
};

const mockSession = {
  user: { id: "user-1", email: "expert@example.com" },
  token: "token-abc",
};

type Lead = {
  id: string;
  status: string | null;
  price_cents: number | null;
  created_at: string | null;
  confirmed_at: string | null;
  flagged_at: string | null;
  flag_reason: string | null;
  flag_window_expires_at: string | null;
  evaluation_score: number | null;
  evaluation_notes: string | null;
  conversion_declared: boolean;
  evaluated_at: string | null;
  prospect: { id: string; email: string | null; requirements: unknown } | null;
  match_score: number | null;
  booking: { id: string; starts_at: string | null; status: string | null } | null;
};

function makeLead(overrides: Partial<Lead> = {}): Lead {
  return {
    id: "lead-1",
    status: "new",
    price_cents: 15000,
    created_at: new Date(Date.now() - 7_200_000).toISOString(),
    confirmed_at: null,
    flagged_at: null,
    flag_reason: null,
    flag_window_expires_at: new Date(Date.now() + 5 * 86_400_000).toISOString(),
    evaluation_score: null,
    evaluation_notes: null,
    conversion_declared: false,
    evaluated_at: null,
    prospect: {
      id: "prospect-1",
      email: "prospect@example.com",
      requirements: { budget: "5000", description: "Need n8n automation" },
    },
    match_score: 87,
    booking: null,
    ...overrides,
  };
}

function makeCtx(env = mockEnv) {
  return { cloudflare: { env, ctx: {} as ExecutionContext } };
}

function makeFormData(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    fd.append(k, v);
  }
  return fd;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(requireSession).mockResolvedValue({
    session: mockSession,
    responseHeaders: new Headers(),
  } as Awaited<ReturnType<typeof requireSession>>);
  vi.mocked(captureEvent).mockResolvedValue(undefined);
});

// ── Loader tests ──────────────────────────────────────────────────────────────

describe("leads loader", () => {
  it("fetches leads with default params (status=all, page=1)", async () => {
    const mockLeads = [makeLead()];
    vi.mocked(apiGet).mockResolvedValueOnce({
      leads: mockLeads,
      total: 1,
      page: 1,
      per_page: 20,
    });

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/leads"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      leads: Lead[];
      total: number;
      page: number;
      per_page: number;
      userId: string;
    };
    expect(data.leads).toHaveLength(1);
    expect(data.total).toBe(1);
    expect(data.userId).toBe("user-1");

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/leads",
      { status: "all", page: "1", per_page: "20" },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.leads_viewed",
      { status_filter: "all" },
    );
  });

  it("passes status=new filter from URL search params", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce({ leads: [], total: 0, page: 2, per_page: 20 });

    await loader({
      request: new Request("https://app.callibrate.io/dashboard/leads?status=new&page=2"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/leads",
      { status: "new", page: "2", per_page: "20" },
    );
  });

  it("passes status=confirmed filter from URL search params", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce({ leads: [], total: 0, page: 1, per_page: 20 });

    await loader({
      request: new Request(
        "https://app.callibrate.io/dashboard/leads?status=confirmed",
      ),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/leads",
      { status: "confirmed", page: "1", per_page: "20" },
    );
  });

  it("returns empty leads when API fails (graceful degradation)", async () => {
    vi.mocked(apiGet).mockRejectedValueOnce(new Error("Network error"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/leads"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = (await res.json()) as { leads: Lead[]; total: number };
    expect(data.leads).toHaveLength(0);
    expect(data.total).toBe(0);
  });
});

// ── Action — confirm ───────────────────────────────────────────────────────────

describe("leads action — confirm", () => {
  it("calls confirm endpoint and returns success", async () => {
    vi.mocked(apiPost).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({ intent: "confirm", leadId: "lead-1", price_cents: "15000" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; intent: string; leadId: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("confirm");
    expect(body.leadId).toBe("lead-1");

    expect(vi.mocked(apiPost)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/leads/lead-1/confirm",
      {},
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.lead_confirmed",
      { lead_id: "lead-1", price_cents: 15000 },
    );
  });

  it("returns 400 when leadId is missing", async () => {
    const fd = makeFormData({ intent: "confirm" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
    const body = (await res.json()) as { success: boolean };
    expect(body.success).toBe(false);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 500 when confirm API throws", async () => {
    vi.mocked(apiPost).mockRejectedValueOnce(new Error("API failure"));

    const fd = makeFormData({ intent: "confirm", leadId: "lead-1" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = (await res.json()) as { success: boolean };
    expect(body.success).toBe(false);
  });
});

// ── Action — flag ──────────────────────────────────────────────────────────────

describe("leads action — flag", () => {
  const validReason = "Ce prospect ne correspond pas à mes critères minimaux de budget";

  it("calls flag endpoint with valid reason", async () => {
    vi.mocked(apiPost).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({ intent: "flag", leadId: "lead-1", flag_reason: validReason });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; intent: string; leadId: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("flag");

    expect(vi.mocked(apiPost)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/leads/lead-1/flag",
      { reason: validReason },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.lead_flagged",
      { lead_id: "lead-1", reason_length: validReason.length },
    );
  });

  it("returns 422 when flag_reason is less than 20 characters", async () => {
    const fd = makeFormData({ intent: "flag", leadId: "lead-1", flag_reason: "Trop court" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = (await res.json()) as { success: boolean; error: string };
    expect(body.success).toBe(false);
    expect(body.error).toMatch(/20 caractères/);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 400 when leadId is missing on flag", async () => {
    const fd = makeFormData({ intent: "flag", flag_reason: validReason });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
  });

  it("returns 500 when flag API throws", async () => {
    vi.mocked(apiPost).mockRejectedValueOnce(new Error("Flag API failed"));

    const fd = makeFormData({ intent: "flag", leadId: "lead-1", flag_reason: validReason });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = (await res.json()) as { success: boolean };
    expect(body.success).toBe(false);
  });
});

// ── Action — evaluate ──────────────────────────────────────────────────────────

describe("leads action — evaluate", () => {
  it("calls evaluate with valid score, notes, and conversion", async () => {
    vi.mocked(apiPost).mockResolvedValueOnce({ id: "lead-1", evaluation_score: 8 });

    const fd = makeFormData({
      intent: "evaluate",
      leadId: "lead-1",
      score: "8",
      notes: "Bon prospect, budget réaliste",
      conversion_declared: "true",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; intent: string; leadId: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("evaluate");

    expect(vi.mocked(apiPost)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/leads/lead-1/evaluate",
      { score: 8, notes: "Bon prospect, budget réaliste", conversion_declared: true },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.lead_evaluated",
      { lead_id: "lead-1", score: 8, conversion_declared: true },
    );
  });

  it("calls evaluate with score only (notes undefined, conversion false)", async () => {
    vi.mocked(apiPost).mockResolvedValueOnce({ id: "lead-1", evaluation_score: 5 });

    const fd = makeFormData({ intent: "evaluate", leadId: "lead-1", score: "5" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    expect(vi.mocked(apiPost)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/leads/lead-1/evaluate",
      { score: 5, notes: undefined, conversion_declared: false },
    );
  });

  it("returns 422 when score is out of range (11)", async () => {
    const fd = makeFormData({ intent: "evaluate", leadId: "lead-1", score: "11" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = (await res.json()) as { success: boolean; error: string };
    expect(body.success).toBe(false);
    expect(body.error).toMatch(/Score invalide/);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 422 when score is 0 (below minimum)", async () => {
    const fd = makeFormData({ intent: "evaluate", leadId: "lead-1", score: "0" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
  });

  it("returns 422 when score is missing (NaN)", async () => {
    const fd = makeFormData({ intent: "evaluate", leadId: "lead-1" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
  });

  it("returns 422 when notes exceed 500 characters", async () => {
    const fd = makeFormData({
      intent: "evaluate",
      leadId: "lead-1",
      score: "7",
      notes: "x".repeat(501),
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = (await res.json()) as { error: string };
    expect(body.error).toMatch(/500 caractères/);
  });

  it("returns 500 when evaluate API throws", async () => {
    vi.mocked(apiPost).mockRejectedValueOnce(new Error("Evaluate API failed"));

    const fd = makeFormData({ intent: "evaluate", leadId: "lead-1", score: "7" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
  });

  it("returns 400 for unknown intent", async () => {
    const fd = makeFormData({ intent: "doSomethingUnknown" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/leads", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
    const body = (await res.json()) as { intent: string };
    expect(body.intent).toBe("unknown");
  });
});
