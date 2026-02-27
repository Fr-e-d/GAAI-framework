import { Form, Link, redirect, useActionData } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import {
  createServerClient,
  parseCookieHeader,
  serializeCookieHeader,
} from "@supabase/ssr";
import type { CookieOptions } from "@supabase/ssr";
import { z } from "zod";
import { Button } from "~/components/ui/button";
import { Input } from "~/components/ui/input";
import { Label } from "~/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "~/components/ui/card";
import { apiPost } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";

const SignupSchema = z.object({
  email: z.string().email("Email invalide"),
  password: z.string().min(8, "Le mot de passe doit contenir au moins 8 caractères"),
});

type ActionData =
  | { success: true }
  | { success: false; fieldErrors?: Record<string, string[]>; error?: string };

export async function loader({ request, context }: LoaderFunctionArgs) {
  const env = context.cloudflare.env;
  // AC3: Already authenticated → redirect
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
  if (user) throw redirect("/dashboard");
  return Response.json({});
}

export async function action({ request, context }: ActionFunctionArgs) {
  const env = context.cloudflare.env;
  const formData = await request.formData();
  const email = String(formData.get("email") ?? "");
  const password = String(formData.get("password") ?? "");

  // Server-side validation
  const parsed = SignupSchema.safeParse({ email, password });
  if (!parsed.success) {
    return Response.json(
      { success: false, fieldErrors: parsed.error.flatten().fieldErrors },
      { status: 422 },
    );
  }

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

  const { data: signUpData, error: signUpError } =
    await supabase.auth.signUp({ email, password });

  if (signUpError) {
    let errorMsg = signUpError.message;
    if (
      signUpError.message.toLowerCase().includes("already") ||
      signUpError.message.toLowerCase().includes("email")
    ) {
      errorMsg = "Un compte existe déjà avec cet email.";
    } else if (signUpError.message.toLowerCase().includes("password")) {
      errorMsg = "Mot de passe trop faible.";
    }
    return Response.json({ success: false, error: errorMsg }, { status: 400 });
  }

  const userId = signUpData.user?.id;
  if (!userId) {
    return Response.json(
      { success: false, error: "Erreur lors de la création du compte." },
      { status: 500 },
    );
  }

  // Get the access token from the session
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const token = session?.access_token ?? "";

  // POST /api/experts/register — create expert record
  try {
    await apiPost(env, token, "/api/experts/register", { email });
  } catch {
    // Race condition recovery: if register fails, the auth layout loader will retry on next login.
    // Display error to prompt retry.
    return Response.json(
      {
        success: false,
        error:
          "Compte créé mais erreur lors de l'inscription. Veuillez vous connecter pour réessayer.",
      },
      { status: 500, headers: responseHeaders },
    );
  }

  // PostHog: expert.signup_completed
  await captureEvent(env, `expert:${userId}`, "expert.signup_completed", {
    email_domain: email.split("@")[1] ?? "unknown",
  });

  return redirect("/onboarding?step=1", { headers: responseHeaders });
}

export default function SignupPage() {
  const actionData = useActionData() as ActionData | undefined;

  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Créer un compte</CardTitle>
          <CardDescription>
            Rejoignez Callibrate pour recevoir des leads qualifiés
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form method="post" className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                name="email"
                type="email"
                required
                autoComplete="email"
                placeholder="vous@exemple.com"
              />
              {actionData &&
                !actionData.success &&
                actionData.fieldErrors?.email?.map((e) => (
                  <p key={e} className="text-sm text-destructive">
                    {e}
                  </p>
                ))}
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Mot de passe</Label>
              <Input
                id="password"
                name="password"
                type="password"
                required
                autoComplete="new-password"
                placeholder="Minimum 8 caractères"
              />
              <p className="text-xs text-muted-foreground">Minimum 8 caractères</p>
              {actionData &&
                !actionData.success &&
                actionData.fieldErrors?.password?.map((e) => (
                  <p key={e} className="text-sm text-destructive">
                    {e}
                  </p>
                ))}
            </div>
            {actionData && !actionData.success && actionData.error && (
              <p className="text-sm text-destructive">{actionData.error}</p>
            )}
            <Button type="submit" className="w-full">
              Créer mon compte
            </Button>
            <p className="text-center text-sm text-muted-foreground">
              Déjà un compte ?{" "}
              <Link to="/login" className="underline hover:text-foreground">
                Se connecter
              </Link>
            </p>
          </Form>
        </CardContent>
      </Card>
    </div>
  );
}
