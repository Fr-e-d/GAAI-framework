import { Form, Link, redirect, useActionData } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import {
  createServerClient,
  parseCookieHeader,
  serializeCookieHeader,
} from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import { Button } from "~/components/ui/button";
import { Input } from "~/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "~/components/ui/card";
import { apiGet } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { inferOnboardingStep } from "~/lib/onboarding";

export async function loader({ request, context }: LoaderFunctionArgs) {
  const env = context.cloudflare.env;
  // AC3: Already authenticated → redirect to dashboard or onboarding
  const supabase = createServerClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get("Cookie") ?? "") as {
          name: string;
          value: string;
        }[];
      },
      setAll() {},
    },
  });
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) {
    const {
      data: { session },
    } = await supabase.auth.getSession();
    const token = session?.access_token ?? "";
    const profile = await apiGet<{ display_name: string | null }>(
      env,
      token,
      `/api/experts/${user.id}/profile`,
    ).catch(() => null);
    if (!profile?.display_name) {
      throw redirect(`/onboarding?step=${inferOnboardingStep(profile)}`);
    }
    throw redirect("/dashboard");
  }
  return Response.json({});
}

export async function action({ request, context }: ActionFunctionArgs) {
  const env = context.cloudflare.env;
  const formData = await request.formData();
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");

  const responseHeaders = new Headers();

  const supabase = createServerClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    cookies: {
      getAll() {
        return parseCookieHeader(request.headers.get("Cookie") ?? "") as {
          name: string;
          value: string;
        }[];
      },
      setAll(
        cookiesToSet: { name: string; value: string; options: CookieOptions }[],
      ) {
        cookiesToSet.forEach(({ name, value, options }) => {
          responseHeaders.append(
            "Set-Cookie",
            serializeCookieHeader(name, value, options),
          );
        });
      },
    },
  });

  const { data: signInData, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    return Response.json({ error: "Email ou mot de passe incorrect." }, { status: 400 });
  }

  const userId = signInData.user?.id ?? "";
  const token = signInData.session?.access_token ?? "";

  // PostHog: expert.login
  await captureEvent(env, `expert:${userId}`, "expert.login", {});

  // AC2: Check if onboarding complete (display_name present)
  const profile = await apiGet<{ display_name: string | null }>(
    env,
    token,
    `/api/experts/${userId}/profile`,
  ).catch(() => null);

  if (!profile?.display_name) {
    const step = inferOnboardingStep(profile);
    return redirect(`/onboarding?step=${step}`, { headers: responseHeaders });
  }

  return redirect("/dashboard", { headers: responseHeaders });
}

export default function LoginPage() {
  const actionData = useActionData() as { error?: string } | undefined;

  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Callibrate</CardTitle>
        </CardHeader>
        <CardContent>
          <Form method="post" className="space-y-4">
            <div className="space-y-2">
              <label htmlFor="email" className="text-sm font-medium">
                Email
              </label>
              <Input
                id="email"
                name="email"
                type="email"
                required
                autoComplete="email"
              />
            </div>
            <div className="space-y-2">
              <label htmlFor="password" className="text-sm font-medium">
                Mot de passe
              </label>
              <Input
                id="password"
                name="password"
                type="password"
                required
                autoComplete="current-password"
              />
            </div>
            {actionData?.error && (
              <p className="text-sm text-destructive">{actionData.error}</p>
            )}
            <Button type="submit" className="w-full">
              Se connecter
            </Button>
            <div className="text-center">
              <Link
                to="/forgot-password"
                className="text-sm text-muted-foreground underline hover:text-foreground"
              >
                Mot de passe oublié ?
              </Link>
            </div>
            <p className="text-center text-sm text-muted-foreground">
              Pas encore de compte ?{" "}
              <Link to="/signup" className="underline hover:text-foreground">
                Créer un compte
              </Link>
            </p>
          </Form>
        </CardContent>
      </Card>
    </div>
  );
}
