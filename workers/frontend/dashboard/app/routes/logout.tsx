import { redirect } from "react-router";
import type { ActionFunctionArgs } from "react-router";
import { createServerClient, parseCookieHeader, serializeCookieHeader } from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";

export async function action({ request, context }: ActionFunctionArgs) {
  const env = context.cloudflare.env;
  const responseHeaders = new Headers();

  const supabase = createServerClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
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
  });

  await supabase.auth.signOut();
  return redirect("/login", { headers: responseHeaders });
}

// No GET handler — logout is POST only (form submission from header)
export function loader() {
  return redirect("/dashboard");
}
