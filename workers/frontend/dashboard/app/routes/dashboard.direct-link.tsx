// E02S12 AC18/AC20: Direct Link Dashboard page
// Route: /dashboard/direct-link
// Displays the expert's direct booking link, quota usage, recent submissions.
// AC20: pricing explanation visible without scroll (above the fold).

import { Form, useLoaderData, useActionData, useFetcher } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useEffect, useRef, useState } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPatch, ApiError } from "~/lib/api.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";

// ── Types ────────────────────────────────────────────────────────────────────

type RecentSubmission = {
  booking_id: string;
  prospect_name: string | null;
  prospect_email: string | null;
  submitted_at: string | null;
  status: string | null;
};

type QuotaInfo = {
  used: number;
  limit: number;
  remaining: number;
  resets_at: string;
};

type DirectLinkInfo = {
  direct_link_url: string | null;
  quota: QuotaInfo;
  recent_submissions: RecentSubmission[];
};

type LoaderData = {
  directLinkInfo: DirectLinkInfo;
  userId: string;
};

type ActionData =
  | { success: true; intent: "rotate"; direct_link_url: string }
  | { success: false; intent: string; error: string };

// ── Loader ───────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const directLinkInfo = await apiGet<DirectLinkInfo>(
    env,
    session.token,
    `/api/experts/${userId}/direct-link`,
  ).catch(() => ({
    direct_link_url: null,
    quota: { used: 0, limit: 100, remaining: 100, resets_at: new Date().toISOString() },
    recent_submissions: [],
  }));

  return Response.json(
    { directLinkInfo, userId } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

// ── Action ───────────────────────────────────────────────────────────────────

export async function action({ request, context }: ActionFunctionArgs) {
  const { session } = await requireSession(request, context.cloudflare.env);
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const formData = await request.formData();
  const intent = String(formData.get("intent") ?? "");

  if (intent === "rotate") {
    try {
      const result = await apiPatch<{ direct_link_url: string; message: string }>(
        env,
        session.token,
        `/api/experts/${userId}/direct-link/rotate`,
        {},
      );
      return Response.json({
        success: true,
        intent: "rotate",
        direct_link_url: result.direct_link_url,
      } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        { success: false, intent: "rotate", error: "Failed to rotate link." } satisfies ActionData,
        { status },
      );
    }
  }

  return Response.json(
    { success: false, intent, error: "Unknown action." } satisfies ActionData,
    { status: 400 },
  );
}

// ── Page component ────────────────────────────────────────────────────────────

export default function DirectLinkPage() {
  const { directLinkInfo } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const fetcher = useFetcher();
  const linkRef = useRef<HTMLInputElement>(null);
  const [currentUrl, setCurrentUrl] = useState(directLinkInfo.direct_link_url ?? "");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!actionData) return;
    if (actionData.success && actionData.intent === "rotate") {
      setCurrentUrl(actionData.direct_link_url);
      toast.success("Direct link rotated. Previous links are now invalid.");
    } else if (!actionData.success) {
      toast.error(actionData.error);
    }
  }, [actionData]);

  const { quota, recent_submissions } = directLinkInfo;
  const quotaPercent = Math.round((quota.used / quota.limit) * 100);
  const resetDate = new Date(quota.resets_at).toLocaleDateString("fr-FR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

  function copyLink() {
    if (!currentUrl) return;
    navigator.clipboard.writeText(currentUrl).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  const isRotating = fetcher.state !== "idle";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Lien direct</h1>
        <p className="text-muted-foreground mt-1">
          Partagez votre lien direct pour recevoir des demandes de réservation sans passer par le matching Callibrate.
        </p>
      </div>

      {/* AC20: Pricing explanation — visible without scroll (above fold) */}
      <Card className="border-amber-200 bg-amber-50">
        <CardHeader className="pb-2">
          <CardTitle className="text-base text-amber-900">Tarification du lien direct</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-amber-800 space-y-1">
          <p>
            Les réservations via votre lien direct ne sont <strong>pas facturées</strong> par Callibrate.
            Vous conservez 100 % des honoraires pour ces clients.
          </p>
          <p>
            En échange, un quota de <strong>{quota.limit} demandes par mois</strong> s&apos;applique.
            Les réservations via le matching Callibrate restent soumises à la grille tarifaire habituelle.
          </p>
        </CardContent>
      </Card>

      {/* Direct link copy */}
      <Card>
        <CardHeader>
          <CardTitle>Votre lien de réservation direct</CardTitle>
          <CardDescription>
            Partagez ce lien à vos clients existants, sur votre site ou votre profil LinkedIn.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {currentUrl ? (
            <>
              <div className="flex items-center gap-2">
                <input
                  ref={linkRef}
                  readOnly
                  value={currentUrl}
                  className="flex-1 h-9 rounded-md border border-input bg-background px-3 py-1 text-sm font-mono"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={copyLink}
                >
                  {copied ? "Copié !" : "Copier"}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Ce lien est unique et signé. Il peut être partagé librement.
              </p>
            </>
          ) : (
            <p className="text-sm text-muted-foreground">
              Votre lien direct n&apos;est pas disponible pour le moment. Rechargez la page.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Quota usage */}
      <Card>
        <CardHeader>
          <CardTitle>Quota mensuel</CardTitle>
          <CardDescription>
            Réinitialisation le {resetDate}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-muted-foreground">{quota.used} / {quota.limit} demandes utilisées</span>
            <span className={quota.remaining < 10 ? "text-amber-600 font-medium" : "text-muted-foreground"}>
              {quota.remaining} restantes
            </span>
          </div>
          {/* Quota progress bar */}
          <div className="w-full bg-gray-100 rounded-full h-2">
            <div
              className={[
                "h-2 rounded-full transition-all",
                quotaPercent >= 90 ? "bg-red-500" : quotaPercent >= 70 ? "bg-amber-500" : "bg-primary",
              ].join(" ")}
              style={{ width: `${Math.min(100, quotaPercent)}%` }}
            />
          </div>
        </CardContent>
      </Card>

      {/* Recent submissions */}
      {recent_submissions.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Demandes récentes</CardTitle>
            <CardDescription>Les 3 dernières demandes reçues via votre lien direct.</CardDescription>
          </CardHeader>
          <CardContent>
            <ul className="space-y-3">
              {recent_submissions.map((sub) => (
                <li key={sub.booking_id} className="flex items-center justify-between text-sm gap-2">
                  <div>
                    <p className="font-medium">{sub.prospect_name ?? "Anonyme"}</p>
                    <p className="text-muted-foreground text-xs">
                      {sub.submitted_at
                        ? new Date(sub.submitted_at).toLocaleDateString("fr-FR", {
                            day: "numeric",
                            month: "short",
                            hour: "2-digit",
                            minute: "2-digit",
                          })
                        : "—"}
                    </p>
                  </div>
                  <span className="text-xs text-muted-foreground bg-gray-100 px-2 py-0.5 rounded-full">
                    {sub.status ?? "—"}
                  </span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      {/* Rotate link */}
      <Card className="border-red-100">
        <CardHeader>
          <CardTitle className="text-base">Rotation du lien</CardTitle>
          <CardDescription>
            Générez un nouveau lien. <strong className="text-red-600">Tous les liens existants seront invalidés.</strong>
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form method="post">
            <input type="hidden" name="intent" value="rotate" />
            <Button
              type="submit"
              variant="destructive"
              size="sm"
              disabled={isRotating}
            >
              {isRotating ? "Rotation en cours..." : "Générer un nouveau lien"}
            </Button>
          </Form>
        </CardContent>
      </Card>
    </div>
  );
}
