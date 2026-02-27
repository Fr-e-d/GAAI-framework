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
import { loader, action } from "../app/routes/dashboard.settings";

const mockEnv: Env = {
  CORE_API_URL: "http://localhost:8787",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_ANON_KEY: "test-anon-key",
};

const mockSession = {
  user: { id: "user-1", email: "test@example.com" },
  token: "token-abc",
};

const mockProfile = {
  id: "user-1",
  display_name: "Jean Expert",
  headline: "Expert n8n",
  bio: "Bio de test",
  rate_min: 100,
  rate_max: 200,
  availability: "immediate",
  profile: { skills: ["n8n"], verticals: [] },
  preferences: { career_stage: "senior", work_mode: "remote", availability: "immediate" },
  admissibility_criteria: { min_project_duration_days: 30 },
  outcome_tags: [],
  gcal_refresh_token: null,
  gcal_email: null,
};

function makeCtx(env = mockEnv) {
  return { cloudflare: { env, ctx: {} as ExecutionContext } };
}

function makeFormData(fields: Record<string, string | string[]>): FormData {
  const fd = new FormData();
  for (const [key, val] of Object.entries(fields)) {
    if (Array.isArray(val)) {
      for (const v of val) fd.append(key, v);
    } else {
      fd.append(key, val);
    }
  }
  return fd;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(requireSession).mockResolvedValue({
    session: mockSession,
    responseHeaders: new Headers(),
  } as Awaited<ReturnType<typeof requireSession>>);
  vi.mocked(apiGet).mockResolvedValue(mockProfile);
  vi.mocked(apiPatch).mockResolvedValue({});
  vi.mocked(captureEvent).mockResolvedValue(undefined);
});

// ── Loader tests ──────────────────────────────────────────────────────────────

describe("settings loader", () => {
  it("returns profile data", async () => {
    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/settings"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { profile: unknown; userId: string };
    expect(data.profile).toBeDefined();
    expect(data.userId).toBe("user-1");
  });

  it("returns null profile when API fails", async () => {
    vi.mocked(apiGet).mockRejectedValue(new Error("Network error"));
    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/settings"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);
    const data = await res.json() as { profile: unknown };
    expect(data.profile).toBeNull();
  });
});

// ── Action — identite ─────────────────────────────────────────────────────────

describe("settings action — identite", () => {
  it("returns success:true on valid data", async () => {
    const fd = makeFormData({
      intent: "identite",
      display_name: "Jean Expert",
      headline: "Expert n8n & automatisation IA",
      bio: "",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean; section: string };
    expect(body.success).toBe(true);
    expect(body.section).toBe("identite");
    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      expect.objectContaining({ display_name: "Jean Expert", headline: "Expert n8n & automatisation IA" }),
    );
  });

  it("returns 422 when display_name is missing", async () => {
    const fd = makeFormData({
      intent: "identite",
      display_name: "",
      headline: "Expert n8n",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; errors: Record<string, unknown> };
    expect(body.success).toBe(false);
    expect(body.errors.display_name).toBeDefined();
  });

  it("returns 500 on API error", async () => {
    vi.mocked(apiPatch).mockRejectedValue(new Error("API failure"));
    const fd = makeFormData({
      intent: "identite",
      display_name: "Jean Expert",
      headline: "Expert n8n",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(false);
  });
});

// ── Action — expertise ────────────────────────────────────────────────────────

describe("settings action — expertise", () => {
  it("returns success:true with valid skills", async () => {
    const fd = makeFormData({
      intent: "expertise",
      skills: ["n8n", "Python"],
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(true);
    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      expect.objectContaining({ profile: { skills: ["n8n", "Python"], verticals: [] } }),
    );
  });

  it("returns 422 when skills empty", async () => {
    const fd = makeFormData({ intent: "expertise" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; errors: Record<string, unknown> };
    expect(body.success).toBe(false);
    expect(body.errors.skills).toBeDefined();
  });
});

// ── Action — admissibilite ────────────────────────────────────────────────────

describe("settings action — admissibilite", () => {
  it("saves with correct fraction conversion for required_stack_overlap_min", async () => {
    const fd = makeFormData({
      intent: "admissibilite",
      required_stack_overlap_min: "80",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      expect.objectContaining({
        admissibility_criteria: expect.objectContaining({
          required_stack_overlap_min: expect.closeTo(0.8, 5),
        }),
      }),
    );
  });

  it("returns success:true with all optional fields absent", async () => {
    const fd = makeFormData({ intent: "admissibilite" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/settings", { method: "POST", body: fd }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(true);
    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      expect.objectContaining({ admissibility_criteria: {} }),
    );
  });
});
