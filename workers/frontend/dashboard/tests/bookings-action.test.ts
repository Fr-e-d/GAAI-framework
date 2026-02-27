import { describe, it, expect, vi, beforeEach } from "vitest";

// Mocks must be defined BEFORE imports of mocked modules
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

vi.mock("../app/lib/api.server", () => ({
  apiGet: vi.fn(),
  apiPost: vi.fn(),
  apiDeleteWithBody: vi.fn(),
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
import { apiGet, apiPost, apiDeleteWithBody } from "../app/lib/api.server";
import { captureEvent } from "../app/lib/posthog.server";
import { loader, action } from "../app/routes/dashboard.bookings";

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

type RawBooking = {
  id: string;
  starts_at: string;
  ends_at: string;
  status: "held" | "confirmed" | "cancelled";
  meeting_url: string | null;
  cancel_reason: string | null;
  prospect: { id: string; email: string | null; name: string | null } | null;
  created_at: string;
};

function makeBooking(overrides: Partial<RawBooking> = {}): RawBooking {
  return {
    id: "booking-1",
    starts_at: "2026-03-06T14:00:00.000Z",
    ends_at: "2026-03-06T14:20:00.000Z",
    status: "confirmed",
    meeting_url: "https://meet.google.com/abc-def-ghi",
    cancel_reason: null,
    prospect: {
      id: "prospect-1",
      email: "prospect@example.com",
      name: "Jean Dupont",
    },
    created_at: new Date(Date.now() - 86_400_000).toISOString(),
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

describe("bookings loader", () => {
  it("fetches bookings with default params (upcoming, page=1)", async () => {
    const mockBookings = [makeBooking()];
    vi.mocked(apiGet).mockResolvedValueOnce({
      bookings: mockBookings,
      total: 1,
      page: 1,
      per_page: 20,
    });

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/bookings"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as {
      bookings: (RawBooking & { formatted_datetime: string })[];
      total: number;
      page: number;
      per_page: number;
      period: string;
      userId: string;
    };
    expect(data.bookings).toHaveLength(1);
    expect(data.total).toBe(1);
    expect(data.userId).toBe("user-1");
    expect(data.period).toBe("upcoming");
    // Verify formatted_datetime is pre-formatted
    expect(typeof data.bookings[0].formatted_datetime).toBe("string");
    expect(data.bookings[0].formatted_datetime.length).toBeGreaterThan(0);

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/bookings",
      { period: "upcoming", page: "1", per_page: "20" },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.bookings_viewed",
      { period: "upcoming" },
    );
  });

  it("fetches bookings with period=past from URL", async () => {
    vi.mocked(apiGet).mockResolvedValueOnce({ bookings: [], total: 0, page: 1, per_page: 20 });

    await loader({
      request: new Request("https://app.callibrate.io/dashboard/bookings?period=past"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(vi.mocked(apiGet)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/experts/user-1/bookings",
      { period: "past", page: "1", per_page: "20" },
    );
  });

  it("returns empty bookings when API fails (graceful degradation)", async () => {
    vi.mocked(apiGet).mockRejectedValueOnce(new Error("Network error"));

    const res = await loader({
      request: new Request("https://app.callibrate.io/dashboard/bookings"),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(res.status).toBe(200);
    const data = await res.json() as { bookings: unknown[]; total: number };
    expect(data.bookings).toHaveLength(0);
    expect(data.total).toBe(0);
  });
});

// ── Action — cancel ────────────────────────────────────────────────────────────

describe("bookings action — cancel", () => {
  it("calls cancel endpoint with empty body (no reason)", async () => {
    vi.mocked(apiDeleteWithBody).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({ intent: "cancel", bookingId: "booking-1" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean; intent: string; bookingId: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("cancel");
    expect(body.bookingId).toBe("booking-1");

    expect(vi.mocked(apiDeleteWithBody)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/bookings/booking-1",
      {},
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.booking_cancelled",
      { booking_id: "booking-1", has_reason: false },
    );
  });

  it("calls cancel endpoint with reason body", async () => {
    vi.mocked(apiDeleteWithBody).mockResolvedValueOnce({ success: true });

    const fd = makeFormData({
      intent: "cancel",
      bookingId: "booking-1",
      cancel_reason: "Je dois annuler pour raisons personnelles.",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    expect(vi.mocked(apiDeleteWithBody)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/bookings/booking-1",
      { reason: "Je dois annuler pour raisons personnelles." },
    );
  });

  it("returns 400 when bookingId is missing on cancel", async () => {
    const fd = makeFormData({ intent: "cancel" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(false);
    expect(vi.mocked(apiDeleteWithBody)).not.toHaveBeenCalled();
  });

  it("returns 500 when cancel API throws", async () => {
    vi.mocked(apiDeleteWithBody).mockRejectedValueOnce(new Error("API failure"));

    const fd = makeFormData({ intent: "cancel", bookingId: "booking-1" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
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

// ── Action — reschedule ────────────────────────────────────────────────────────

describe("bookings action — reschedule", () => {
  it("calls reschedule endpoint with computed new_end_at (+20min)", async () => {
    vi.mocked(apiPost).mockResolvedValueOnce({ success: true });

    // Use a far-future date so the "must be in future" check always passes
    const fd = makeFormData({
      intent: "reschedule",
      bookingId: "booking-1",
      new_start_at: "2030-01-01T10:00",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(200);
    const body = await res.json() as { success: boolean; intent: string; bookingId: string };
    expect(body.success).toBe(true);
    expect(body.intent).toBe("reschedule");
    expect(body.bookingId).toBe("booking-1");

    expect(vi.mocked(apiPost)).toHaveBeenCalledWith(
      expect.anything(),
      "token-abc",
      "/api/bookings/booking-1/reschedule",
      {
        new_start_at: "2030-01-01T10:00:00.000Z",
        new_end_at: "2030-01-01T10:20:00.000Z",
      },
    );
    expect(vi.mocked(captureEvent)).toHaveBeenCalledWith(
      expect.anything(),
      "expert:user-1",
      "expert.booking_rescheduled",
      { booking_id: "booking-1", new_start_at: "2030-01-01T10:00:00.000Z" },
    );
  });

  it("returns 422 when new_start_at is empty", async () => {
    const fd = makeFormData({ intent: "reschedule", bookingId: "booking-1", new_start_at: "" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; error: string };
    expect(body.success).toBe(false);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 422 when new_start_at is in the past", async () => {
    // Use a clearly past date
    const fd = makeFormData({
      intent: "reschedule",
      bookingId: "booking-1",
      new_start_at: "2020-01-01T00:00",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(422);
    const body = await res.json() as { success: boolean; error: string };
    expect(body.success).toBe(false);
    expect(body.error).toMatch(/futur/);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 400 when bookingId is missing on reschedule", async () => {
    const fd = makeFormData({ intent: "reschedule", new_start_at: "2030-01-01T10:00" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
        method: "POST",
        body: fd,
      }),
      context: makeCtx(),
      params: {},
    } as Parameters<typeof action>[0]);

    expect(res.status).toBe(400);
    const body = await res.json() as { success: boolean };
    expect(body.success).toBe(false);
    expect(vi.mocked(apiPost)).not.toHaveBeenCalled();
  });

  it("returns 500 when reschedule API throws", async () => {
    vi.mocked(apiPost).mockRejectedValueOnce(new Error("Reschedule API failed"));

    const fd = makeFormData({
      intent: "reschedule",
      bookingId: "booking-1",
      new_start_at: "2030-01-01T10:00",
    });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
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

// ── Action — unknown intent ────────────────────────────────────────────────────

describe("bookings action — unknown intent", () => {
  it("returns 400 for unknown intent", async () => {
    const fd = makeFormData({ intent: "doSomethingUnknown" });
    const res = await action({
      request: new Request("https://app.callibrate.io/dashboard/bookings", {
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
