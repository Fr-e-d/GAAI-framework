import { createServerClient, parseCookieHeader, serializeCookieHeader } from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import { redirect } from "react-router";

export type SessionUser = {
  id: string;
  email: string | undefined;
};

export type Session = {
  user: SessionUser;
  token: string;
};

/**
 * Creates a Supabase server client bound to the current request's cookies.
 * Returns both the client and a response headers object that will carry
 * any Set-Cookie headers for token refresh.
 */
function createSupabaseServerClient(request: Request, env: Env) {
  const responseHeaders = new Headers();

  const supabase = createServerClient(
    env.SUPABASE_URL,
    env.SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return parseCookieHeader(request.headers.get("Cookie") ?? "") as {
            name: string;
            value: string;
          }[];
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          cookiesToSet.forEach(({ name, value, options }) => {
            responseHeaders.append(
              "Set-Cookie",
              serializeCookieHeader(name, value, options),
            );
          });
        },
      },
    },
  );

  return { supabase, responseHeaders };
}

/**
 * Reads and validates the session from the request cookies.
 * Returns { user, token } if authenticated, null otherwise.
 *
 * Uses getUser() (not getSession()) — validates JWT server-side via Supabase.
 */
export async function getSession(
  request: Request,
  env: Env,
): Promise<{ session: Session | null; responseHeaders: Headers }> {
  const { supabase, responseHeaders } = createSupabaseServerClient(request, env);

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return { session: null, responseHeaders };
  }

  const {
    data: { session: supabaseSession },
  } = await supabase.auth.getSession();

  const token = supabaseSession?.access_token ?? "";

  return {
    session: {
      user: { id: user.id, email: user.email },
      token,
    },
    responseHeaders,
  };
}

/**
 * Requires an authenticated session. Throws a redirect to /login if not found.
 * Use in React Router loaders for protected routes.
 *
 * Usage:
 *   const { session, responseHeaders } = await requireSession(request, context.cloudflare.env);
 */
export async function requireSession(
  request: Request,
  env: Env,
): Promise<{ session: Session; responseHeaders: Headers }> {
  const { session, responseHeaders } = await getSession(request, env);

  if (!session) {
    throw redirect("/login");
  }

  return { session, responseHeaders };
}
