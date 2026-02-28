import { Link, useLoaderData, useSearchParams } from "react-router";
import type { LoaderFunctionArgs } from "react-router";
import { useEffect } from "react";
import { toast } from "sonner";
import { requireSession } from "~/lib/session.server";
import { apiGet } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { Badge } from "~/components/ui/badge";
import { Progress } from "~/components/ui/progress";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";
import { TrendingUp, TrendingDown, Minus, CheckCircle, Lock, Clock } from "lucide-react";

// ── Types ─────────────────────────────────────────────────────────────────────

type QualityTier = "New" | "Rising" | "Established" | "Top";

type MonthStats = {
  leads_received: number;
  leads_confirmed: number;
  leads_flagged: number;
  bookings_total: number;
  bookings_completed: number;
  conversions_declared: number;
};

type MonthHistory = MonthStats & { month: string };

type MilestoneInfo = {
  unlocked: boolean;
  unlocked_at: string | null;
  available_at: string | null;
  credits: number;
};

type DashboardIndexResponse = {
  unread_leads: number;
  upcoming_bookings: number;
  credit_balance: number;
  composite_score: number | null;
  quality_tier: QualityTier;
  month_stats: MonthStats;
  monthly_history: MonthHistory[];
  // E02S10/AC7: Profile completion milestones
  milestones?: {
    matchable: MilestoneInfo;
    bookable: MilestoneInfo;
    trust: MilestoneInfo;
  };
};

type LoaderData = { data: DashboardIndexResponse; userId: string };

// ── Helpers ────────────────────────────────────────────────────────────────────

function centsToEur(cents: number): string {
  return (cents / 100).toFixed(2);
}

function getTierBadgeClass(tier: QualityTier): string {
  switch (tier) {
    case "Top":
      return "bg-yellow-100 text-yellow-800 border border-yellow-300";
    case "Established":
      return "bg-green-100 text-green-800 border border-green-200";
    case "Rising":
      return "bg-blue-100 text-blue-800 border border-blue-200";
    default:
      return "bg-gray-100 text-gray-800 border border-gray-200";
  }
}

function getTierLabel(tier: QualityTier): string {
  switch (tier) {
    case "Top":
      return "Expert Top";
    case "Established":
      return "Expert Confirmé";
    case "Rising":
      return "Expert Prometteur";
    default:
      return "Nouvel Expert";
  }
}

// ── Loader ────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const defaultData: DashboardIndexResponse = {
    unread_leads: 0,
    upcoming_bookings: 0,
    credit_balance: 0,
    composite_score: null,
    quality_tier: "New",
    month_stats: {
      leads_received: 0,
      leads_confirmed: 0,
      leads_flagged: 0,
      bookings_total: 0,
      bookings_completed: 0,
      conversions_declared: 0,
    },
    monthly_history: [],
    milestones: undefined,
  };

  const data = await apiGet<DashboardIndexResponse>(
    env,
    session.token,
    `/api/experts/${userId}/dashboard`,
  ).catch(() => defaultData);

  captureEvent(env, `expert:${userId}`, "expert.dashboard_viewed", {
    unread_leads: data.unread_leads,
    upcoming_bookings: data.upcoming_bookings,
  }).catch(() => {});

  return Response.json(
    { data, userId } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

// ── Component ─────────────────────────────────────────────────────────────────

export default function DashboardIndex() {
  const { data } = useLoaderData<typeof loader>();
  const [searchParams] = useSearchParams();

  // Retain welcome toast from E02S01
  useEffect(() => {
    if (searchParams.get("welcome") === "1") {
      toast.success("Votre profil est prêt ! Vous commencerez à recevoir des leads qualifiés.");
    }
  }, [searchParams]);

  const {
    unread_leads,
    upcoming_bookings,
    credit_balance,
    composite_score,
    quality_tier,
    month_stats,
    monthly_history,
    milestones,
  } = data;

  // monthly_history is ASCENDING: index 0 = oldest, index [length-1] = current month
  // previous month = index [length-2]
  const prevHistory =
    monthly_history.length >= 2
      ? monthly_history[monthly_history.length - 2]
      : null;

  function TrendArrow({ curr, prev }: { curr: number; prev: number | null }) {
    if (prev === null) return <Minus className="h-3 w-3 text-muted-foreground inline" />;
    if (curr > prev) return <TrendingUp className="h-3 w-3 text-green-600 inline" />;
    if (curr < prev) return <TrendingDown className="h-3 w-3 text-red-600 inline" />;
    return <Minus className="h-3 w-3 text-muted-foreground inline" />;
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Vue d&apos;ensemble</h1>
        <p className="text-muted-foreground mt-1">Votre activité en un coup d&apos;œil.</p>
      </div>

      {/* AC7: Summary cards grid */}
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {/* Leads non lus */}
        <Link to="/dashboard/leads?status=new">
          <Card className="hover:shadow-md transition-shadow cursor-pointer">
            <CardHeader className="pb-2">
              <CardDescription>Leads non lus</CardDescription>
              <CardTitle className="text-3xl tabular-nums">{unread_leads}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-primary">Voir les leads →</p>
            </CardContent>
          </Card>
        </Link>

        {/* Rendez-vous à venir */}
        <Link to="/dashboard/bookings">
          <Card className="hover:shadow-md transition-shadow cursor-pointer">
            <CardHeader className="pb-2">
              <CardDescription>Rendez-vous à venir</CardDescription>
              <CardTitle className="text-3xl tabular-nums">{upcoming_bookings}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-primary">Voir les rendez-vous →</p>
            </CardContent>
          </Card>
        </Link>

        {/* Solde de crédits */}
        <Link to="/dashboard/billing">
          <Card className="hover:shadow-md transition-shadow cursor-pointer">
            <CardHeader className="pb-2">
              <CardDescription>Solde de crédits</CardDescription>
              <CardTitle
                className={[
                  "text-3xl tabular-nums",
                  credit_balance > 0 ? "text-green-600" : "text-red-600",
                ].join(" ")}
              >
                {centsToEur(credit_balance)}€
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-primary">Voir la facturation →</p>
            </CardContent>
          </Card>
        </Link>

        {/* Score composite */}
        <Link to="/dashboard/analytics">
          <Card className="hover:shadow-md transition-shadow cursor-pointer">
            <CardHeader className="pb-2">
              <CardDescription>Score composite</CardDescription>
              <CardTitle className="text-3xl tabular-nums">
                {composite_score !== null ? composite_score : "—"}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Badge className={getTierBadgeClass(quality_tier)}>
                {getTierLabel(quality_tier)}
              </Badge>
            </CardContent>
          </Card>
        </Link>
      </div>

      {/* AC7: Profile completion milestones section */}
      {milestones && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Complétion du profil</CardTitle>
            <CardDescription>
              Complétez votre profil pour débloquer vos crédits de bienvenue (100EUR au total).
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Progress bar */}
            {(() => {
              const unlocked = [milestones.matchable, milestones.bookable, milestones.trust].filter(m => m.unlocked).length;
              return (
                <div className="space-y-1">
                  <div className="flex justify-between text-xs text-muted-foreground">
                    <span>{unlocked}/3 jalons atteints</span>
                    <span>{unlocked === 3 ? "100%" : unlocked === 2 ? "67%" : unlocked === 1 ? "33%" : "0%"}</span>
                  </div>
                  <Progress value={Math.round((unlocked / 3) * 100)} className="h-2" />
                </div>
              );
            })()}
            {/* Milestone cards */}
            <div className="grid gap-3 md:grid-cols-3">
              {[
                {
                  key: "matchable" as const,
                  label: "Matchable",
                  credit: "40EUR",
                  missing: "Nom affiché (2+ chars) + bio (50+ chars) + 3 compétences",
                  info: milestones.matchable,
                },
                {
                  key: "bookable" as const,
                  label: "Réservable",
                  credit: "40EUR",
                  missing: "Définissez vos disponibilités hebdomadaires",
                  info: milestones.bookable,
                },
                {
                  key: "trust" as const,
                  label: "De confiance",
                  credit: "20EUR",
                  missing: "Photo de profil ou lien portfolio/LinkedIn/GitHub",
                  info: milestones.trust,
                },
              ].map(({ label, credit, missing, info }) => {
                const now = new Date();
                const isPending = info.unlocked && info.available_at ? new Date(info.available_at) > now : false;
                return (
                  <div
                    key={label}
                    className={[
                      "rounded-lg border p-3 text-sm",
                      info.unlocked && !isPending ? "border-green-200 bg-green-50" :
                      isPending ? "border-amber-200 bg-amber-50" :
                      "border-gray-200 bg-gray-50",
                    ].join(" ")}
                  >
                    <div className="flex items-center gap-2 mb-1">
                      {info.unlocked && !isPending ? (
                        <CheckCircle className="h-4 w-4 text-green-600 flex-shrink-0" />
                      ) : isPending ? (
                        <Clock className="h-4 w-4 text-amber-600 flex-shrink-0" />
                      ) : (
                        <Lock className="h-4 w-4 text-gray-400 flex-shrink-0" />
                      )}
                      <span className="font-medium">{label}</span>
                      <span className={[
                        "ml-auto text-xs font-semibold",
                        info.unlocked && !isPending ? "text-green-700" : "text-muted-foreground",
                      ].join(" ")}>{credit}</span>
                    </div>
                    {info.unlocked && !isPending && info.unlocked_at && (
                      <p className="text-xs text-green-700">
                        Crédité le {new Date(info.unlocked_at).toLocaleDateString("fr-FR")}
                      </p>
                    )}
                    {isPending && info.available_at && (
                      <p className="text-xs text-amber-700">
                        Disponible le {new Date(info.available_at).toLocaleDateString("fr-FR")}
                      </p>
                    )}
                    {!info.unlocked && (
                      <p className="text-xs text-muted-foreground">
                        Complétez&#8239;: {missing}
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
            {/* CTA if any milestone unlocked */}
            {[milestones.matchable, milestones.bookable, milestones.trust].some(m => !m.unlocked) && (
              <p className="text-xs text-muted-foreground">
                <Link to="/dashboard/settings" className="text-primary hover:underline">
                  Compléter mon profil →
                </Link>
              </p>
            )}
          </CardContent>
        </Card>
      )}

      {/* Monthly summary */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Ce mois</CardTitle>
          <CardDescription>
            Activité du mois en cours vs mois précédent
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {[
              {
                label: "Leads reçus",
                curr: month_stats.leads_received,
                prev: prevHistory?.leads_received ?? null,
              },
              {
                label: "Leads confirmés",
                curr: month_stats.leads_confirmed,
                prev: prevHistory?.leads_confirmed ?? null,
              },
              {
                label: "Leads signalés",
                curr: month_stats.leads_flagged,
                prev: prevHistory?.leads_flagged ?? null,
              },
            ].map((row) => (
              <div
                key={row.label}
                className="flex items-center justify-between text-sm"
              >
                <span className="text-muted-foreground">{row.label}</span>
                <div className="flex items-center gap-2">
                  <span className="font-medium tabular-nums">{row.curr}</span>
                  <TrendArrow curr={row.curr} prev={row.prev} />
                  {row.prev !== null && (
                    <span className="text-xs text-muted-foreground">
                      ({row.prev} préc.)
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
