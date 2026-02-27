import { Form, Link, useActionData } from "react-router";
import type { ActionFunctionArgs } from "react-router";
import {
  createServerClient,
  parseCookieHeader,
} from "@supabase/ssr";
import { Button } from "~/components/ui/button";
import { Input } from "~/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "~/components/ui/card";

type ActionData =
  | { success: true }
  | { success: false; error: string };

export async function action({ request, context }: ActionFunctionArgs) {
  const env = context.cloudflare.env;
  const formData = await request.formData();
  const email = String(formData.get("email") ?? "").trim();

  if (!email) {
    return Response.json({ success: false, error: "Email requis." }, { status: 422 });
  }

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

  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${new URL(request.url).origin}/reset-password`,
  });

  if (error) {
    return Response.json(
      { success: false, error: "Erreur lors de l'envoi. Vérifiez votre email." },
      { status: 400 },
    );
  }

  return Response.json({ success: true });
}

export default function ForgotPasswordPage() {
  const actionData = useActionData() as ActionData | undefined;

  if (actionData?.success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle className="text-2xl">Email envoyé</CardTitle>
            <CardDescription>
              Si un compte existe avec cet email, vous recevrez un lien de réinitialisation.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/login">
              <Button variant="outline" className="w-full">
                Retour à la connexion
              </Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Mot de passe oublié</CardTitle>
          <CardDescription>
            Entrez votre email pour recevoir un lien de réinitialisation
          </CardDescription>
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
                placeholder="vous@exemple.com"
              />
            </div>
            {actionData && !actionData.success && (
              <p className="text-sm text-destructive">{actionData.error}</p>
            )}
            <Button type="submit" className="w-full">
              Envoyer le lien
            </Button>
            <div className="text-center">
              <Link
                to="/login"
                className="text-sm text-muted-foreground underline hover:text-foreground"
              >
                Retour à la connexion
              </Link>
            </div>
          </Form>
        </CardContent>
      </Card>
    </div>
  );
}
