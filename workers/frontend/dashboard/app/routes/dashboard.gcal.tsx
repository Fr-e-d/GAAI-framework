import { Form, useFetcher, useActionData, useLoaderData } from "react-router";
import type { ActionFunctionArgs, LoaderFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { useState, useEffect } from "react";
import { requireSession } from "~/lib/session.server";
import { apiGet, apiDelete, ApiError } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { toast } from "sonner";
import { Button } from "~/components/ui/button";
import { Badge } from "~/components/ui/badge";
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

// ── Types ──────────────────────────────────────────────────────────────────────

type GcalStatus = {
  connected: boolean;
  google_email: string | null;
  connected_at: string | null;
};

type AvailabilitySlot = {
  start: string;
  end: string;
};

type AvailabilityResponse = {
  slots: AvailabilitySlot[];
  metadata: { tz: string; generated_at: string };
};

type LoaderData = {
  gcalStatus: GcalStatus | null;
  slots: AvailabilitySlot[] | null;
  generatedAt: string | null;
  userId: string;
};

type ActionData =
  | { success: true; action: "disconnect" }
  | { success: false; action: "disconnect" | "connect"; error: string };

// ── Loader ─────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  // AC1: Fetch GCal connection status
  const gcalStatus = await apiGet<GcalStatus>(
    env,
    session.token,
    `/api/experts/${userId}/gcal/status`,
  ).catch(() => null);

  // AC7: Fetch next 5 availability slots — only when connected
  let slots: AvailabilitySlot[] | null = null;
  let generatedAt: string | null = null;

  if (gcalStatus?.connected) {
    try {
      const avail = await apiGet<AvailabilityResponse>(
        env,
        session.token,
        `/api/experts/${userId}/availability`,
      );
      slots = avail.slots.slice(0, 5);
      generatedAt = avail.metadata.generated_at;
    } catch {
      // Non-blocking — availability unavailable but page still renders
    }
  }

  return Response.json(
    { gcalStatus, slots, generatedAt, userId } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

// ── Action ─────────────────────────────────────────────────────────────────────

export async function action({ request, context }: ActionFunctionArgs) {
  const { session } = await requireSession(request, context.cloudflare.env);
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const formData = await request.formData();
  const intent = String(formData.get("intent") ?? "");

  // AC4: Connect — fetch auth URL and redirect to Google OAuth
  if (intent === "connect") {
    try {
      const { auth_url } = await apiGet<{ auth_url: string }>(
        env,
        session.token,
        `/api/experts/${userId}/gcal/auth-url`,
      );
      // PostHog: expert.gcal_connect_started (fire-and-forget)
      captureEvent(env, `expert:${userId}`, "expert.gcal_connect_started", {}).catch(
        () => {},
      );
      return redirect(auth_url);
    } catch {
      return Response.json(
        {
          success: false,
          action: "connect",
          error: "Impossible de démarrer la connexion. Veuillez réessayer.",
        } satisfies ActionData,
        { status: 500 },
      );
    }
  }

  // AC6: Disconnect — call DELETE endpoint with confirmation
  if (intent === "disconnect") {
    try {
      await apiDelete(env, session.token, `/api/experts/${userId}/gcal/disconnect`);
      // PostHog: expert.gcal_disconnected (fire-and-forget, also fired by API)
      captureEvent(env, `expert:${userId}`, "expert.gcal_disconnected", {}).catch(
        () => {},
      );
      return Response.json({ success: true, action: "disconnect" } satisfies ActionData);
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 500;
      return Response.json(
        {
          success: false,
          action: "disconnect",
          error: "Impossible de déconnecter le calendrier. Veuillez réessayer.",
        } satisfies ActionData,
        { status },
      );
    }
  }

  return Response.json(
    { success: false, action: "disconnect", error: "Action inconnue." } satisfies ActionData,
    { status: 400 },
  );
}

// ── Page component ─────────────────────────────────────────────────────────────

export default function GcalPage() {
  const { gcalStatus, slots, generatedAt } = useLoaderData<typeof loader>();
  const actionData = useActionData() as ActionData | undefined;
  const fetcher = useFetcher();
  const [disconnectOpen, setDisconnectOpen] = useState(false);

  // AC5: Detect return from OAuth connect via sessionStorage flash
  // When connect action succeeds, sessionStorage flag is set. On next mount with connected=true, show toast.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const pending = sessionStorage.getItem("gcalPendingConnect");
    if (pending && gcalStatus?.connected) {
      toast.success("Google Calendar connecté avec succès");
      sessionStorage.removeItem("gcalPendingConnect");
    }
  }, [gcalStatus?.connected]);

  // AC6: Disconnect success / error toasts from actionData
  useEffect(() => {
    if (!actionData) return;
    if (actionData.success && actionData.action === "disconnect") {
      toast.success("Google Calendar déconnecté");
      setDisconnectOpen(false);
    } else if (!actionData.success) {
      toast.error(actionData.error);
    }
  }, [actionData]);

  const refreshingSlots = fetcher.state !== "idle";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Google Calendar</h1>
        <p className="text-muted-foreground mt-1">
          Connectez votre calendrier pour recevoir des réservations automatiques.
        </p>
      </div>

      {/* AC1 / AC2 / AC3: Connection status card */}
      <Card>
        <CardHeader>
          <CardTitle>Statut de connexion</CardTitle>
          <CardDescription>
            Votre calendrier Google est utilisé pour afficher vos disponibilités aux prospects.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {gcalStatus?.connected ? (
            <>
              {/* AC2: Connected state */}
              <div className="flex items-center gap-3">
                <Badge className="bg-green-600 hover:bg-green-600">Connecté</Badge>
                <span className="text-sm text-muted-foreground">
                  {gcalStatus.google_email ?? ""}
                </span>
              </div>
              <Button
                variant="destructive"
                onClick={() => setDisconnectOpen(true)}
                type="button"
              >
                Déconnecter
              </Button>
            </>
          ) : (
            <>
              {/* AC3: Not connected state */}
              <div className="flex items-center gap-3">
                <Badge variant="outline" className="border-yellow-500 text-yellow-600">
                  Non connecté
                </Badge>
              </div>
              <p className="text-sm text-muted-foreground">
                Connectez votre calendrier Google pour afficher vos disponibilités et recevoir
                des réservations automatiques.
              </p>
              {/* AC4: Connect button — form action redirects to Google OAuth */}
              <Form method="post">
                <input type="hidden" name="intent" value="connect" />
                <Button
                  type="submit"
                  onClick={() => {
                    if (typeof window !== "undefined") {
                      sessionStorage.setItem("gcalPendingConnect", "1");
                    }
                  }}
                >
                  Connecter Google Calendar
                </Button>
              </Form>
            </>
          )}
        </CardContent>
      </Card>

      {/* AC7 / AC8: Availability preview — only shown when connected */}
      {gcalStatus?.connected && (
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle>Prochains créneaux disponibles</CardTitle>
                {generatedAt && (
                  <CardDescription>
                    Actualisé à{" "}
                    {new Date(generatedAt).toLocaleTimeString("fr-FR", {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </CardDescription>
                )}
              </div>
              {/* AC7: Refresh button */}
              <fetcher.Form method="get" action="/dashboard/gcal">
                <Button variant="outline" size="sm" type="submit" disabled={refreshingSlots}>
                  {refreshingSlots ? "Actualisation..." : "Actualiser"}
                </Button>
              </fetcher.Form>
            </div>
          </CardHeader>
          <CardContent>
            {slots && slots.length > 0 ? (
              <ul className="space-y-2">
                {slots.map((slot) => (
                  <li key={slot.start} className="text-sm flex gap-2">
                    <span className="font-medium">
                      {new Date(slot.start).toLocaleDateString("fr-FR", {
                        weekday: "long",
                        month: "long",
                        day: "numeric",
                      })}
                    </span>
                    <span className="text-muted-foreground">
                      {new Date(slot.start).toLocaleTimeString("fr-FR", {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                      {"–"}
                      {new Date(slot.end).toLocaleTimeString("fr-FR", {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              // AC8: No slots available
              <p className="text-sm text-muted-foreground">
                Aucun créneau disponible dans les 7 prochains jours. Vérifiez votre agenda
                Google.
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {/* AC6: Disconnect confirmation dialog */}
      <Dialog open={disconnectOpen} onOpenChange={setDisconnectOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Déconnecter Google Calendar</DialogTitle>
            <DialogDescription>
              Êtes-vous sûr de vouloir déconnecter votre Google Calendar ? Les prospects ne
              pourront plus réserver de créneaux sur votre calendrier.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDisconnectOpen(false)} type="button">
              Annuler
            </Button>
            <Form method="post">
              <input type="hidden" name="intent" value="disconnect" />
              <Button variant="destructive" type="submit">
                Déconnecter
              </Button>
            </Form>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
