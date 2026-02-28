import { Form, Link, useActionData, useLoaderData, useSearchParams } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { useState, useEffect } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiPost, apiDeleteWithBody, ApiError } from "~/lib/api.server";
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
import { Input } from "~/components/ui/input";
import { Separator } from "~/components/ui/separator";
import { Calendar } from "lucide-react";

// ── Types ─────────────────────────────────────────────────────────────────────

type BookingStatus =
  | "held"
  | "confirmed"
  | "cancelled"
  | "no_show"
  | "pending_confirmation"
  | "expired_no_confirmation"
  | "cancelled_by_prospect"
  | "pending_expert_approval";

type Prospect = {
  id: string;
  email: string | null;
  name: string | null;
};

type Booking = {
  id: string;
  starts_at: string;
  ends_at: string;
  status: BookingStatus;
  meeting_url: string | null;
  cancel_reason: string | null;
  prospect: Prospect | null;
  created_at: string;
  formatted_datetime: string; // pre-formatted by loader
};

type BookingsResponse = {
  bookings: Omit<Booking, "formatted_datetime">[];
  total: number;
  page: number;
  per_page: number;
};

type LoaderData = {
  bookings: Booking[];
  total: number;
  page: number;
  per_page: number;
  period: string;
  userId: string;
};

type ActionData =
  | { success: true; intent: "cancel"; bookingId: string }
  | { success: true; intent: "reschedule"; bookingId: string }
  | { success: true; intent: "no-show"; bookingId: string }
  | { success: false; intent: "cancel" | "reschedule" | "no-show"; error: string }
  | { success: false; intent: "unknown"; error: string };

// ── Helpers ───────────────────────────────────────────────────────────────────

export function formatBookingDatetime(startsAt: string, endsAt: string): string {
  const fmtDate = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "UTC",
    weekday: "short",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
  const fmtTime = new Intl.DateTimeFormat("fr-FR", {
    timeZone: "UTC",
    hour: "2-digit",
    minute: "2-digit",
  });

  const start = new Date(startsAt);
  const end = new Date(endsAt);

  const datePart = fmtDate.format(start);
  const startTime = fmtTime.format(start);
  const endTime = fmtTime.format(end);

  // Capitalize first character
  const capitalized = datePart.charAt(0).toUpperCase() + datePart.slice(1);

  return `${capitalized}, ${startTime} — ${endTime}`;
}

export function bookingStatusDisplay(
  status: BookingStatus,
  period: string,
): { label: string; badgeClass: string } {
  if (period === "past" && status !== "cancelled") {
    return { label: "Terminé", badgeClass: "bg-gray-100 text-gray-800 border border-gray-200" };
  }
  switch (status) {
    case "held":
      return {
        label: "En attente",
        badgeClass: "bg-yellow-100 text-yellow-800 border border-yellow-200",
      };
    case "confirmed":
      return {
        label: "Confirmé",
        badgeClass: "bg-green-100 text-green-800 border border-green-200",
      };
    case "cancelled":
      return {
        label: "Annulé",
        badgeClass: "bg-red-100 text-red-800 border border-red-200",
      };
    case "no_show":
      return { label: "Absent", badgeClass: "bg-orange-100 text-orange-800 border border-orange-200" };
    case "pending_confirmation":
      return { label: "En attente de confirmation", badgeClass: "bg-yellow-100 text-yellow-800 border border-yellow-200" };
    case "expired_no_confirmation":
      return { label: "Expiré", badgeClass: "bg-gray-100 text-gray-800 border border-gray-200" };
    case "cancelled_by_prospect":
      return { label: "Annulé par le prospect", badgeClass: "bg-red-100 text-red-800 border border-red-200" };
    case "pending_expert_approval":
      return { label: "Approbation requise", badgeClass: "bg-purple-100 text-purple-800 border border-purple-200" };
    default:
      return { label: status, badgeClass: "bg-gray-100 text-gray-800 border border-gray-200" };
  }
}

export function buildTabUrl(period: string, currentParams: URLSearchParams): string {
  const params = new URLSearchParams(currentParams);
  params.set("period", period);
  params.delete("page");
  return `/dashboard/bookings?${params.toString()}`;
}

export function buildPageUrl(page: number, period: string): string {
  const params = new URLSearchParams();
  params.set("period", period);
  params.set("page", String(page));
  return `/dashboard/bookings?${params.toString()}`;
}

const PERIOD_TABS = [
  { value: "upcoming", label: "À venir" },
  { value: "past", label: "Passés" },
] as const;

// ── Loader ────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const url = new URL(request.url);
  const period = url.searchParams.get("period") ?? "upcoming";
  const page = url.searchParams.get("page") ?? "1";

  const data = await apiGet<BookingsResponse>(
    env,
    session.token,
    `/api/experts/${userId}/bookings`,
    { period, page, per_page: "20" },
  ).catch(() => ({ bookings: [], total: 0, page: 1, per_page: 20 }));

  const bookings: Booking[] = data.bookings.map((b) => ({
    ...b,
    formatted_datetime: formatBookingDatetime(b.starts_at, b.ends_at),
  }));

  captureEvent(env, `expert:${userId}`, "expert.bookings_viewed", {
    period,
  }).catch(() => {});

  return Response.json(
    {
      bookings,
      total: data.total,
      page: data.page,
      per_page: data.per_page,
      period,
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

  if (intent === "cancel") {
    const bookingId = String(formData.get("bookingId") ?? "");
    if (!bookingId) {
      return Response.json(
        {
          success: false,
          intent: "cancel",
          error: "Booking ID manquant.",
        } satisfies ActionData,
        { status: 400 },
      );
    }

    const reason = String(formData.get("cancel_reason") ?? "").trim() || undefined;

    try {
      await apiDeleteWithBody<{ success: true }>(
        env,
        session.token,
        `/api/bookings/${bookingId}`,
        reason !== undefined ? { reason } : {},
      );
      captureEvent(env, `expert:${userId}`, "expert.booking_cancelled", {
        booking_id: bookingId,
        has_reason: reason !== undefined,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "cancel", bookingId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "cancel",
          error: "Impossible d'annuler ce rendez-vous.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  if (intent === "reschedule") {
    const bookingId = String(formData.get("bookingId") ?? "");
    if (!bookingId) {
      return Response.json(
        {
          success: false,
          intent: "reschedule",
          error: "Booking ID manquant.",
        } satisfies ActionData,
        { status: 400 },
      );
    }

    const newStartAtRaw = String(formData.get("new_start_at") ?? "").trim();
    if (!newStartAtRaw) {
      return Response.json(
        {
          success: false,
          intent: "reschedule",
          error: "La nouvelle date de début est requise.",
        } satisfies ActionData,
        { status: 422 },
      );
    }

    // Append seconds and UTC suffix for ISO 8601
    const newStartAt = `${newStartAtRaw}:00.000Z`;
    const newStartDate = new Date(newStartAt);

    if (isNaN(newStartDate.getTime()) || newStartDate.getTime() <= Date.now()) {
      return Response.json(
        {
          success: false,
          intent: "reschedule",
          error: "La nouvelle date doit être dans le futur.",
        } satisfies ActionData,
        { status: 422 },
      );
    }

    // Auto-compute end = start + 20 minutes
    const newEndAt = new Date(newStartDate.getTime() + 20 * 60 * 1000).toISOString();

    try {
      await apiPost<{ success: true }>(
        env,
        session.token,
        `/api/bookings/${bookingId}/reschedule`,
        { new_start_at: newStartAt, new_end_at: newEndAt },
      );
      captureEvent(env, `expert:${userId}`, "expert.booking_rescheduled", {
        booking_id: bookingId,
        new_start_at: newStartAt,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "reschedule", bookingId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "reschedule",
          error: "Impossible de reporter ce rendez-vous.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  if (intent === "no-show") {
    const bookingId = String(formData.get("bookingId") ?? "");
    if (!bookingId) {
      return Response.json(
        {
          success: false,
          intent: "no-show",
          error: "Booking ID manquant.",
        } satisfies ActionData,
        { status: 400 },
      );
    }

    try {
      await apiPost<{ success: true }>(env, session.token, `/api/bookings/${bookingId}/no-show`, {});
      captureEvent(env, `expert:${userId}`, "expert.booking_no_show_reported", {
        booking_id: bookingId,
      }).catch(() => {});
      return Response.json(
        { success: true, intent: "no-show", bookingId } satisfies ActionData,
      );
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          intent: "no-show",
          error: "Impossible de marquer cet appel comme absent.",
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

export default function BookingsPage() {
  const { bookings, total, page, per_page, period } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const [searchParams] = useSearchParams();

  const [selectedBooking, setSelectedBooking] = useState<Booking | null>(null);
  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const [rescheduleDialogOpen, setRescheduleDialogOpen] = useState(false);
  const [newStartAt, setNewStartAt] = useState("");

  const currentPage = Number(searchParams.get("page") ?? "1");
  const start = (currentPage - 1) * per_page + 1;
  const end = Math.min(currentPage * per_page, total);
  const totalPages = Math.ceil(total / per_page);

  const isUpcoming = period === "upcoming";

  useEffect(() => {
    if (!actionData) return;
    if (actionData.success) {
      if (actionData.intent === "cancel") {
        toast.success("Rendez-vous annulé");
        setCancelDialogOpen(false);
        setCancelReason("");
        setSelectedBooking(null);
      }
      if (actionData.intent === "reschedule") {
        toast.success("Rendez-vous reporté");
        setRescheduleDialogOpen(false);
        setNewStartAt("");
        setSelectedBooking(null);
      }
      if (actionData.intent === "no-show") {
        toast.success("Absent enregistré");
      }
    } else {
      toast.error(actionData.error);
    }
  }, [actionData]);

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div>
        <h1 className="text-2xl font-semibold">Mes Rendez-vous</h1>
        <p className="text-muted-foreground mt-1">
          Gérez vos rendez-vous à venir et consultez l&apos;historique de vos sessions passées.
        </p>
      </div>

      {/* Period tabs */}
      <div className="flex gap-1 border-b border-border">
        {PERIOD_TABS.map((tab) => {
          const isActive = period === tab.value;
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
            </Link>
          );
        })}
      </div>

      {/* Empty state or booking cards */}
      {bookings.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-16 text-center">
            <div className="mb-4 rounded-full bg-muted p-4">
              <Calendar className="h-8 w-8 text-muted-foreground" aria-hidden="true" />
            </div>
            <h2 className="text-lg font-semibold">Aucun rendez-vous pour le moment</h2>
            <p className="mt-2 max-w-sm text-sm text-muted-foreground">
              Vos rendez-vous programmés apparaîtront ici dès qu&apos;un prospect réservera
              une session avec vous.
            </p>
          </CardContent>
        </Card>
      ) : (
        <>
          <div className="space-y-4">
            {bookings.map((booking) => {
              const { label: statusLabel, badgeClass } = bookingStatusDisplay(
                booking.status,
                period,
              );
              const isActionable = isUpcoming && booking.status !== "cancelled";

              return (
                <Card key={booking.id}>
                  <CardContent className="p-4 space-y-3">
                    {/* Row 1: datetime + status badge */}
                    <div className="flex items-center justify-between">
                      <p className="font-medium text-sm">{booking.formatted_datetime}</p>
                      <Badge className={badgeClass}>{statusLabel}</Badge>
                    </div>

                    <Separator />

                    {/* Row 2: prospect name + email */}
                    <div className="text-sm text-muted-foreground">
                      {booking.prospect ? (
                        <>
                          <span className="font-medium text-foreground">
                            {booking.prospect.name ?? "Prospect"}
                          </span>
                          {booking.prospect.email && (
                            <span className="ml-2">{booking.prospect.email}</span>
                          )}
                        </>
                      ) : (
                        <span>Prospect inconnu</span>
                      )}
                    </div>

                    {/* Row 3: meeting URL + copy button */}
                    {booking.meeting_url && (
                      <div className="flex items-center gap-2 text-sm">
                        <a
                          href={booking.meeting_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-primary underline underline-offset-2 truncate max-w-xs"
                        >
                          {booking.meeting_url}
                        </a>
                        <Button
                          size="sm"
                          variant="outline"
                          type="button"
                          className="shrink-0 h-7 px-2"
                          onClick={() => {
                            navigator.clipboard
                              .writeText(booking.meeting_url!)
                              .then(() => toast.success("Lien copié"))
                              .catch(() => toast.error("Impossible de copier le lien"));
                          }}
                        >
                          Copier
                        </Button>
                      </div>
                    )}

                    {/* Row 4: action buttons */}
                    <div className="flex items-center gap-2 pt-1">
                      <Button
                        size="sm"
                        variant="outline"
                        type="button"
                        onClick={() => setSelectedBooking(booking)}
                      >
                        Voir le détail
                      </Button>
                      {isActionable && (
                        <>
                          <Button
                            size="sm"
                            variant="outline"
                            type="button"
                            onClick={() => {
                              setSelectedBooking(booking);
                              setRescheduleDialogOpen(true);
                            }}
                          >
                            Reporter
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            type="button"
                            onClick={() => {
                              setSelectedBooking(booking);
                              setCancelDialogOpen(true);
                            }}
                          >
                            Annuler
                          </Button>
                        </>
                      )}
                      {period === "past" && booking.status === "confirmed" && (
                        <Form method="post" className="inline">
                          <input type="hidden" name="intent" value="no-show" />
                          <input type="hidden" name="bookingId" value={booking.id} />
                          <Button
                            size="sm"
                            variant="outline"
                            type="submit"
                            className="border-orange-200 text-orange-700 hover:bg-orange-50"
                          >
                            Marquer comme absent
                          </Button>
                        </Form>
                      )}
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>

          {/* Pagination */}
          {total > per_page && (
            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">
                Affichage de {start}–{end} sur {total} rendez-vous
              </p>
              <div className="flex gap-2">
                {currentPage > 1 && (
                  <Link to={buildPageUrl(currentPage - 1, period)}>
                    <Button variant="outline" size="sm">
                      Précédent
                    </Button>
                  </Link>
                )}
                {currentPage < totalPages && (
                  <Link to={buildPageUrl(currentPage + 1, period)}>
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

      {/* AC5: Detail Dialog */}
      <Dialog
        open={!!selectedBooking && !cancelDialogOpen && !rescheduleDialogOpen}
        onOpenChange={(open) => {
          if (!open) setSelectedBooking(null);
        }}
      >
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Détail du rendez-vous</DialogTitle>
            <DialogDescription>
              Informations complètes sur ce rendez-vous.
            </DialogDescription>
          </DialogHeader>
          {selectedBooking && (
            <div className="space-y-4 pt-2">
              <div className="space-y-1">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">Date</p>
                <p className="font-medium">{selectedBooking.formatted_datetime}</p>
              </div>

              <div className="space-y-1">
                <p className="text-xs text-muted-foreground uppercase tracking-wide">Statut</p>
                {(() => {
                  const { label, badgeClass } = bookingStatusDisplay(
                    selectedBooking.status,
                    period,
                  );
                  return <Badge className={badgeClass}>{label}</Badge>;
                })()}
              </div>

              {selectedBooking.prospect && (
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">Prospect</p>
                  <p className="font-medium">{selectedBooking.prospect.name ?? "Prospect"}</p>
                  {selectedBooking.prospect.email && (
                    <p className="text-sm text-muted-foreground">{selectedBooking.prospect.email}</p>
                  )}
                </div>
              )}

              {selectedBooking.meeting_url && (
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">
                    Lien de réunion
                  </p>
                  <div className="flex items-center gap-2">
                    <a
                      href={selectedBooking.meeting_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-primary underline underline-offset-2 text-sm truncate max-w-xs"
                    >
                      {selectedBooking.meeting_url}
                    </a>
                    <Button
                      size="sm"
                      variant="outline"
                      type="button"
                      className="shrink-0 h-7 px-2"
                      onClick={() => {
                        navigator.clipboard
                          .writeText(selectedBooking.meeting_url!)
                          .then(() => toast.success("Lien copié"))
                          .catch(() => toast.error("Impossible de copier le lien"));
                      }}
                    >
                      Copier
                    </Button>
                  </div>
                </div>
              )}

              {selectedBooking.cancel_reason && (
                <div className="space-y-1">
                  <p className="text-xs text-muted-foreground uppercase tracking-wide">
                    Raison d&apos;annulation
                  </p>
                  <p className="text-sm">{selectedBooking.cancel_reason}</p>
                </div>
              )}

              {/* prep link: not in list API response — deferred */}

              {isUpcoming && selectedBooking.status !== "cancelled" && (
                <>
                  <Separator />
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      type="button"
                      onClick={() => {
                        setRescheduleDialogOpen(true);
                      }}
                    >
                      Reporter
                    </Button>
                    <Button
                      variant="destructive"
                      type="button"
                      onClick={() => {
                        setCancelDialogOpen(true);
                      }}
                    >
                      Annuler
                    </Button>
                  </div>
                </>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* AC6: Cancel Dialog */}
      <Dialog
        open={cancelDialogOpen}
        onOpenChange={(open) => {
          if (!open) {
            setCancelDialogOpen(false);
            setCancelReason("");
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Annuler ce rendez-vous</DialogTitle>
            <DialogDescription>
              Cette action est irréversible. Le prospect sera notifié de l&apos;annulation.
            </DialogDescription>
          </DialogHeader>
          <Form method="post" className="space-y-4">
            <input type="hidden" name="intent" value="cancel" />
            <input type="hidden" name="bookingId" value={selectedBooking?.id ?? ""} />
            <div className="space-y-2">
              <Label htmlFor="cancel_reason">Raison de l&apos;annulation (optionnel)</Label>
              <Textarea
                id="cancel_reason"
                name="cancel_reason"
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                placeholder="Indiquez pourquoi vous annulez ce rendez-vous..."
                rows={3}
              />
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                type="button"
                onClick={() => {
                  setCancelDialogOpen(false);
                  setCancelReason("");
                }}
              >
                Retour
              </Button>
              <Button variant="destructive" type="submit">
                Confirmer l&apos;annulation
              </Button>
            </DialogFooter>
          </Form>
        </DialogContent>
      </Dialog>

      {/* AC7: Reschedule Dialog */}
      <Dialog
        open={rescheduleDialogOpen}
        onOpenChange={(open) => {
          if (!open) {
            setRescheduleDialogOpen(false);
            setNewStartAt("");
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reporter ce rendez-vous</DialogTitle>
            <DialogDescription>
              Choisissez une nouvelle date et heure pour ce rendez-vous.
            </DialogDescription>
          </DialogHeader>
          <Form method="post" className="space-y-4">
            <input type="hidden" name="intent" value="reschedule" />
            <input type="hidden" name="bookingId" value={selectedBooking?.id ?? ""} />
            <div className="space-y-2">
              <Label htmlFor="new_start_at">Nouvelle date et heure</Label>
              <Input
                id="new_start_at"
                name="new_start_at"
                type="datetime-local"
                value={newStartAt}
                onChange={(e) => setNewStartAt(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                type="button"
                onClick={() => {
                  setRescheduleDialogOpen(false);
                  setNewStartAt("");
                }}
              >
                Annuler
              </Button>
              <Button type="submit" disabled={!newStartAt}>
                Confirmer le report
              </Button>
            </DialogFooter>
          </Form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
