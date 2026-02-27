import { Link, useLoaderData } from "react-router";
import type { LoaderFunctionArgs } from "react-router";
import {
  RadarChart,
  Radar,
  PolarAngleAxis,
  PolarGrid,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { requireSession } from "~/lib/session.server";
import { apiGet } from "~/lib/api.server";
import { captureEvent } from "~/lib/posthog.server";
import { Button } from "~/components/ui/button";
import { Badge } from "~/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";
import { TrendingUp, TrendingDown, Minus, BarChart2 } from "lucide-react";

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

type DashboardResponse = {
  unread_leads: number;
  upcoming_bookings: number;
  credit_balance: number;
  composite_score: number | null;
  quality_tier: QualityTier;
  month_stats: MonthStats;
  monthly_history: MonthHistory[];
};

type ProfileScores = {
  call_experience: number | null;
  trust: number | null;
  satisfaction: number | null;
  hire_rate: number | null;
  recency: number | null;
} | null;

type ProfileResponse = {
  composite_score: number | null;
  profile: ProfileScores;
};

type LoaderData = {
  dashboard: DashboardResponse;
  profileScores: ProfileScores;
  userId: string;
};

// ── Helpers (exported for tests) ──────────────────────────────────────────────

export type TierConfig = { label: string; badgeClass: string };

export function getTierConfig(tier: QualityTier): TierConfig {
  switch (tier) {
    case "Top":
      return {
        label: "Expert Top",
        badgeClass: "bg-yellow-100 text-yellow-800 border border-yellow-300",
      };
    case "Established":
      return {
        label: "Expert Confirmé",
        badgeClass: "bg-green-100 text-green-800 border border-green-200",
      };
    case "Rising":
      return {
        label: "Expert Prometteur",
        badgeClass: "bg-blue-100 text-blue-800 border border-blue-200",
      };
    case "New":
    default:
      return {
        label: "Nouvel Expert",
        badgeClass: "bg-gray-100 text-gray-800 border border-gray-200",
      };
  }
}

// Format YYYY-MM → short French month label
export function formatMonthLabel(yyyyMm: string): string {
  const [year, month] = yyyyMm.split("-");
  const date = new Date(Number(year), Number(month) - 1, 1);
  return new Intl.DateTimeFormat("fr-FR", { month: "short" }).format(date);
}

// Safe percentage — avoids division by zero
export function safePct(numerator: number, denominator: number): number {
  if (denominator === 0) return 0;
  return Math.round((numerator / denominator) * 100);
}

// ── Loader ────────────────────────────────────────────────────────────────────

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  const env = context.cloudflare.env;
  const userId = session.user.id;

  const defaultDashboard: DashboardResponse = {
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
  };

  const [dashboard, profileData] = await Promise.all([
    apiGet<DashboardResponse>(
      env,
      session.token,
      `/api/experts/${userId}/dashboard`,
    ).catch(() => defaultDashboard),
    apiGet<ProfileResponse>(
      env,
      session.token,
      `/api/experts/${userId}/profile`,
    ).catch(() => ({ composite_score: null, profile: null })),
  ]);

  captureEvent(env, `expert:${userId}`, "expert.analytics_viewed", {
    composite_score: dashboard.composite_score,
    quality_tier: dashboard.quality_tier,
  }).catch(() => {});

  return Response.json(
    {
      dashboard,
      profileScores: profileData.profile,
      userId,
    } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

// ── Score dimension definitions ───────────────────────────────────────────────

const SCORE_DIMENSIONS = [
  {
    key: "call_experience" as const,
    label: "Expérience d'appel",
    weight: "35%",
    driver: "Basé sur les évaluations post-appel de vos prospects.",
    tip: "Préparez chaque appel en consultant le contexte prospect dans la page Leads.",
  },
  {
    key: "trust" as const,
    label: "Confiance",
    weight: "20%",
    driver: "Basé sur la complétude de votre profil et vos signaux d'activité.",
    tip: "Complétez votre profil et connectez votre Google Calendar.",
  },
  {
    key: "satisfaction" as const,
    label: "Satisfaction",
    weight: "20%",
    driver: "Basé sur les évaluations soumises par vos prospects après appel.",
    tip: "Suivez chaque appel avec un récapitulatif envoyé au prospect.",
  },
  {
    key: "hire_rate" as const,
    label: "Taux de conversion",
    weight: "10%",
    driver: "Proportion de leads convertis en projets déclarés.",
    tip: "Déclarez vos conversions dans la page Leads après chaque mission gagnée.",
  },
  {
    key: "recency" as const,
    label: "Activité récente",
    weight: "15%",
    driver: "Mesure votre activité récente sur la plateforme.",
    tip: "Connectez-vous régulièrement et répondez rapidement aux nouveaux leads.",
  },
] as const;

// ── Sub-components ─────────────────────────────────────────────────────────────

function AnalyticsEmptyState() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Statistiques</h1>
        <p className="text-muted-foreground mt-1">
          Suivez votre score composite et vos métriques de conversion.
        </p>
      </div>
      <Card>
        <CardContent className="flex flex-col items-center justify-center py-16 text-center">
          <BarChart2 className="h-12 w-12 text-muted-foreground/40" />
          <h2 className="text-lg font-semibold mt-4">
            Vos statistiques apparaîtront ici après votre premier lead
          </h2>
          <p className="mt-2 max-w-md text-sm text-muted-foreground">
            Le score composite mesure votre expérience d&apos;appel (35%), votre confiance (20%),
            la satisfaction de vos prospects (20%), votre taux de conversion (10%)
            et votre activité récente (15%).
          </p>
          <Link to="/dashboard/settings" className="mt-6">
            <Button variant="outline">Compléter mon profil</Button>
          </Link>
        </CardContent>
      </Card>
    </div>
  );
}

function TrendArrow({
  current,
  previous,
}: {
  current: number;
  previous: number | null;
}) {
  if (previous === null) return <Minus className="h-4 w-4 text-muted-foreground" />;
  if (current > previous) return <TrendingUp className="h-4 w-4 text-green-600" />;
  if (current < previous) return <TrendingDown className="h-4 w-4 text-red-600" />;
  return <Minus className="h-4 w-4 text-muted-foreground" />;
}

// ── Component ─────────────────────────────────────────────────────────────────

export default function AnalyticsPage() {
  const { dashboard, profileScores } = useLoaderData<typeof loader>();

  const { composite_score, quality_tier, month_stats, monthly_history } = dashboard;
  const tierConfig = getTierConfig(quality_tier);

  // AC9: Empty state — new expert with no data
  const isNewExpert = composite_score === null && month_stats.leads_received === 0;
  if (isNewExpert) {
    return <AnalyticsEmptyState />;
  }

  // monthly_history is ASCENDING (oldest-first): index 0 = 5 months ago, index N-1 = current month
  // For trend comparison: previous month = index [length-2]
  const prevHistory =
    monthly_history.length >= 2
      ? monthly_history[monthly_history.length - 2]
      : null;

  // AC5: Bar chart data — already in chronological order (oldest→newest)
  const barData = monthly_history.map((h) => ({
    month: formatMonthLabel(h.month),
    Total: h.leads_received,
    Confirmés: h.leads_confirmed,
    Signalés: h.leads_flagged,
  }));

  // AC3: Radar chart data
  const radarData: Array<{
    axis: string;
    value: number;
    weight: string;
    available: boolean;
  }> = [
    {
      axis: "Expérience d'appel",
      value: profileScores?.call_experience ?? 0,
      weight: "35%",
      available: profileScores?.call_experience !== null && profileScores !== null,
    },
    {
      axis: "Confiance",
      value: profileScores?.trust ?? 0,
      weight: "20%",
      available: profileScores?.trust !== null && profileScores !== null,
    },
    {
      axis: "Satisfaction",
      value: profileScores?.satisfaction ?? 0,
      weight: "20%",
      available: profileScores?.satisfaction !== null && profileScores !== null,
    },
    {
      axis: "Taux de conversion",
      value: profileScores?.hire_rate ?? 0,
      weight: "10%",
      available: profileScores?.hire_rate !== null && profileScores !== null,
    },
    {
      axis: "Activité récente",
      value: profileScores?.recency ?? 0,
      weight: "15%",
      available: profileScores?.recency !== null && profileScores !== null,
    },
  ];

  // AC6: Conversion metrics
  const curr = month_stats;
  const leadsToBookings = safePct(curr.bookings_total, curr.leads_received);
  const bookingsToProjects = safePct(curr.conversions_declared, curr.bookings_total);
  const confirmationRate = safePct(curr.leads_confirmed, curr.leads_received);

  const prevLeadsToBookings = prevHistory
    ? safePct(prevHistory.bookings_total, prevHistory.leads_received)
    : null;
  const prevBookingsToProjects = prevHistory
    ? safePct(prevHistory.conversions_declared, prevHistory.bookings_total)
    : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Statistiques</h1>
        <p className="text-muted-foreground mt-1">
          Votre score composite et vos métriques de performance.
        </p>
      </div>

      {/* AC2: Score hero card */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Score composite</CardTitle>
          <CardDescription>
            Votre score de qualité sur la plateforme Callibrate
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-end gap-4">
            <span className="text-6xl font-bold tabular-nums">
              {composite_score !== null ? composite_score : "—"}
            </span>
            <span className="text-xl text-muted-foreground mb-2">/100</span>
          </div>
          <div className="mt-3">
            <Badge className={tierConfig.badgeClass}>{tierConfig.label}</Badge>
          </div>
        </CardContent>
      </Card>

      {/* AC3: Radar chart */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Répartition du score</CardTitle>
          <CardDescription>Les 5 composantes de votre score composite</CardDescription>
        </CardHeader>
        <CardContent>
          <ResponsiveContainer width="100%" height={300}>
            <RadarChart data={radarData}>
              <PolarGrid />
              <PolarAngleAxis
                dataKey="axis"
                tick={{ fontSize: 12 }}
              />
              <Radar
                name="Score"
                dataKey="value"
                stroke="#3b82f6"
                fill="#3b82f6"
                fillOpacity={0.3}
              />
            </RadarChart>
          </ResponsiveContainer>
          {/* Legend with weights */}
          <div className="flex flex-wrap gap-x-4 gap-y-1 mt-2 justify-center">
            {SCORE_DIMENSIONS.map((d) => (
              <span key={d.key} className="text-xs text-muted-foreground">
                {d.label} ({d.weight})
              </span>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* AC4: Per-component detail cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {SCORE_DIMENSIONS.map((dim) => {
          const value = profileScores?.[dim.key] ?? null;
          const isAvailable = value !== null;
          return (
            <Card
              key={dim.key}
              className={isAvailable ? undefined : "opacity-60"}
            >
              <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium">
                  {dim.label}
                  <span className="text-muted-foreground font-normal ml-1">
                    ({dim.weight})
                  </span>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {isAvailable ? (
                  <>
                    <p className="text-2xl font-bold tabular-nums">{value}/100</p>
                    <p className="text-xs text-muted-foreground">{dim.driver}</p>
                    <p className="text-xs text-blue-600">{dim.tip}</p>
                  </>
                ) : (
                  <p className="text-sm text-muted-foreground italic">
                    Données insuffisantes
                  </p>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>

      {/* AC6: Conversion metrics cards */}
      <div className="grid gap-4 grid-cols-2 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardDescription className="text-xs">Leads → Réservations</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{leadsToBookings}%</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-1">
              <TrendArrow current={leadsToBookings} previous={prevLeadsToBookings} />
              {prevLeadsToBookings !== null && (
                <span className="text-xs text-muted-foreground">
                  {prevLeadsToBookings}% mois préc.
                </span>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardDescription className="text-xs">Réservations → Projets</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{bookingsToProjects}%</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex items-center gap-1">
              <TrendArrow current={bookingsToProjects} previous={prevBookingsToProjects} />
              {prevBookingsToProjects !== null && (
                <span className="text-xs text-muted-foreground">
                  {prevBookingsToProjects}% mois préc.
                </span>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardDescription className="text-xs">Taux de confirmation</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{confirmationRate}%</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">
              Un taux élevé indique que vos critères sont bien calibrés.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-2">
            <CardDescription className="text-xs">Leads ce mois</CardDescription>
            <CardTitle className="text-3xl tabular-nums">{curr.leads_received}</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">Leads reçus ce mois</p>
          </CardContent>
        </Card>
      </div>

      {/* AC5: Monthly leads bar chart */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Évolution mensuelle des leads</CardTitle>
          <CardDescription>6 derniers mois</CardDescription>
        </CardHeader>
        <CardContent>
          {barData.length === 0 ? (
            <p className="text-sm text-muted-foreground py-8 text-center">
              Aucune donnée disponible.
            </p>
          ) : (
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={barData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                <YAxis allowDecimals={false} tick={{ fontSize: 12 }} />
                <Tooltip />
                <Legend />
                <Bar dataKey="Total" fill="#94a3b8" name="Total reçus" />
                <Bar dataKey="Confirmés" fill="#22c55e" name="Confirmés" />
                <Bar dataKey="Signalés" fill="#ef4444" name="Signalés" />
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      {/* AC8: Monthly summary — this month vs previous month */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Ce mois vs mois précédent</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-3">
            {[
              { label: "Leads reçus", curr: curr.leads_received, prev: prevHistory?.leads_received ?? null },
              { label: "Leads confirmés", curr: curr.leads_confirmed, prev: prevHistory?.leads_confirmed ?? null },
              { label: "Leads signalés", curr: curr.leads_flagged, prev: prevHistory?.leads_flagged ?? null },
            ].map((row) => (
              <div key={row.label} className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">{row.label}</span>
                <div className="flex items-center gap-2">
                  <span className="font-medium tabular-nums">{row.curr}</span>
                  <TrendArrow current={row.curr} previous={row.prev} />
                  {row.prev !== null && (
                    <span className="text-xs text-muted-foreground">({row.prev} préc.)</span>
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
