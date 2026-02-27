import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock session
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

// Mock API client
vi.mock("../app/lib/api.server", () => ({
  apiPost: vi.fn(),
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

// Mock PostHog
vi.mock("../app/lib/posthog.server", () => ({
  captureEvent: vi.fn(),
}));

import { requireSession } from "../app/lib/session.server";
import { apiPatch, apiGet } from "../app/lib/api.server";
import { action, loader } from "../app/routes/onboarding";

const mockEnv: Env = {
  CORE_API_URL: "http://localhost:8787",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_ANON_KEY: "test-anon-key",
};

const mockSession = {
  user: { id: "user-1", email: "test@example.com" },
  token: "token-abc",
};

function makeCtx(env = mockEnv) {
  return { cloudflare: { env, ctx: {} as ExecutionContext } };
}

function makeFormData(fields: Record<string, string | string[]>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    if (Array.isArray(v)) {
      v.forEach((val) => fd.append(k, val));
    } else {
      fd.append(k, v);
    }
  }
  return fd;
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(requireSession).mockResolvedValue({
    session: mockSession,
    responseHeaders: new Headers(),
  });
  vi.mocked(apiPatch).mockResolvedValue({});
  vi.mocked(apiGet).mockResolvedValue({
    id: "user-1",
    display_name: null,
    headline: null,
    bio: null,
    rate_min: null,
    rate_max: null,
    profile: null,
    preferences: null,
    outcome_tags: null,
    gcal_refresh_token: null,
    gcal_email: null,
  });
});

describe("onboarding loader", () => {
  it("returns step=1 from URL param", async () => {
    const req = new Request("https://app.callibrate.io/onboarding?step=1");
    const res = await loader({
      request: req,
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { step: number };
    expect(data.step).toBe(1);
  });

  it("clamps out-of-range step param to 1", async () => {
    const req = new Request("https://app.callibrate.io/onboarding?step=99");
    const res = await loader({
      request: req,
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = await res.json() as { step: number };
    expect(data.step).toBe(4); // clamped to max 4
  });

  it("defaults to step=1 for NaN param", async () => {
    const req = new Request("https://app.callibrate.io/onboarding?step=abc");
    const res = await loader({
      request: req,
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = await res.json() as { step: number };
    expect(data.step).toBe(1);
  });
});

describe("onboarding action — step 1", () => {
  it("redirects to ?step=2 on valid data", async () => {
    const fd = makeFormData({
      step: "1",
      display_name: "Jean Expert",
      headline: "Expert n8n & automatisation IA",
      bio: "",
    });

    let caught: Response | undefined;
    let result: Response | undefined;
    try {
      result = (await action({
        request: new Request("https://app.callibrate.io/onboarding", {
          method: "POST",
          body: fd,
        }),
        context: makeCtx(),
        params: {},
      } as Parameters<typeof action>[0])) as Response;
    } catch (err) {
      if (err instanceof Response) caught = err;
    }

    const redirected = caught ?? result;
    expect(redirected).toBeDefined();
    if (redirected) {
      expect(redirected.status).toBe(302);
      expect(redirected.headers.get("Location")).toContain("step=2");
    }

    expect(vi.mocked(apiPatch)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/profile",
      expect.objectContaining({ display_name: "Jean Expert" }),
    );
  });

  it("returns 422 when display_name is missing", async () => {
    const fd = makeFormData({
      step: "1",
      display_name: "",
      headline: "Expert n8n",
    });

    const res = await action({
      request: new Request("https://app.callibrate.io/onboarding", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; errors: Record<string, unknown> };
    expect(body.success).toBe(false);
    expect(body.errors).toHaveProperty("display_name");
  });

  it("returns 422 when headline is missing", async () => {
    const fd = makeFormData({
      step: "1",
      display_name: "Jean Expert",
      headline: "",
    });

    const res = await action({
      request: new Request("https://app.callibrate.io/onboarding", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; errors: Record<string, unknown> };
    expect(body.success).toBe(false);
    expect(body.errors).toHaveProperty("headline");
  });
});

describe("onboarding action — step 2", () => {
  it("redirects to ?step=3 on valid data", async () => {
    const fd = makeFormData({
      step: "2",
      skills: ["n8n", "Python"],
      verticals: ["Workflow Automation"],
    });

    let caught: Response | undefined;
    let result: Response | undefined;
    try {
      result = (await action({
        request: new Request("https://app.callibrate.io/onboarding", {
          method: "POST",
          body: fd,
        }),
        context: makeCtx(),
        params: {},
      } as Parameters<typeof action>[0])) as Response;
    } catch (err) {
      if (err instanceof Response) caught = err;
    }

    const redirected = caught ?? result;
    expect(redirected).toBeDefined();
    if (redirected) {
      expect(redirected.status).toBe(302);
      expect(redirected.headers.get("Location")).toContain("step=3");
    }
  });

  it("returns 422 when no skills selected", async () => {
    const fd = makeFormData({ step: "2" });

    const res = await action({
      request: new Request("https://app.callibrate.io/onboarding", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; errors: Record<string, unknown> };
    expect(body.success).toBe(false);
    expect(body.errors).toHaveProperty("skills");
  });
});

describe("onboarding redirect — incomplete profile detection", () => {
  it("_layout.dashboard redirects to /onboarding when display_name is null", async () => {
    // requireSession is already mocked at module level; configured in beforeEach.
    // Override apiGet to return null display_name for this test.
    vi.mocked(apiGet).mockResolvedValue({
      display_name: null,
      profile: null,
      preferences: null,
    });

    const { loader: dashboardLoader } = await import(
      "../app/routes/_layout.dashboard"
    );

    let caught: Response | undefined;
    try {
      await dashboardLoader({
        request: new Request("https://app.callibrate.io/dashboard"),
        context: makeCtx(),
        params: {},
      } as Parameters<typeof dashboardLoader>[0]);
    } catch (err) {
      if (err instanceof Response) caught = err;
    }

    expect(caught).toBeDefined();
    expect(caught?.status).toBe(302);
    const loc = caught?.headers.get("Location");
    expect(loc).toContain("/onboarding");
    expect(loc).toContain("step=1");
  });
});
