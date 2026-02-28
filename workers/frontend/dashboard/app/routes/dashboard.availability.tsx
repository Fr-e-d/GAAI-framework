// E02S11: Expert Availability — Weekly Recurring Rules dashboard page
import { Form, useFetcher, useActionData, useLoaderData } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState, useEffect } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPost, apiPut, apiPatch, apiDelete, ApiError } from "~/lib/api.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "~/components/ui/dialog";

// ── Constants ────────────────────────────────────────────────────────────────

const ROW_HEIGHT_PX = 36; // Height of each 30-minute slot row in the grid
const GRID_START_HOUR = 6; // 06:00
const GRID_END_HOUR = 22;  // 22:00 (exclusive)
const ROWS = (GRID_END_HOUR - GRID_START_HOUR) * 2; // 32 rows (06:00–21:30)

// European Mon-first column order. day_of_week: 0=Sun,1=Mon,...,6=Sat
const DAY_DISPLAY = [
  { label: "Lun", dayOfWeek: 1 },
  { label: "Mar", dayOfWeek: 2 },
  { label: "Mer", dayOfWeek: 3 },
  { label: "Jeu", dayOfWeek: 4 },
  { label: "Ven", dayOfWeek: 5 },
  { label: "Sam", dayOfWeek: 6 },
  { label: "Dim", dayOfWeek: 0 },
] as const;

const COMMON_TIMEZONES = [
  "UTC",
  "Europe/Brussels",
  "Europe/Paris",
  "Europe/London",
  "Europe/Berlin",
  "Europe/Amsterdam",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "Asia/Tokyo",
  "Asia/Singapore",
  "Australia/Sydney",
] as const;

// ── Types ────────────────────────────────────────────────────────────────────

type AvailabilityRule = {
  id: string;
  expert_id: string;
  day_of_week: number;
  start_time: string; // HH:MM
  end_time: string;   // HH:MM
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

type RulesResponse = {
  rules: AvailabilityRule[];
  timezone: string;
};

type AvailabilitySlot = {
  start_at: string;
  end_at: string;
};

type AvailabilityResponse = {
  slots: AvailabilitySlot[];
  availability_status: string;
  metadata: { tz: string; generated_at: string };
};

type LoaderData = {
  rules: AvailabilityRule[];
  timezone: string;
  nextSlots: AvailabilitySlot[] | null;
  userId: string;
};

type ActionData =
  | { success: true; intent: "create" | "update" | "delete" | "timezone"; warn_no_rules?: boolean }
  | { success: false; intent: string; error: string };

// ── Helpers ──────────────────────────────────────────────────────────────────

function timeToMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function formatTime(hhmm: string): string {
  return hhmm.slice(0, 5);
}

// ── Loader ───────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  // Fetch current availability rules + timezone
  const rulesData = await apiGet<RulesResponse>(
    env,
    session.token,
    `/api/experts/${userId}/availability/rules`,
  ).catch(() => ({ rules: [], timezone: "UTC" }));

  // Fetch next slots (best-effort — may be not_configured)
  let nextSlots: AvailabilitySlot[] | null = null;
  try {
    const avail = await apiGet<AvailabilityResponse>(
      env,
      session.token,
      `/api/experts/${userId}/availability`,
    );
    if (avail.availability_status === "configured") {
      nextSlots = avail.slots.slice(0, 5);
    }
  } catch {
    // Non-blocking
  }

  return Response.json(
    {
      rules: rulesData.rules,
      timezone: rulesData.timezone,
      nextSlots,
      userId,
    } satisfies LoaderData,
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

  // Create rule
  if (intent === "create") {
    const day_of_week = Number(formData.get("day_of_week"));
    const start_time = String(formData.get("start_time") ?? "");
    const end_time = String(formData.get("end_time") ?? "");

    try {
      await apiPost(env, session.token, `/api/experts/${userId}/availability/rules`, {
        day_of_week,
        start_time,
        end_time,
      });
      return Response.json({ success: true, intent: "create" } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      const body = err instanceof ApiError ? (err.body as Record<string, string> | null) : null;
      const errorMsg = body?.error === "overlapping_rule"
        ? "Ce créneau chevauche une règle existante."
        : "Impossible de créer la règle. Vérifiez les données.";
      return Response.json(
        { success: false, intent: "create", error: errorMsg } satisfies ActionData,
        { status },
      );
    }
  }

  // Update rule
  if (intent === "update") {
    const rule_id = String(formData.get("rule_id") ?? "");
    const day_of_week = Number(formData.get("day_of_week"));
    const start_time = String(formData.get("start_time") ?? "");
    const end_time = String(formData.get("end_time") ?? "");

    try {
      await apiPut(env, session.token, `/api/experts/${userId}/availability/rules/${rule_id}`, {
        day_of_week,
        start_time,
        end_time,
      });
      return Response.json({ success: true, intent: "update" } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      const body = err instanceof ApiError ? (err.body as Record<string, string> | null) : null;
      const errorMsg = body?.error === "overlapping_rule"
        ? "Ce créneau chevauche une règle existante."
        : "Impossible de mettre à jour la règle.";
      return Response.json(
        { success: false, intent: "update", error: errorMsg } satisfies ActionData,
        { status },
      );
    }
  }

  // Delete rule (soft delete)
  if (intent === "delete") {
    const rule_id = String(formData.get("rule_id") ?? "");

    try {
      await apiDelete(env, session.token, `/api/experts/${userId}/availability/rules/${rule_id}`);

      // Check remaining active rules count
      const rulesData = await apiGet<RulesResponse>(
        env,
        session.token,
        `/api/experts/${userId}/availability/rules`,
      ).catch(() => ({ rules: [], timezone: "UTC" }));

      const warn_no_rules = rulesData.rules.length === 0;
      return Response.json({ success: true, intent: "delete", warn_no_rules } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "delete",
          error: "Impossible de supprimer la règle.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  // Update timezone
  if (intent === "timezone") {
    const timezone = String(formData.get("timezone") ?? "UTC");

    try {
      await apiPatch(env, session.token, `/api/experts/${userId}/profile`, { timezone });
      return Response.json({ success: true, intent: "timezone" } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "timezone",
          error: "Impossible de mettre à jour le fuseau horaire.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  return Response.json(
    { success: false, intent, error: "Action inconnue." } satisfies ActionData,
    { status: 400 },
  );
}

// ── Page component ───────────────────────────────────────────────────────────

export default function AvailabilityPage() {
  const { rules, timezone, nextSlots, userId } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const fetcher = useFetcher();

  // Form state
  const [formOpen, setFormOpen] = useState(false);
  const [editingRule, setEditingRule] = useState<AvailabilityRule | null>(null);
  const [formDay, setFormDay] = useState<number>(1);
  const [formStart, setFormStart] = useState("09:00");
  const [formEnd, setFormEnd] = useState("18:00");

  // Delete confirmation state
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deletingRuleId, setDeletingRuleId] = useState<string | null>(null);

  // AC11: warn when all rules deleted
  useEffect(() => {
    if (!actionData) return;
    if (actionData.success) {
      if (actionData.intent === "delete" && actionData.warn_no_rules) {
        toast.warning(
          "Sans disponibilités, vous ne recevrez plus de réservations.",
        );
      } else if (actionData.intent === "create") {
        toast.success("Règle créée avec succès.");
        setFormOpen(false);
      } else if (actionData.intent === "update") {
        toast.success("Règle mise à jour.");
        setFormOpen(false);
        setEditingRule(null);
      } else if (actionData.intent === "delete") {
        toast.success("Règle supprimée.");
        setDeleteOpen(false);
        setDeletingRuleId(null);
      } else if (actionData.intent === "timezone") {
        toast.success("Fuseau horaire mis à jour.");
      }
    } else {
      toast.error(actionData.error);
    }
  }, [actionData]);

  function openCreateForm(dayOfWeek: number) {
    setEditingRule(null);
    setFormDay(dayOfWeek);
    setFormStart("09:00");
    setFormEnd("18:00");
    setFormOpen(true);
  }

  function openEditForm(rule: AvailabilityRule) {
    setEditingRule(rule);
    setFormDay(rule.day_of_week);
    setFormStart(formatTime(rule.start_time));
    setFormEnd(formatTime(rule.end_time));
    setFormOpen(true);
  }

  function openDeleteConfirm(ruleId: string) {
    setDeletingRuleId(ruleId);
    setDeleteOpen(true);
  }

  // Build a map of rules per day_of_week for grid rendering
  const rulesByDay: Record<number, AvailabilityRule[]> = {};
  for (const rule of rules) {
    if (!rulesByDay[rule.day_of_week]) rulesByDay[rule.day_of_week] = [];
    rulesByDay[rule.day_of_week]!.push(rule);
  }

  const isSubmitting = fetcher.state !== "idle";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Disponibilités</h1>
        <p className="text-muted-foreground mt-1">
          Définissez vos plages horaires hebdomadaires récurrentes.
        </p>
      </div>

      {/* Timezone selector */}
      <Card>
        <CardHeader>
          <CardTitle>Fuseau horaire</CardTitle>
          <CardDescription>
            Toutes les plages horaires ci-dessous sont exprimées dans ce fuseau.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form method="post" className="flex items-center gap-3">
            <input type="hidden" name="intent" value="timezone" />
            <select
              name="timezone"
              defaultValue={timezone}
              className="flex h-9 rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus:outline-none focus:ring-1 focus:ring-ring"
            >
              {COMMON_TIMEZONES.map((tz) => (
                <option key={tz} value={tz}>
                  {tz}
                </option>
              ))}
            </select>
            <Button type="submit" variant="outline" size="sm">
              Enregistrer
            </Button>
          </Form>
        </CardContent>
      </Card>

      {/* Weekly grid */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Grille hebdomadaire</CardTitle>
              <CardDescription>
                Cliquez sur une plage vide pour ajouter une règle. Cliquez sur une règle pour la modifier.
              </CardDescription>
            </div>
            <Button
              type="button"
              size="sm"
              onClick={() => openCreateForm(1)}
            >
              + Ajouter
            </Button>
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <div className="flex min-w-[600px]">
            {/* Time labels column */}
            <div className="w-14 flex-shrink-0">
              {/* Header spacer */}
              <div style={{ height: ROW_HEIGHT_PX }} />
              {Array.from({ length: ROWS }, (_, i) => {
                const totalMinutes = GRID_START_HOUR * 60 + i * 30;
                const h = Math.floor(totalMinutes / 60);
                const m = totalMinutes % 60;
                return (
                  <div
                    key={i}
                    style={{ height: ROW_HEIGHT_PX }}
                    className="flex items-center justify-end pr-2 text-xs text-muted-foreground border-t border-border/30"
                  >
                    {i % 2 === 0 ? `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}` : ""}
                  </div>
                );
              })}
            </div>

            {/* Day columns */}
            {DAY_DISPLAY.map(({ label, dayOfWeek }) => {
              const dayRules = rulesByDay[dayOfWeek] ?? [];
              return (
                <div key={dayOfWeek} className="flex-1 min-w-0">
                  {/* Day header */}
                  <div
                    style={{ height: ROW_HEIGHT_PX }}
                    className="flex items-center justify-center text-sm font-medium border-b border-border"
                  >
                    {label}
                  </div>

                  {/* Grid body */}
                  <div
                    className="relative border-l border-border/50"
                    style={{ height: ROWS * ROW_HEIGHT_PX }}
                    onClick={() => openCreateForm(dayOfWeek)}
                  >
                    {/* Row lines */}
                    {Array.from({ length: ROWS }, (_, i) => (
                      <div
                        key={i}
                        style={{ top: i * ROW_HEIGHT_PX, height: ROW_HEIGHT_PX }}
                        className="absolute inset-x-0 border-t border-border/20"
                      />
                    ))}

                    {/* Rule overlays */}
                    {dayRules.map((rule) => {
                      const startMin = timeToMinutes(formatTime(rule.start_time));
                      const endMin = timeToMinutes(formatTime(rule.end_time));
                      const gridStartMin = GRID_START_HOUR * 60;
                      const topPx = ((startMin - gridStartMin) / 30) * ROW_HEIGHT_PX;
                      const heightPx = ((endMin - startMin) / 30) * ROW_HEIGHT_PX;

                      return (
                        <div
                          key={rule.id}
                          className="absolute inset-x-1 rounded bg-primary/20 border border-primary/40 cursor-pointer hover:bg-primary/30 transition-colors overflow-hidden px-1"
                          style={{ top: topPx, height: Math.max(heightPx, 20) }}
                          onClick={(e) => {
                            e.stopPropagation();
                            openEditForm(rule);
                          }}
                        >
                          <p className="text-xs font-medium text-primary truncate leading-tight mt-0.5">
                            {formatTime(rule.start_time)}–{formatTime(rule.end_time)}
                          </p>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {/* Next 5 available slots (AC9) */}
      <Card>
        <CardHeader>
          <CardTitle>Prochains créneaux disponibles</CardTitle>
          <CardDescription>
            Calculés à partir de vos règles hebdomadaires.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {nextSlots && nextSlots.length > 0 ? (
            <ul className="space-y-2">
              {nextSlots.map((slot) => (
                <li key={slot.start_at} className="text-sm flex gap-2">
                  <span className="font-medium">
                    {new Date(slot.start_at).toLocaleDateString("fr-FR", {
                      weekday: "long",
                      month: "long",
                      day: "numeric",
                    })}
                  </span>
                  <span className="text-muted-foreground">
                    {new Date(slot.start_at).toLocaleTimeString("fr-FR", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                    {"–"}
                    {new Date(slot.end_at).toLocaleTimeString("fr-FR", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">
              Aucun créneau disponible. Ajoutez des règles de disponibilité pour commencer à recevoir des réservations.
            </p>
          )}
        </CardContent>
      </Card>

      {/* Rule create/edit form dialog */}
      <Dialog open={formOpen} onOpenChange={(open) => { setFormOpen(open); if (!open) setEditingRule(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {editingRule ? "Modifier la règle" : "Nouvelle règle"}
            </DialogTitle>
            <DialogDescription>
              Définissez le jour et les heures de disponibilité.
            </DialogDescription>
          </DialogHeader>

          <Form method="post" className="space-y-4">
            <input type="hidden" name="intent" value={editingRule ? "update" : "create"} />
            {editingRule && <input type="hidden" name="rule_id" value={editingRule.id} />}

            {/* Day selector */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Jour</label>
              <select
                name="day_of_week"
                value={formDay}
                onChange={(e) => setFormDay(Number(e.target.value))}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus:outline-none focus:ring-1 focus:ring-ring"
              >
                {DAY_DISPLAY.map(({ label, dayOfWeek }) => (
                  <option key={dayOfWeek} value={dayOfWeek}>
                    {label}
                  </option>
                ))}
              </select>
            </div>

            {/* Start time */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Début</label>
              <input
                type="time"
                name="start_time"
                value={formStart}
                onChange={(e) => setFormStart(e.target.value)}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus:outline-none focus:ring-1 focus:ring-ring"
                required
              />
            </div>

            {/* End time */}
            <div className="space-y-1">
              <label className="text-sm font-medium">Fin</label>
              <input
                type="time"
                name="end_time"
                value={formEnd}
                onChange={(e) => setFormEnd(e.target.value)}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus:outline-none focus:ring-1 focus:ring-ring"
                required
              />
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => { setFormOpen(false); setEditingRule(null); }}
              >
                Annuler
              </Button>
              {editingRule && (
                <Button
                  type="button"
                  variant="destructive"
                  onClick={() => {
                    setFormOpen(false);
                    openDeleteConfirm(editingRule.id);
                  }}
                >
                  Supprimer
                </Button>
              )}
              <Button type="submit" disabled={isSubmitting}>
                {editingRule ? "Mettre à jour" : "Créer"}
              </Button>
            </DialogFooter>
          </Form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation dialog */}
      <Dialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Supprimer la règle</DialogTitle>
            <DialogDescription>
              Cette règle de disponibilité sera désactivée. Cette action ne peut pas être annulée.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteOpen(false)} type="button">
              Annuler
            </Button>
            <Form method="post">
              <input type="hidden" name="intent" value="delete" />
              <input type="hidden" name="rule_id" value={deletingRuleId ?? ""} />
              <Button variant="destructive" type="submit">
                Supprimer
              </Button>
            </Form>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
