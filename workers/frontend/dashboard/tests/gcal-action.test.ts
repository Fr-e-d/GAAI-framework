import { describe, it, expect, vi, beforeEach } from "vitest";

// Mocks must be defined BEFORE imports of mocked modules
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

vi.mock("../app/lib/api.server", () => ({
  apiGet: vi.fn(),
  apiDelete: vi.fn(),
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
import { apiGet, apiDelete } from "../app/lib/api.server";
import { captureEvent } from "../app/lib/posthog.server";
import { loader, action } from "../app/routes/dashboard.gcal";

// ── Test fixtures ──────────────────────────────────────────────────────────────

const mockEnv: Env = {
  CORE_API_URL: "http://localhost:8787",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_ANON_KEY: "test-anon-key",
};

const mockSession = {
  user: { id: "user-1", email: "test@example.com" },
  token: "token-abc",
};

const mockGcalStatusConnected = {
  connected: true,
  google_email: "expert@gmail.com",
  connected_at: "2026-02-27T10:00:00Z",
};

const mockGcalStatusDisconnected = {
  connected: false,
  google_email: null,
  connected_at: null,
};

const mockAvailabilityResponse = {
  slots: [
    { start: "2026-03-01T09:00:00Z", end: "2026-03-01T09:30:00Z" },
    { start: "2026-03-01T10:00:00Z", end: "2026-03-01T10:30:00Z" },
    { start: "2026-03-01T11:00:00Z", end: "2026-03-01T11:30:00Z" },
    { start: "2026-03-02T09:00:00Z", end: "2026-03-02T09:30:00Z" },
    { start: "2026-03-02T10:00:00Z", end: "2026-03-02T10:30:00Z" },
    { start: "2026-03-02T11:00:00Z", end: "2026-03-02T11:30:00Z" }, // 6th — should be sliced off
  ],
  metadata: { tz: "UTC", generated_at: "2026-02-27T12:00:00Z" },
};

function makeCtx(env = mockEnv) {
  return { cloudflare: { env, ctx: {} as ExecutionContext } };
}

function makeFormData(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [key, val] of Object.entries(fields)) {
    fd.append(key, val);
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

describe("gcal loader", () => {
  it("returns connected status with availability slots (sliced to 5)", async () => {
    vi.mocked(apiGet)
      .mockResolvedValueOnce(mockGcalStatusConnected) // gcal/status
      .mockResolvedValueOnce(mockAvailabilityResponse); // availability

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/gcal"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      gcalStatus: typeof mockGcalStatusConnected;
      slots: Array<{ start: string; end: string }>;
      generatedAt: string;
      userId: string;
    };
    expect(data.gcalStatus.connected).toBe(true);
    expect(data.gcalStatus.google_email).toBe("expert@gmail.com");
    expect(data.slots).toHaveLength(5); // sliced from 6
    expect(data.generatedAt).toBe("2026-02-27T12:00:00Z");
    expect(data.userId).toBe("user-1");
  });

  it("returns disconnected status without fetching availability", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce(mockGcalStatusDisconnected); // gcal/status only

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/gcal"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = (await res.json()) as {
      gcalStatus: typeof mockGcalStatusDisconnected;
      slots: null;
    };
    expect(data.gcalStatus?.connected).toBe(false);
    expect(data.slots).toBeNull();
    // Only 1 apiGet call (gcal/status) — no availability fetch when disconnected
    expect(vi.mocked(apiGet)).toHaveBeenCalledTimes(1);
  });

  it("returns null gcalStatus when gcal/status API fails", async () => {
    vi.mocked(apiGet).mockRejectedValueOnce(new Error("Network error"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/gcal"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    const data = (await res.json()) as { gcalStatus: null; slots: null };
    expect(data.gcalStatus).toBeNull();
    expect(data.slots).toBeNull();
  });
});

// ── Action — connect ──────────────────────────────────────────────────────────

describe("gcal action — connect", () => {
  it("redirects to OAuth auth URL", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce({
      auth_url: "https://accounts.google.com/o/oauth2/v2/auth?state=abc123",
    });

    const fd = makeFormData({ intent: "connect" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/gcal", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(302);
    expect(res.headers.get("Location")).toBe(
      "https://accounts.google.com/o/oauth2/v2/auth?state=abc123",
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.gcal_connect_started",
      {},
    );
  });

  it("returns 500 when auth-url API fails", async () => {
    vi.mocked(apiGet).mockRejectedValueOnce(new Error("API failure"));

    const fd = makeFormData({ intent: "connect" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/gcal", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = (await res.json()) as { success: boolean; action: string };
    expect(body.success).toBe(false);
    expect(body.action).toBe("connect");
  });
});

// ── Action — disconnect ────────────────────────────────────────────────────────

describe("gcal action — disconnect", () => {
  it("returns success on valid disconnect", async () => {
    vi.mocked(apiDelete).mockResolvedValueOnce({ disconnected: true });

    const fd = makeFormData({ intent: "disconnect" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/gcal", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = (await res.json()) as { success: boolean; action: string };
    expect(body.success).toBe(true);
    expect(body.action).toBe("disconnect");
    expect(vi.mocked(apiDelete)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/gcal/disconnect",
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.gcal_disconnected",
      {},
    );
  });

  it("returns error when disconnect API fails", async () => {
    vi.mocked(apiDelete).mockRejectedValueOnce(new Error("API failure"));

    const fd = makeFormData({ intent: "disconnect" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/gcal", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(500);
    const body = (await res.json()) as { success: boolean; action: string };
    expect(body.success).toBe(false);
    expect(body.action).toBe("disconnect");
  });
});
