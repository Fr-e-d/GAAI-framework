import { describe, it, expect, vi, beforeEach } from "vitest";

// Mocks must be defined BEFORE imports of mocked modules
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

vi.mock("../app/lib/api.server", () => ({
  apiGet: vi.fn(),
  apiPatch: vi.fn(),
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

import { requireSession } from "../app/lib/session.server";
import { apiGet, apiPatch } from "../app/lib/api.server";
import { captureEvent } from "../app/lib/posthog.server";
import { loader, action } from "../app/routes/dashboard.billing";

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

const mockBilling = {
  credit_balance: 10000,
  ls_subscription_status: "active",
  ls_subscription_id: "sub-123",
  spending_limit: 50000,
  max_lead_price: 20000,
  monthly_spend: 15000,
  transactions: [
    {
      id: "txn-1",
      type: "credit",
      amount_cents: 10000,
      description: "Welcome credit",
      lead_id: null,
      created_at: "2026-02-01T00:00:00.000Z",
    },
  ],
  total_transactions: 1,
  page: 1,
  per_page: 20,
};

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

describe("billing loader", () => {
  it("returns billing data with formatted_date on transactions", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce(mockBilling);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/billing"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      billing: typeof mockBilling & { transactions: Array<{ formatted_date: string }> };
      userId: string;
      lsCheckoutUrl: string | null;
    };
    expect(data.billing.credit_balance).toBe(10000);
    expect(data.billing.transactions).toHaveLength(1);
    expect(typeof data.billing.transactions[0].formatted_date).toBe("string");
    expect(data.billing.transactions[0].formatted_date.length).toBeGreaterThan(0);
    expect(data.userId).toBe("user-1");

    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.billing_viewed",
      { has_subscription: true, subscription_status: "active" },
    );
  });

  it("passes page param to API", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce(mockBilling);

    await loader({
      request: new Request("https://app.callibrate.io/dashboard/billing?page=2"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/billing",
      { page: "2", per_page: "20" },
    );
  });

  it("graceful degradation when API fails", async () => {
    vi.mocked(apiGet).mockRejectedValueOnce(new Error("Network error"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/billing"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      billing: { credit_balance: number; transactions: unknown[] };
    };
    expect(data.billing.credit_balance).toBe(0);
    expect(data.billing.transactions).toHaveLength(0);
  });

  it("lsCheckoutUrl is null when env.LS_CHECKOUT_URL is absent", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce(mockBilling);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/billing"),
      context: makeCtx(mockEnv), // mockEnv has no LS_CHECKOUT_URL
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { lsCheckoutUrl: string | null };
    expect(data.lsCheckoutUrl).toBeNull();
  });

  it("returns null subscription fields when ls_subscription_id is null (CTA path)", async () => {
    const noSubscriptionBilling = {
      ...mockBilling,
      ls_subscription_id: null,
      ls_subscription_status: null,
    };
    vi.mocked(apiGet).mockResolvedValueOnce(noSubscriptionBilling);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/billing"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      billing: { ls_subscription_id: string | null; ls_subscription_status: string | null };
    };
    expect(data.billing.ls_subscription_id).toBeNull();
    expect(data.billing.ls_subscription_status).toBeNull();

    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.billing_viewed",
      { has_subscription: false, subscription_status: null },
    );
  });
});

// ── Action — update_max_lead_price ────────────────────────────────────────────

describe("billing action — update_max_lead_price", () => {
  it("succeeds with valid EUR amount (49.50 → 4950 centimes)", async () => {
    vi.mocked(apiPatch).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({
      intent: "update_max_lead_price",
      max_lead_price_eur: "49.50",
      old_max_lead_price: "20000",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean; intent: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("update_max_lead_price");

    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      { max_lead_price: 4950 },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.spending_control_updated",
      { control_name: "max_lead_price", old_value: 20000, new_value: 4950 },
    );
  });

  it("returns 422 for non-numeric input", async () => {
    const fd = makeFormData({
      intent: "update_max_lead_price",
      max_lead_price_eur: "abc",
      old_max_lead_price: "0",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(false);
    expect(vi.mocked(apiPatch)).not.toHaveBeenCalled();
  });

  it("returns 422 for negative input", async () => {
    const fd = makeFormData({
      intent: "update_max_lead_price",
      max_lead_price_eur: "-10",
      old_max_lead_price: "0",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    expect(vi.mocked(apiPatch)).not.toHaveBeenCalled();
  });

  it("returns 500 when apiPatch throws", async () => {
    vi.mocked(apiPatch).mockRejectedValueOnce(new Error("API failure"));

    const fd = makeFormData({
      intent: "update_max_lead_price",
      max_lead_price_eur: "100",
      old_max_lead_price: "0",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(false);
  });
});

// ── Action — update_spending_limit ────────────────────────────────────────────

describe("billing action — update_spending_limit", () => {
  it("succeeds with valid EUR amount", async () => {
    vi.mocked(apiPatch).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({
      intent: "update_spending_limit",
      spending_limit_eur: "200",
      old_spending_limit: "50000",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean; intent: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("update_spending_limit");

    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      { spending_limit: 20000 },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.spending_control_updated",
      { control_name: "spending_limit", old_value: 50000, new_value: 20000 },
    );
  });

  it("returns 422 for empty input", async () => {
    const fd = makeFormData({
      intent: "update_spending_limit",
      spending_limit_eur: "",
      old_spending_limit: "0",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    expect(vi.mocked(apiPatch)).not.toHaveBeenCalled();
  });

  it("accepts zero (explicit unset)", async () => {
    vi.mocked(apiPatch).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({
      intent: "update_spending_limit",
      spending_limit_eur: "0",
      old_spending_limit: "50000",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      { spending_limit: 0 },
    );
  });
});

// ── Action — unknown intent ────────────────────────────────────────────────────

describe("billing action — unknown intent", () => {
  it("returns 400 for unknown intent", async () => {
    const fd = makeFormData({ intent: "do_something_unknown" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/billing", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
    const body = await res.json() as { success: boolean; intent: string };
    expect(body.success).toBe(false);
    expect(body.intent).toBe("unknown");
  });
});
