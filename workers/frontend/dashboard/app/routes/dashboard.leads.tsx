import { Form, Link, useActionData, useLoaderData, useSearchParams } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState, useEffect } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPost, ApiError } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import { Badge } from "~/components/ui/badge";
import { Card, CardContent } from "~/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "~/components/ui/dialog";
import { Label } from "~/components/ui/label";
import { Textarea } from "~/components/ui/textarea";
import { Separator } from "~/components/ui/separator";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "~/components/ui/table";

// ── Types ─────────────────────────────────────────────────────────────────────

type ProspectRequirements = {
  budget?: string | number | null;
  timeline?: string | null;
  skills_needed?: string[] | null;
  description?: string | null;
};

type Lead = {
  id: string;
  status: string | null;
  price_cents: number | null;
  created_at: string | null;
  confirmed_at: string | null;
  flagged_at: string | null;
  flag_reason: string | null;
  flag_window_expires_at: string | null;
  evaluation_score: number | null;
  evaluation_notes: string | null;
  conversion_declared: boolean;
  evaluated_at: string | null;
  prospect: { id: string; email: string | null; requirements: unknown } | null;
  match_score: number | null;
  booking: { id: string; starts_at: string | null; status: string | null } | null;
};

type LeadsResponse = {
  leads: Lead[];
  total: number;
  page: number;
  per_page: number;
};

type LoaderData = {
  leads: Lead[];
  total: number;
  page: number;
  per_page: number;
  userId: string;
};

type ActionData =
  | { success: true; intent: "confirm"; leadId: string }
  | { success: true; intent: "flag"; leadId: string }
  | { success: true; intent: "evaluate"; leadId: string }
  | { success: false; intent: "confirm" | "flag" | "evaluate"; error: string }
  | { success: false; intent: "unknown"; error: string };

// ── Loader ────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const url = new URL(request.url);
  const status = url.searchParams.get("status") ?? "all";
  const page = url.searchParams.get("page") ?? "1";

  const data = await apiGet<LeadsResponse>(
    env,
    session.token,
    `/api/experts/${userId}/leads`,
    { status, page, per_page: "20" },
  ).catch(() => ({ leads: [], total: 0, page: 1, per_page: 20 }));

  captureEvent(env, `expert:${userId}`, "expert.leads_viewed", {
    status_filter: status,
  }).catch(() => {});

  return Response.json(
    {
      leads: data.leads,
      total: data.total,
      page: data.page,
      per_page: data.per_page,
      userId,
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

  if (intent === "confirm") {
    const leadId = String(formData.get("leadId") ?? "");
    if (!leadId) {
      return Response.json(
        { success: false, intent: "confirm", error: "Lead ID manquant." } satisfies ActionData,
        { status: 400 },
      );
    }
    try {
      await apiPost<{ success: true }>(env, session.token, `/api/leads/${leadId}/confirm`, {});
      const priceCents = Number(formData.get("price_cents")) || 0;
      captureEvent(env, `expert:${userId}`, "expert.lead_confirmed", {
        lead_id: leadId,
        price_cents: priceCents,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "confirm", leadId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        { success: false, intent: "confirm", error: "Impossible de confirmer ce lead." } satisfies ActionData,
        { status },
      );
    }
  }

  if (intent === "flag") {
    const leadId = String(formData.get("leadId") ?? "");
    const reason = String(formData.get("flag_reason") ?? "").trim();
    if (!leadId) {
      return Response.json(
        { success: false, intent: "flag", error: "Lead ID manquant." } satisfies ActionData,
        { status: 400 },
      );
    }
    if (reason.length < 20) {
      return Response.json(
        {
          success: false,
          intent: "flag",
          error: "La raison doit contenir au moins 20 caractères.",
        } satisfies ActionData,
        { status: 422 },
      );
    }
    try {
      await apiPost<{ success: true }>(env, session.token, `/api/leads/${leadId}/flag`, {
        reason,
      });
      captureEvent(env, `expert:${userId}`, "expert.lead_flagged", {
        lead_id: leadId,
        reason_length: reason.length,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "flag", leadId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        { success: false, intent: "flag", error: "Impossible de signaler ce lead." } satisfies ActionData,
        { status },
      );
    }
  }

  if (intent === "evaluate") {
    const leadId = String(formData.get("leadId") ?? "");
    const scoreRaw = Number(formData.get("score"));
    const notes = String(formData.get("notes") ?? "").trim();
    const conversionDeclared = formData.get("conversion_declared") === "true";

    if (!leadId) {
      return Response.json(
        { success: false, intent: "evaluate", error: "Lead ID manquant." } satisfies ActionData,
        { status: 400 },
      );
    }
    if (isNaN(scoreRaw) || scoreRaw < 1 || scoreRaw > 10) {
      return Response.json(
        { success: false, intent: "evaluate", error: "Score invalide (1–10 requis)." } satisfies ActionData,
        { status: 422 },
      );
    }
    if (notes.length > 500) {
      return Response.json(
        { success: false, intent: "evaluate", error: "Notes limitées à 500 caractères." } satisfies ActionData,
        { status: 422 },
      );
    }
    try {
      await apiPost(env, session.token, `/api/leads/${leadId}/evaluate`, {
        score: scoreRaw,
        notes: notes || undefined,
        conversion_declared: conversionDeclared,
      });
      captureEvent(env, `expert:${userId}`, "expert.lead_evaluated", {
        lead_id: leadId,
        score: scoreRaw,
        conversion_declared: conversionDeclared,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "evaluate", leadId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        { success: false, intent: "evaluate", error: "Impossible d'enregistrer l'évaluation." } satisfies ActionData,
        { status },
      );
    }
  }

  return Response.json(
    { success: false, intent: "unknown", error: "Action inconnue." } satisfies ActionData,
    { status: 400 },
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function formatPrice(cents: number | null): string {
  if (cents === null) return "—";
  return new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(
    cents / 100,
  );
}

function relativeDate(isoString: string | null): string {
  if (!isoString) return "—";
  const diff = Date.now() - new Date(isoString).getTime();
  const hours = Math.floor(diff / 3_600_000);
  if (hours < 1) return "il y a < 1h";
  if (hours < 24) return `il y a ${hours}h`;
  const days = Math.floor(hours / 24);
  return `il y a ${days}j`;
}

function flagWindowInfo(lead: Lead): { daysLeft: number; urgent: boolean } | null {
  if (!lead.flag_window_expires_at || lead.status !== "new") return null;
  const msLeft = new Date(lead.flag_window_expires_at).getTime() - Date.now();
  if (msLeft <= 0) return null;
  const hoursLeft = msLeft / 3_600_000;
  const daysLeft = Math.ceil(hoursLeft / 24);
  return { daysLeft, urgent: hoursLeft < 24 };
}

function statusBadgeClass(status: string | null): string {
  switch (status) {
    case "new":
      return "bg-blue-100 text-blue-800 border border-blue-200";
    case "confirmed":
      return "bg-green-100 text-green-800 border border-green-200";
    case "flagged":
      return "bg-red-100 text-red-800 border border-red-200";
    default:
      return "bg-gray-100 text-gray-800 border border-gray-200";
  }
}

function statusLabel(status: string | null): string {
  switch (status) {
    case "new":
      return "Nouveau";
    case "confirmed":
      return "Confirmé";
    case "flagged":
      return "Signalé";
    default:
      return status ?? "—";
  }
}

function buildTabUrl(status: string, currentParams: URLSearchParams): string {
  const params = new URLSearchParams(currentParams);
  params.set("status", status);
  params.delete("page");
  return `/dashboard/leads?${params.toString()}`;
}

function buildPageUrl(page: number, status: string): string {
  const params = new URLSearchParams();
  params.set("status", status);
  params.set("page", String(page));
  return `/dashboard/leads?${params.toString()}`;
}

const STATUS_TABS = [
  { value: "all", label: "Tous" },
  { value: "new", label: "Nouveaux" },
  { value: "confirmed", label: "Confirmés" },
  { value: "flagged", label: "Signalés" },
] as const;

// ── Component ─────────────────────────────────────────────────────────────────

export default function LeadsPage() {
  const { leads, total, page, per_page } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const [searchParams] = useSearchParams();

  const [selectedLead, setSelectedLead] = useState<Lead | null>(null);
  const [flagDialogOpen, setFlagDialogOpen] = useState(false);
  const [flagReason, setFlagReason] = useState("");
  const [evalScore, setEvalScore] = useState(5);
  const [evalNotes, setEvalNotes] = useState("");
  const [evalConversion, setEvalConversion] = useState(false);

  const statusFilter = searchParams.get("status") ?? "all";
  const currentPage = Number(searchParams.get("page") ?? "1");
  const start = (currentPage - 1) * per_page + 1;
  const end = Math.min(currentPage * per_page, total);
  const totalPages = Math.ceil(total / per_page);

  useEffect(() => {
    if (!actionData) return;
    if (actionData.success) {
      if (actionData.intent === "confirm") {
        toast.success("Lead confirmé");
      }
      if (actionData.intent === "flag") {
        toast.success("Lead signalé — crédit restauré");
        setFlagDialogOpen(false);
        setFlagReason("");
        setSelectedLead(null);
      }
      if (actionData.intent === "evaluate") {
        toast.success("Évaluation enregistrée — merci, vos futurs matchs s'amélioreront.");
        setSelectedLead(null);
        setEvalScore(5);
        setEvalNotes("");
        setEvalConversion(false);
      }
    } else if (actionData.intent !== "unknown") {
      toast.error(actionData.error);
    }
  }, [actionData]);

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div>
        <h1 className="text-2xl font-semibold">Mes Leads</h1>
        <p className="text-muted-foreground mt-1">
          Gérez vos leads entrants, confirmez ou signalez dans les 7 jours.
        </p>
      </div>

      {/* AC2: Status filter tabs */}
      <div className="flex gap-1 border-b border-border">
        {STATUS_TABS.map((tab) => {
          const isActive = statusFilter === tab.value;
          return (
            <Link
              key={tab.value}
              to={buildTabUrl(tab.value, searchParams)}
              className={[
                "px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px",
                isActive
                  ? "border-primary text-foreground"
                  : "border-transparent text-muted-foreground hover:text-foreground",
              ].join(" ")}
            >
              {tab.label}
              {isActive && total > 0 && (
                <span className="ml-2 rounded-full bg-primary/10 px-2 py-0.5 text-xs text-primary">
                  {total}
                </span>
              )}
            </Link>
          );
        })}
      </div>

      {/* AC10: Empty state */}
      {leads.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 rounded-full bg-muted p-4">
              <svg
                className="h-8 w-8 text-muted-foreground"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={1.5}
                  d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
            </div>
            <h2 className="text-lg font-semibold">Vous n'avez pas encore de leads</h2>
            <p className="mt-2 max-w-sm text-sm text-muted-foreground">
              Dès qu'un prospect correspondant à votre profil sera identifié, il apparaîtra
              ici. Assurez-vous que votre profil est complet pour maximiser vos matches.
            </p>
            <Link to="/dashboard/settings" className="mt-4">
              <Button variant="outline">Compléter mon profil</Button>
            </Link>
          </CardContent>
        </Card>
      ) : (
        <>
          {/* AC3: Lead table */}
          <Card>
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Prospect</TableHead>
                    <TableHead>Score</TableHead>
                    <TableHead>Prix</TableHead>
                    <TableHead>Statut</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {leads.map((lead) => {
                    const windowInfo = flagWindowInfo(lead);
                    return (
                      <TableRow
                        key={lead.id}
                        className="cursor-pointer"
                        onClick={() => setSelectedLead(lead)}
                      >
                        <TableCell className="font-medium">
                          {lead.prospect?.email ?? "Prospect anonyme"}
                        </TableCell>
                        <TableCell>
                          <Badge variant="secondary">
                            {lead.match_score !== null ? `${lead.match_score}%` : "—"}
                          </Badge>
                        </TableCell>
                        <TableCell>{formatPrice(lead.price_cents)}</TableCell>
                        <TableCell>
                          <div className="flex flex-col gap-1">
                            <Badge className={statusBadgeClass(lead.status)}>
                              {statusLabel(lead.status)}
                            </Badge>
                            {/* AC8: Flag window badge */}
                            {lead.status === "new" && windowInfo && (
                              <span
                                className={[
                                  "text-xs rounded px-1.5 py-0.5 inline-block w-fit",
                                  windowInfo.urgent
                                    ? "bg-red-100 text-red-700"
                                    : "bg-amber-50 text-amber-700",
                                ].join(" ")}
                              >
                                {windowInfo.urgent
                                  ? "Dernier jour"
                                  : `${windowInfo.daysLeft}j restants`}
                              </span>
                            )}
                          </div>
                        </TableCell>
                        <TableCell className="text-muted-foreground text-sm">
                          {relativeDate(lead.created_at)}
                        </TableCell>
                        <TableCell onClick={(e) => e.stopPropagation()}>
                          <div className="flex items-center gap-2">
                            {/* AC6: Confirm action */}
                            {lead.status === "new" && (
                              <Form method="post">
                                <input type="hidden" name="intent" value="confirm" />
                                <input type="hidden" name="leadId" value={lead.id} />
                                <input
                                  type="hidden"
                                  name="price_cents"
                                  value={lead.price_cents ?? ""}
                                />
                                <Button size="sm" type="submit">
                                  Confirmer
                                </Button>
                              </Form>
                            )}
                            {/* AC7: Flag action — only within flag window */}
                            {lead.status === "new" && windowInfo !== null && (
                              <Button
                                size="sm"
                                variant="outline"
                                type="button"
                                onClick={() => {
                                  setSelectedLead(lead);
                                  setFlagDialogOpen(true);
                                }}
                              >
                                Signaler
                              </Button>
                            )}
                          </div>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          {/* AC4: Pagination */}
          {total > per_page && (
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">
                Affichage de {start}–{end} sur {total} leads
              </p>
              <div className="flex gap-2">
                {currentPage > 1 && (
                  <Link to={buildPageUrl(currentPage - 1, statusFilter)}>
                    <Button variant="outline" size="sm">
                      Précédent
                    </Button>
                  </Link>
                )}
                {currentPage < totalPages && (
                  <Link to={buildPageUrl(currentPage + 1, statusFilter)}>
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

      {/* AC5: Lead detail Dialog */}
      <Dialog
        open={!!selectedLead && !flagDialogOpen}
        onOpenChange={(open) => {
          if (!open) setSelectedLead(null);
        }}
      >
        <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Détail du lead</DialogTitle>
            <DialogDescription>
              Informations complètes sur ce lead et son contexte.
            </DialogDescription>
          </DialogHeader>
          {selectedLead && (
            <div className="space-y-4 pt-2">
              {/* Match score + price */}
              <div className="flex items-center gap-4">
                <div>
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">
                    Score de match
                  </p>
                  <p className="text-2xl font-bold">
                    {selectedLead.match_score !== null
                      ? `${selectedLead.match_score}%`
                      : "—"}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">Prix</p>
                  <p className="text-2xl font-bold">
                    {formatPrice(selectedLead.price_cents)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">
                    Statut
                  </p>
                  <Badge className={statusBadgeClass(selectedLead.status)}>
                    {statusLabel(selectedLead.status)}
                  </Badge>
                </div>
              </div>

              {/* Flag window countdown */}
              {selectedLead.status === "new" && (() => {
                const info = flagWindowInfo(selectedLead);
                return info ? (
                  <div
                    className={[
                      "rounded-md px-3 py-2 text-sm",
                      info.urgent ? "bg-red-50 text-red-700" : "bg-amber-50 text-amber-700",
                    ].join(" ")}
                  >
                    {info.urgent
                      ? "⚠️ Dernier jour pour signaler ce lead"
                      : `⏱ ${info.daysLeft} jour${info.daysLeft > 1 ? "s" : ""} restants pour signaler ce lead`}
                  </div>
                ) : null;
              })()}

              <Separator />

              {/* Prospect requirements */}
              {selectedLead.prospect && (
                <div className="space-y-2">
                  <h3 className="font-medium">Besoins du prospect</h3>
                  {(() => {
                    const req = (selectedLead.prospect.requirements ??
                      {}) as ProspectRequirements;
                    return (
                      <dl className="grid grid-cols-2 gap-2 text-sm">
                        {req.budget && (
                          <>
                            <dt className="text-muted-foreground">Budget</dt>
                            <dd>{req.budget}</dd>
                          </>
                        )}
                        {req.timeline && (
                          <>
                            <dt className="text-muted-foreground">Délai</dt>
                            <dd>{req.timeline}</dd>
                          </>
                        )}
                        {req.skills_needed && req.skills_needed.length > 0 && (
                          <>
                            <dt className="text-muted-foreground">Compétences</dt>
                            <dd className="flex flex-wrap gap-1">
                              {req.skills_needed.map((s) => (
                                <Badge key={s} variant="outline" className="text-xs">
                                  {s}
                                </Badge>
                              ))}
                            </dd>
                          </>
                        )}
                        {req.description && (
                          <>
                            <dt className="text-muted-foreground">Description</dt>
                            <dd className="col-span-1">{req.description}</dd>
                          </>
                        )}
                      </dl>
                    );
                  })()}
                </div>
              )}

              {/* Booking info */}
              {selectedLead.booking && (
                <>
                  <Separator />
                  <div className="space-y-2">
                    <h3 className="font-medium">Réservation</h3>
                    <dl className="grid grid-cols-2 gap-2 text-sm">
                      <dt className="text-muted-foreground">Date</dt>
                      <dd>
                        {selectedLead.booking.starts_at
                          ? new Date(selectedLead.booking.starts_at).toLocaleString(
                              "fr-FR",
                              {
                                weekday: "long",
                                day: "numeric",
                                month: "long",
                                hour: "2-digit",
                                minute: "2-digit",
                              },
                            )
                          : "—"}
                      </dd>
                      <dt className="text-muted-foreground">Statut</dt>
                      <dd>{selectedLead.booking.status ?? "—"}</dd>
                    </dl>
                  </div>
                </>
              )}

              {/* AC9: Evaluate form — confirmed + not yet evaluated */}
              {selectedLead.status === "confirmed" &&
                selectedLead.evaluation_score === null && (
                  <>
                    <Separator />
                    <div className="space-y-4">
                      <div>
                        <h3 className="font-medium">Évaluer ce lead</h3>
                        <p className="text-sm text-muted-foreground">
                          Vos évaluations améliorent la qualité de vos futurs leads.
                        </p>
                      </div>
                      <Form method="post" className="space-y-4">
                        <input type="hidden" name="intent" value="evaluate" />
                        <input type="hidden" name="leadId" value={selectedLead.id} />
                        <div className="space-y-2">
                          <Label>Score (1–10)</Label>
                          <input
                            type="range"
                            name="score"
                            min={1}
                            max={10}
                            step={1}
                            value={evalScore}
                            onChange={(e) => setEvalScore(Number(e.target.value))}
                            className="w-full accent-primary"
                          />
                          <div className="flex justify-between text-xs text-muted-foreground">
                            <span>1 — Très mauvais</span>
                            <span className="font-semibold text-foreground">{evalScore}</span>
                            <span>10 — Excellent</span>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="eval_notes">Notes (optionnel)</Label>
                          <Textarea
                            id="eval_notes"
                            name="notes"
                            value={evalNotes}
                            onChange={(e) => setEvalNotes(e.target.value)}
                            maxLength={500}
                            placeholder="Vos retours sur ce lead..."
                            rows={3}
                          />
                          <p className="text-xs text-muted-foreground">
                            {evalNotes.length}/500
                          </p>
                        </div>
                        <div className="flex items-center gap-2">
                          <input
                            type="checkbox"
                            id="conversion"
                            name="conversion_declared"
                            value="true"
                            checked={evalConversion}
                            onChange={(e) => setEvalConversion(e.target.checked)}
                            className="h-4 w-4 rounded border-border"
                          />
                          <Label htmlFor="conversion" className="cursor-pointer">
                            Ce lead a mené à un projet
                          </Label>
                        </div>
                        <Button type="submit">Enregistrer l'évaluation</Button>
                      </Form>
                    </div>
                  </>
                )}

              {/* Existing evaluation display */}
              {selectedLead.evaluation_score !== null && (
                <>
                  <Separator />
                  <div className="space-y-1">
                    <h3 className="font-medium">Évaluation soumise</h3>
                    <p className="text-sm text-muted-foreground">
                      Score :{" "}
                      <span className="font-medium text-foreground">
                        {selectedLead.evaluation_score}/10
                      </span>
                    </p>
                    {selectedLead.evaluation_notes && (
                      <p className="text-sm text-muted-foreground">
                        {selectedLead.evaluation_notes}
                      </p>
                    )}
                    {selectedLead.conversion_declared && (
                      <p className="text-sm text-green-700">✓ Conversion déclarée</p>
                    )}
                  </div>
                </>
              )}

              {/* AC11: Realtime subscription deferred — CF Worker context complexity */}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* AC7: Flag Dialog */}
      <Dialog
        open={flagDialogOpen}
        onOpenChange={(open) => {
          if (!open) {
            setFlagDialogOpen(false);
            setFlagReason("");
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Signaler ce lead</DialogTitle>
            <DialogDescription>
              Indiquez pourquoi ce lead ne correspond pas à vos critères. Votre crédit sera
              restauré après validation du signalement (min. 20 caractères).
            </DialogDescription>
          </DialogHeader>
          <Form method="post" className="space-y-4">
            <input type="hidden" name="intent" value="flag" />
            <input type="hidden" name="leadId" value={selectedLead?.id ?? ""} />
            <div className="space-y-2">
              <Label htmlFor="flag_reason">Raison du signalement</Label>
              <Textarea
                id="flag_reason"
                name="flag_reason"
                value={flagReason}
                onChange={(e) => setFlagReason(e.target.value)}
                placeholder="Décrivez pourquoi ce lead ne vous correspond pas..."
                rows={4}
              />
              <p
                className={[
                  "text-xs",
                  flagReason.length < 20
                    ? "text-muted-foreground"
                    : "text-green-600",
                ].join(" ")}
              >
                {flagReason.length} / 20 caractères minimum
              </p>
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                type="button"
                onClick={() => {
                  setFlagDialogOpen(false);
                  setFlagReason("");
                }}
              >
                Annuler
              </Button>
              <Button
                variant="destructive"
                type="submit"
                disabled={flagReason.length < 20}
              >
                Confirmer le signalement
              </Button>
            </DialogFooter>
          </Form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
