import { describe, it, expect, vi, beforeEach } from "vitest";

// Mocks must be defined BEFORE imports of mocked modules
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

vi.mock("../app/lib/api.server", () => ({
  apiGet: vi.fn(),
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
import { apiGet } from "../app/lib/api.server";
import { captureEvent } from "../app/lib/posthog.server";
import {
  loader,
  getTierConfig,
  formatMonthLabel,
  safePct,
} from "../app/routes/dashboard.analytics";

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

const mockMonthHistory = [
  { month: "2025-09", leads_received: 2, leads_confirmed: 1, leads_flagged: 0, bookings_total: 1, bookings_completed: 1, conversions_declared: 1 },
  { month: "2025-10", leads_received: 3, leads_confirmed: 2, leads_flagged: 0, bookings_total: 2, bookings_completed: 1, conversions_declared: 1 },
  { month: "2025-11", leads_received: 4, leads_confirmed: 3, leads_flagged: 1, bookings_total: 3, bookings_completed: 2, conversions_declared: 2 },
  { month: "2025-12", leads_received: 5, leads_confirmed: 4, leads_flagged: 1, bookings_total: 4, bookings_completed: 3, conversions_declared: 3 },
  { month: "2026-01", leads_received: 6, leads_confirmed: 5, leads_flagged: 0, bookings_total: 5, bookings_completed: 4, conversions_declared: 3 },
  { month: "2026-02", leads_received: 7, leads_confirmed: 6, leads_flagged: 1, bookings_total: 5, bookings_completed: 4, conversions_declared: 4 },
];

const mockDashboard = {
  unread_leads: 3,
  upcoming_bookings: 2,
  credit_balance: 10000,
  composite_score: 78,
  quality_tier: "Established" as const,
  month_stats: {
    leads_received: 7,
    leads_confirmed: 6,
    leads_flagged: 1,
    bookings_total: 5,
    bookings_completed: 4,
    conversions_declared: 4,
  },
  monthly_history: mockMonthHistory,
};

const mockProfile = {
  composite_score: 78,
  profile: {
    call_experience: 80,
    trust: 75,
    satisfaction: 70,
    hire_rate: null,
    recency: 85,
  },
};

function makeCtx(env = mockEnv) {
  return { cloudflare: { env, ctx: {} as ExecutionContext } };
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

describe("analytics loader", () => {
  it("returns dashboard and profile data, fires expert.analytics_viewed", async () => {
    vi.mocked(apiGet)
      .mockResolvedValueOnce(mockDashboard)
      .mockResolvedValueOnce(mockProfile);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      dashboard: typeof mockDashboard;
      profileScores: typeof mockProfile.profile;
      userId: string;
    };

    expect(data.dashboard.composite_score).toBe(78);
    expect(data.dashboard.quality_tier).toBe("Established");
    expect(data.dashboard.monthly_history).toHaveLength(6);
    expect(data.profileScores).toEqual(mockProfile.profile);
    expect(data.userId).toBe("user-1");

    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.analytics_viewed",
      { composite_score: 78, quality_tier: "Established" },
    );
  });

  it("graceful degradation when dashboard API fails", async () => {
    vi.mocked(apiGet)
      .mockRejectedValueOnce(new Error("Network error"))
      .mockResolvedValueOnce(mockProfile);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      dashboard: { composite_score: null; month_stats: { leads_received: number } };
    };
    expect(data.dashboard.composite_score).toBeNull();
    expect(data.dashboard.month_stats.leads_received).toBe(0);
  });

  it("graceful degradation when profile API fails", async () => {
    vi.mocked(apiGet)
      .mockResolvedValueOnce(mockDashboard)
      .mockRejectedValueOnce(new Error("Profile error"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { profileScores: null };
    expect(data.profileScores).toBeNull();
  });

  it("both APIs fail — returns zeroed defaults", async () => {
    vi.mocked(apiGet)
      .mockRejectedValueOnce(new Error("err1"))
      .mockRejectedValueOnce(new Error("err2"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      dashboard: { composite_score: null; unread_leads: number };
      profileScores: null;
    };
    expect(data.dashboard.composite_score).toBeNull();
    expect(data.dashboard.unread_leads).toBe(0);
    expect(data.profileScores).toBeNull();
  });

  it("loader returns partial profileScores when some are null", async () => {
    const partialProfile = {
      composite_score: 60,
      profile: {
        call_experience: 72,
        trust: null,
        satisfaction: 65,
        hire_rate: null,
        recency: 80,
      },
    };
    vi.mocked(apiGet)
      .mockResolvedValueOnce(mockDashboard)
      .mockResolvedValueOnce(partialProfile);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { profileScores: typeof partialProfile.profile };
    expect(data.profileScores?.call_experience).toBe(72);
    expect(data.profileScores?.trust).toBeNull();
    expect(data.profileScores?.hire_rate).toBeNull();
  });

  it("loader returns monthly_history with 6 entries", async () => {
    vi.mocked(apiGet)
      .mockResolvedValueOnce(mockDashboard)
      .mockResolvedValueOnce(mockProfile);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = await res.json() as { dashboard: { monthly_history: unknown[] } };
    expect(data.dashboard.monthly_history).toHaveLength(6);
  });

  it("loader returns empty monthly_history when API returns empty", async () => {
    const emptyDashboard = { ...mockDashboard, monthly_history: [] };
    vi.mocked(apiGet)
      .mockResolvedValueOnce(emptyDashboard)
      .mockResolvedValueOnce(mockProfile);

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = await res.json() as { dashboard: { monthly_history: unknown[] } };
    expect(data.dashboard.monthly_history).toHaveLength(0);
  });

  it("loader marks new expert (null score + 0 leads)", async () => {
    const newExpertDashboard = {
      ...mockDashboard,
      composite_score: null,
      quality_tier: "New" as const,
      month_stats: { ...mockDashboard.month_stats, leads_received: 0 },
    };
    vi.mocked(apiGet)
      .mockResolvedValueOnce(newExpertDashboard)
      .mockResolvedValueOnce({ composite_score: null, profile: null });

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/analytics"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = await res.json() as {
      dashboard: { composite_score: null; month_stats: { leads_received: number } };
    };
    expect(data.dashboard.composite_score).toBeNull();
    expect(data.dashboard.month_stats.leads_received).toBe(0);
  });
});

// ── Helper unit tests ─────────────────────────────────────────────────────────

describe("getTierConfig", () => {
  it("Top tier returns gold badge class and correct label", () => {
    const config = getTierConfig("Top");
    expect(config.label).toBe("Expert Top");
    expect(config.badgeClass).toContain("yellow");
  });

  it("all four tiers return distinct labels and badge classes", () => {
    const tiers = ["New", "Rising", "Established", "Top"] as const;
    const results = tiers.map(getTierConfig);
    const labels = results.map((r) => r.label);
    const classes = results.map((r) => r.badgeClass);
    // All labels are distinct
    expect(new Set(labels).size).toBe(4);
    // All badge classes are distinct
    expect(new Set(classes).size).toBe(4);
    // Specific checks
    expect(results[0].label).toBe("Nouvel Expert");
    expect(results[1].label).toBe("Expert Prometteur");
    expect(results[2].label).toBe("Expert Confirmé");
    expect(results[3].label).toBe("Expert Top");
  });
});

describe("formatMonthLabel", () => {
  it("converts YYYY-MM to short French month", () => {
    const result = formatMonthLabel("2026-02");
    // fr-FR short month for February is "févr." or "fév." depending on locale
    expect(result.toLowerCase()).toMatch(/f[eé]v/);
  });

  it("converts January correctly", () => {
    const result = formatMonthLabel("2026-01");
    expect(result.toLowerCase()).toMatch(/janv?/);
  });
});

describe("safePct", () => {
  it("returns 0 when denominator is 0", () => {
    expect(safePct(5, 0)).toBe(0);
    expect(safePct(0, 0)).toBe(0);
  });

  it("calculates percentage correctly", () => {
    expect(safePct(3, 10)).toBe(30);
    expect(safePct(1, 4)).toBe(25);
    expect(safePct(10, 10)).toBe(100);
  });
});
