import { Form, Link, NavLink, Outlet, redirect, useOutletContext } from "react-router";
import type { LoaderFunctionArgs } from "react-router";
import { useState } from "react";
import { requireSession } from "~/lib/session.server";
import type { SessionUser } from "~/lib/session.server";
import { apiGet } from "~/lib/api.server";
import { inferOnboardingStep } from "~/lib/onboarding";
import { Button } from "~/components/ui/button";
import { Separator } from "~/components/ui/separator";
import {
  LayoutDashboard,
  Users,
  Calendar,
  Clock,
  CreditCard,
  BarChart3,
  Settings,
  Menu,
  X,
  LogOut,
  Link2,
} from "lucide-react";

type LoaderData = { user: SessionUser };

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );

  // AC10: Check if onboarding is complete — display_name must be set
  const profile = await apiGet<{
    display_name: string | null;
    profile: Record<string, unknown> | null;
    preferences: Record<string, unknown> | null;
  }>(
    context.cloudflare.env,
    session.token,
    `/api/experts/${session.user.id}/profile`,
  ).catch(() => null);

  if (!profile?.display_name) {
    const step = inferOnboardingStep(profile);
    throw redirect(`/onboarding?step=${step}`, { headers: responseHeaders });
  }

  return Response.json(
    { user: session.user } satisfies LoaderData,
    { headers: responseHeaders },
  );
}

const NAV_LINKS = [
  { to: "/dashboard", label: "Vue d'ensemble", icon: LayoutDashboard, end: true },
  { to: "/dashboard/leads", label: "Leads", icon: Users, end: false },
  { to: "/dashboard/bookings", label: "Rendez-vous", icon: Calendar, end: false },
  { to: "/dashboard/availability", label: "Disponibilités", icon: Clock, end: false },
  { to: "/dashboard/billing", label: "Facturation", icon: CreditCard, end: false },
  { to: "/dashboard/analytics", label: "Statistiques", icon: BarChart3, end: false },
  { to: "/dashboard/settings", label: "Paramètres", icon: Settings, end: false },
  { to: "/dashboard/direct-link", label: "Lien direct", icon: Link2, end: false },
] as const;

export default function DashboardLayout() {
  const { user } = useOutletContext<LoaderData>();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  return (
    <div className="flex h-screen bg-background">
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-20 bg-black/50 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={[
          "fixed inset-y-0 left-0 z-30 flex w-64 flex-col bg-card border-r border-border",
          "transition-transform duration-200 ease-in-out",
          "lg:static lg:translate-x-0",
          sidebarOpen ? "translate-x-0" : "-translate-x-full",
        ].join(" ")}
      >
        {/* Logo */}
        <div className="flex h-16 items-center px-6 border-b border-border">
          <Link to="/dashboard" className="text-lg font-semibold text-foreground">
            Callibrate
          </Link>
        </div>

        {/* Nav */}
        <nav className="flex-1 overflow-y-auto px-4 py-4 space-y-1">
          {NAV_LINKS.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                [
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                  isActive
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                ].join(" ")
              }
              onClick={() => setSidebarOpen(false)}
            >
              <Icon className="h-4 w-4 shrink-0" />
              {label}
            </NavLink>
          ))}
        </nav>

        {/* User + logout */}
        <div className="border-t border-border p-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="h-8 w-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-medium text-primary">
              {user.email?.[0]?.toUpperCase() ?? "U"}
            </div>
            <div className="min-w-0">
              <p className="text-sm font-medium truncate">{user.email}</p>
            </div>
          </div>
          <Form action="/logout" method="post">
            <Button variant="ghost" size="sm" className="w-full justify-start gap-2">
              <LogOut className="h-4 w-4" />
              Se déconnecter
            </Button>
          </Form>
        </div>
      </aside>

      {/* Main */}
      <div className="flex flex-1 flex-col min-w-0 overflow-hidden">
        {/* Mobile header */}
        <header className="flex h-16 items-center border-b border-border px-4 lg:hidden">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setSidebarOpen(!sidebarOpen)}
            aria-label="Toggle navigation"
          >
            {sidebarOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </Button>
          <span className="ml-4 text-lg font-semibold">Callibrate</span>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-6">
          <Outlet context={{ user } satisfies LoaderData} />
        </main>
      </div>
    </div>
  );
}
