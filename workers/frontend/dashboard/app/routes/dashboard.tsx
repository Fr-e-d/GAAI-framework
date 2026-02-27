import { useOutletContext, useSearchParams } from "react-router";
import { useEffect } from "react";
import { toast } from "sonner";
import type { SessionUser } from "~/lib/session.server";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "~/components/ui/card";

// No additional loader needed — auth is handled by parent _layout.dashboard.tsx
// If additional data is needed later, add a loader here.

export default function DashboardIndex() {
  const { user } = useOutletContext<{ user: SessionUser }>();
  const [searchParams] = useSearchParams();

  // AC9: Show welcome toast after onboarding completion
  useEffect(() => {
    if (searchParams.get("welcome") === "1") {
      toast.success("Votre profil est prêt ! Vous commencerez à recevoir des leads qualifiés.");
    }
  }, [searchParams]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Bienvenue</h1>
        <p className="text-muted-foreground mt-1">
          {user.email}
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {/* Placeholder metric cards */}
        {[
          { title: "Leads reçus", value: "—", description: "Ce mois" },
          { title: "Rendez-vous", value: "—", description: "À venir" },
          { title: "Crédits", value: "—", description: "Solde" },
          { title: "Conversions", value: "—", description: "Déclarées" },
        ].map((card) => (
          <Card key={card.title}>
            <CardHeader className="pb-2">
              <CardDescription>{card.title}</CardDescription>
              <CardTitle className="text-3xl">{card.value}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-xs text-muted-foreground">{card.description}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Activité récente</CardTitle>
          <CardDescription>Vos dernières interactions sur la plateforme</CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Aucune activité récente pour le moment.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
