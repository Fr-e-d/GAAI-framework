import { describe, it, expect, vi } from "vitest";
import { loader } from "../app/routes/_layout";

// Mock the session module
vi.mock("../app/lib/session.server", () => ({
  requireSession: vi.fn(),
}));

import { requireSession } from "../app/lib/session.server";

const mockEnv: Env = {
  CORE_API_URL: "http://localhost:8787",
  SUPABASE_URL: "https://test.supabase.co",
  SUPABASE_ANON_KEY: "test-anon-key",
};

function makeRequest(cookieHeader?: string): Request {
  return new Request("https://app.callibrate.io/dashboard", {
    headers: cookieHeader ? { Cookie: cookieHeader } : {},
  });
}

describe("_layout loader", () => {
  it("redirects to /login when no session cookie present", async () => {
    vi.mocked(requireSession).mockImplementationOnce(async () => {
      const { redirect } = await import("react-router");
      throw redirect("/login");
    });

    const request = makeRequest();
    const context = {
      cloudflare: { env: mockEnv, ctx: {} as ExecutionContext },
    };

    let caughtResponse: Response | undefined;
    try {
      await loader({ request, context, params: {} } as Parameters<typeof loader>[0]);
    } catch (err) {
      if (err instanceof Response) {
        caughtResponse = err;
      }
    }

    expect(caughtResponse).toBeDefined();
    expect(caughtResponse?.status).toBe(302);
    expect(caughtResponse?.headers.get("Location")).toBe("/login");
  });

  it("returns user data when session is valid", async () => {
    const mockUser = { id: "user-123", email: "test@example.com" };
    vi.mocked(requireSession).mockResolvedValueOnce({
      session: { user: mockUser, token: "token-abc" },
      responseHeaders: new Headers(),
    });

    const request = makeRequest("sb-access-token=valid");
    const context = {
      cloudflare: { env: mockEnv, ctx: {} as ExecutionContext },
    };

    const response = await loader({
      request,
      context,
      params: {},
    } as Parameters<typeof loader>[0]);

    expect(response.status).toBe(200);
    const data = await response.json() as { user: typeof mockUser };
    expect(data.user.id).toBe("user-123");
  });
});
