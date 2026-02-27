import { Form, Link, useActionData, useLoaderData, useSearchParams } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState, useEffect } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPatch, ApiError } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import { Badge } from "~/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";
import { Input } from "~/components/ui/input";
import { Label } from "~/components/ui/label";
import { Progress } from "~/components/ui/progress";
import { Separator } from "~/components/ui/separator";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "~/components/ui/table";

// ── Lemon Squeezy global type (client-side only) ───────────────────────────────

declare global {
  interface Window {
    createLemonSqueezy?: () => void;
    LemonSqueezy?: {
      Setup: (config: { eventHandler: (event: { event: string }) => void }) => void;
      openUrl: (url: string) => void;
    };
  }
}

// ── Types ─────────────────────────────────────────────────────────────────────

type Transaction = {
  id: string;
  type: string;
  amount_cents: number;
  description: string | null;
  lead_id: string | null;
  created_at: string | null;
  formatted_date: string;
};

type BillingResponse = {
  credit_balance: number;
  ls_subscription_status: string | null;
  ls_subscription_id: string | null;
  spending_limit: number | null;
  max_lead_price: number | null;
  monthly_spend: number;
  transactions: Omit<Transaction, "formatted_date">[];
  total_transactions: number;
  page: number;
  per_page: number;
};

type LoaderData = {
  billing: Omit<BillingResponse, "transactions"> & { transactions: Transaction[] };
  userId: string;
  lsCheckoutUrl: string | null;
  lsCustomerPortalUrl: string | null;
};

type ActionData =
  | { success: true; intent: "update_max_lead_price" | "update_spending_limit" }
  | {
      success: false;
      intent: "update_max_lead_price" | "update_spending_limit" | "unknown";
      error: string;
    };

// ── Helpers ───────────────────────────────────────────────────────────────────

export function formatTransactionDate(isoString: string | null): string {
  if (!isoString) return "—";
  const date = new Date(isoString);
  if (isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "UTC",
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(date);
}

export function centsToEur(cents: number): string {
  return (cents / 100).toFixed(2);
}

export function buildBillingPageUrl(page: number): string {
  const params = new URLSearchParams({ page: String(page) });
  return `/dashboard/billing?${params.toString()}`;
}

// ── Loader ────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const url = new URL(request.url);
  const page = url.searchParams.get("page") ?? "1";

  const billing = await apiGet<BillingResponse>(
    env,
    session.token,
    `/api/experts/${userId}/billing`,
    { page, per_page: "20" },
  ).catch(
    () =>
      ({
        credit_balance: 0,
        ls_subscription_status: null,
        ls_subscription_id: null,
        spending_limit: null,
        max_lead_price: null,
        monthly_spend: 0,
        transactions: [],
        total_transactions: 0,
        page: 1,
        per_page: 20,
      }) satisfies BillingResponse,
  );

  const transactions: Transaction[] = billing.transactions.map((t) => ({
    ...t,
    formatted_date: formatTransactionDate(t.created_at),
  }));

  captureEvent(env, `expert:${userId}`, "expert.billing_viewed", {
    has_subscription: billing.ls_subscription_id !== null,
    subscription_status: billing.ls_subscription_status,
  }).catch(() => {});

  return Response.json(
    {
      billing: { ...billing, transactions },
      userId,
      lsCheckoutUrl: env.LS_CHECKOUT_URL ?? null,
      lsCustomerPortalUrl: env.LS_CUSTOMER_PORTAL_URL ?? null,
    } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

// ── Action ────────────────────────────────────────────────────────────────────

export async function action({ request, context }: ActionFunctionArgs) {
  const { session } = await requireSession(request, context.cloudflare.env);
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const formData = await request.formData();
  const intent = String(formData.get("intent") ?? "");

  if (intent === "update_max_lead_price") {
    const rawEur = String(formData.get("max_lead_price_eur") ?? "").trim();
    const oldCents = Number(formData.get("old_max_lead_price") ?? "0");
    const eurValue = parseFloat(rawEur);

    if (isNaN(eurValue) || eurValue < 0) {
      return Response.json(
        {
          success: false,
          intent: "update_max_lead_price",
          error: "Montant invalide.",
        } satisfies ActionData,
        { status: 422 },
      );
    }

    const centimes = Math.round(eurValue * 100);

    try {
      await apiPatch<{ success: true }>(
        env,
        session.token,
        `/api/experts/${userId}/profile`,
        { max_lead_price: centimes },
      );
      captureEvent(env, `expert:${userId}`, "expert.spending_control_updated", {
        control_name: "max_lead_price",
        old_value: oldCents,
        new_value: centimes,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "update_max_lead_price" } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "update_max_lead_price",
          error: "Impossible de mettre à jour.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  if (intent === "update_spending_limit") {
    const rawEur = String(formData.get("spending_limit_eur") ?? "").trim();
    const oldCents = Number(formData.get("old_spending_limit") ?? "0");
    const eurValue = parseFloat(rawEur);

    if (isNaN(eurValue) || eurValue < 0) {
      return Response.json(
        {
          success: false,
          intent: "update_spending_limit",
          error: "Montant invalide.",
        } satisfies ActionData,
        { status: 422 },
      );
    }

    const centimes = Math.round(eurValue * 100);

    try {
      await apiPatch<{ success: true }>(
        env,
        session.token,
        `/api/experts/${userId}/profile`,
        { spending_limit: centimes },
      );
      captureEvent(env, `expert:${userId}`, "expert.spending_control_updated", {
        control_name: "spending_limit",
        old_value: oldCents,
        new_value: centimes,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "update_spending_limit" } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "update_spending_limit",
          error: "Impossible de mettre à jour.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  return Response.json(
    { success: false, intent: "unknown", error: "Action inconnue." } satisfies ActionData,
    { status: 400 },
  );
}

// ── Component ─────────────────────────────────────────────────────────────────

export default function BillingPage() {
  const { billing, lsCheckoutUrl, lsCustomerPortalUrl } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const [searchParams] = useSearchParams();

  const currentPage = Number(searchParams.get("page") ?? "1");
  const totalPages = Math.ceil(billing.total_transactions / billing.per_page);
  const start = (currentPage - 1) * billing.per_page + 1;
  const end = Math.min(currentPage * billing.per_page, billing.total_transactions);

  const [maxLeadPriceInput, setMaxLeadPriceInput] = useState(
    billing.max_lead_price !== null ? String(billing.max_lead_price / 100) : "",
  );
  const [spendingLimitInput, setSpendingLimitInput] = useState(
    billing.spending_limit !== null ? String(billing.spending_limit / 100) : "",
  );

  // Lemon.js script injection (client-side only)
  useEffect(() => {
    if (typeof document === "undefined") return;
    if (document.getElementById("lemon-js")) {
      // Script already loaded — just wire up the event handler
      window.createLemonSqueezy?.();
      window.LemonSqueezy?.Setup({
        eventHandler: (event: { event: string }) => {
          if (event.event === "Checkout.Success") {
            window.location.reload();
          }
        },
      });
      return;
    }
    const script = document.createElement("script");
    script.id = "lemon-js";
    script.src = "https://app.lemonsqueezy.com/js/lemon.js";
    script.defer = true;
    script.onload = () => {
      window.createLemonSqueezy?.();
      window.LemonSqueezy?.Setup({
        eventHandler: (event: { event: string }) => {
          if (event.event === "Checkout.Success") {
            // Force loader revalidation to show updated credit balance and subscription status.
            // Note: if a CSP header is added in the future, ensure app.lemonsqueezy.com is in script-src.
            window.location.reload();
          }
        },
      });
    };
    document.head.appendChild(script);
  }, []);

  useEffect(() => {
    if (!actionData) return;
    if (actionData.success) {
      toast.success("Paramètre mis à jour");
    } else {
      toast.error(actionData.error);
    }
  }, [actionData]);

  // Monthly spend progress
  const spendPct =
    billing.spending_limit !== null && billing.spending_limit > 0
      ? Math.min(100, (billing.monthly_spend / billing.spending_limit) * 100)
      : 0;
  const spendWarning = spendPct >= 100;
  const spendCaution = spendPct > 80 && spendPct < 100;

  // Subscription display helpers
  const hasSubscription = billing.ls_subscription_id !== null;
  const subStatus = billing.ls_subscription_status;

  function subscriptionBadge() {
    if (!hasSubscription || !subStatus) return null;
    switch (subStatus) {
      case "active":
        return (
          <Badge className="bg-green-100 text-green-800 border border-green-200">
            Abonnement actif
          </Badge>
        );
      case "past_due":
        return (
          <Badge className="bg-orange-100 text-orange-800 border border-orange-200">
            Paiement en attente
          </Badge>
        );
      case "cancelled":
        return (
          <Badge className="bg-red-100 text-red-800 border border-red-200">
            Abonnement annulé
          </Badge>
        );
      default:
        return (
          <Badge className="bg-gray-100 text-gray-800 border border-gray-200">
            {subStatus}
          </Badge>
        );
    }
  }

  function handleActivate() {
    if (!lsCheckoutUrl) return;
    // The ?embed=1 parameter enables the overlay mode in Lemon Squeezy.
    const overlayUrl = lsCheckoutUrl.includes("?")
      ? `${lsCheckoutUrl}&embed=1`
      : `${lsCheckoutUrl}?embed=1`;
    window.LemonSqueezy?.openUrl(overlayUrl);
  }

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div>
        <h1 className="text-2xl font-semibold">Facturation</h1>
        <p className="text-muted-foreground mt-1">
          Gérez votre abonnement, consultez votre solde de crédits et contrôlez vos dépenses.
        </p>
      </div>

      {/* AC2 / AC3: Subscription status */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Abonnement</CardTitle>
        </CardHeader>
        <CardContent>
          {!hasSubscription ? (
            /* AC2: No subscription — activation CTA */
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Activez votre abonnement pour recevoir des leads. Aucun frais fixe — vous ne payez
                que les leads que vous acceptez. 100€ de crédits offerts à l&apos;activation.
              </p>
              <Button
                type="button"
                onClick={handleActivate}
                disabled={!lsCheckoutUrl}
              >
                {lsCheckoutUrl ? "Activer" : "Configuration en cours..."}
              </Button>
            </div>
          ) : (
            /* AC3: Has subscription — status badge + management */
            <div className="space-y-3">
              <div className="flex items-center gap-3">
                {subscriptionBadge()}
              </div>

              {subStatus === "past_due" && (
                <p className="text-sm text-orange-600">
                  Un problème de paiement a été détecté. Veuillez mettre à jour vos informations de
                  paiement pour continuer à recevoir des leads.
                </p>
              )}

              {subStatus === "cancelled" && (
                <div className="space-y-2">
                  <p className="text-sm text-red-600">
                    Votre abonnement a été annulé. Réactivez-le pour recevoir de nouveaux leads.
                  </p>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleActivate}
                    disabled={!lsCheckoutUrl}
                  >
                    Réactiver l&apos;abonnement
                  </Button>
                </div>
              )}

              {/* AC3: Subscription management link — LS customer portal */}
              {lsCustomerPortalUrl && (
                <p className="text-sm text-muted-foreground">
                  <a
                    href={lsCustomerPortalUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary underline underline-offset-2"
                  >
                    Gérer votre abonnement via le portail Lemon Squeezy
                  </a>
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* AC4: Credit balance */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Solde de crédits</CardTitle>
        </CardHeader>
        <CardContent>
          <p
            className={[
              "text-4xl font-bold tabular-nums",
              billing.credit_balance > 0 ? "text-green-600" : "text-red-600",
            ].join(" ")}
          >
            {centsToEur(billing.credit_balance)}€
          </p>
          <p className="text-sm text-muted-foreground mt-1">
            Solde disponible pour recevoir des leads
          </p>
        </CardContent>
      </Card>

      {/* AC5: Monthly spending progress */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Dépenses du mois</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {billing.spending_limit !== null ? (
            <>
              <div className="flex items-center justify-between text-sm">
                <span>
                  <span className="font-medium">{centsToEur(billing.monthly_spend)}€</span>
                  {" "}dépensés ce mois
                </span>
                <span className="text-muted-foreground">
                  limite {centsToEur(billing.spending_limit)}€
                </span>
              </div>
              <Progress
                value={spendPct}
                className={
                  spendWarning
                    ? "[&>div]:bg-red-500"
                    : spendCaution
                      ? "[&>div]:bg-orange-500"
                      : undefined
                }
              />
              {spendWarning && (
                <p className="text-sm text-red-600 font-medium">
                  Limite mensuelle atteinte. Les nouveaux leads sont pausés.
                </p>
              )}
              {spendCaution && (
                <p className="text-sm text-orange-600">
                  Vous approchez de votre limite mensuelle.
                </p>
              )}
            </>
          ) : (
            <p className="text-sm">
              <span className="font-medium text-foreground">
                {centsToEur(billing.monthly_spend)}€
              </span>{" "}
              dépensés ce mois
            </p>
          )}
        </CardContent>
      </Card>

      {/* AC7 + AC8: Spending controls */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Contrôles de dépenses</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* AC7: Max lead price */}
          <Form method="post" className="space-y-3">
            <input type="hidden" name="intent" value="update_max_lead_price" />
            <input
              type="hidden"
              name="old_max_lead_price"
              value={String(billing.max_lead_price ?? 0)}
            />
            <div className="space-y-1">
              <Label htmlFor="max_lead_price_eur">Prix maximum par lead</Label>
              <div className="flex gap-2 items-center">
                <div className="relative">
                  <Input
                    id="max_lead_price_eur"
                    name="max_lead_price_eur"
                    type="number"
                    min="0"
                    step="0.01"
                    value={maxLeadPriceInput}
                    onChange={(e) => setMaxLeadPriceInput(e.target.value)}
                    className="pr-8 w-36"
                    placeholder="0.00"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-sm pointer-events-none">
                    €
                  </span>
                </div>
                <Button type="submit" size="sm">
                  Enregistrer
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Les leads dont le prix dépasse ce montant ne vous seront pas envoyés.
              </p>
            </div>
          </Form>

          <Separator />

          {/* AC8: Spending limit */}
          <Form method="post" className="space-y-3">
            <input type="hidden" name="intent" value="update_spending_limit" />
            <input
              type="hidden"
              name="old_spending_limit"
              value={String(billing.spending_limit ?? 0)}
            />
            <div className="space-y-1">
              <Label htmlFor="spending_limit_eur">Limite mensuelle</Label>
              <div className="flex gap-2 items-center">
                <div className="relative">
                  <Input
                    id="spending_limit_eur"
                    name="spending_limit_eur"
                    type="number"
                    min="0"
                    step="0.01"
                    value={spendingLimitInput}
                    onChange={(e) => setSpendingLimitInput(e.target.value)}
                    className="pr-8 w-36"
                    placeholder="0.00"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-sm pointer-events-none">
                    €
                  </span>
                </div>
                <Button type="submit" size="sm">
                  Enregistrer
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Les leads seront pausés une fois cette limite atteinte. Réinitialisé chaque mois.
              </p>
            </div>
          </Form>
        </CardContent>
      </Card>

      {/* AC6: Transaction history */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Historique des transactions</CardTitle>
        </CardHeader>
        <CardContent>
          {billing.transactions.length === 0 ? (
            <p className="text-sm text-muted-foreground py-4 text-center">
              Aucune transaction pour le moment.
            </p>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead className="text-right">Montant</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {billing.transactions.map((txn) => (
                    <TableRow key={txn.id}>
                      <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                        {txn.formatted_date}
                      </TableCell>
                      <TableCell className="text-sm">
                        {txn.type === "credit" ? "Crédit" : "Débit"}
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {txn.description ?? "—"}
                      </TableCell>
                      <TableCell className="text-right text-sm font-medium whitespace-nowrap">
                        {txn.type === "credit" ? (
                          <span className="text-green-600">
                            + {centsToEur(txn.amount_cents)}€
                          </span>
                        ) : (
                          <span className="text-red-600">
                            − {centsToEur(txn.amount_cents)}€
                          </span>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              {/* Pagination */}
              {billing.total_transactions > billing.per_page && (
                <div className="flex items-center justify-between mt-4">
                  <p className="text-sm text-muted-foreground">
                    Affichage de {start}–{end} sur {billing.total_transactions} transactions
                  </p>
                  <div className="flex gap-2">
                    {currentPage > 1 && (
                      <Link to={buildBillingPageUrl(currentPage - 1)}>
                        <Button variant="outline" size="sm">
                          Précédent
                        </Button>
                      </Link>
                    )}
                    {currentPage < totalPages && (
                      <Link to={buildBillingPageUrl(currentPage + 1)}>
                        <Button variant="outline" size="sm">
                          Suivant
                        </Button>
                      </Link>
                    )}
                  </div>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

      {/* AC10: Leads manqués — DEFERRED.
          Requires billing_excluded_leads array in GET /api/experts/:id/billing response (E06S38 gap).
          Implement as a post-MVP enhancement once the backend provides exclusion data. */}
    </div>
  );
}
