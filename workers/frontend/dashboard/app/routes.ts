import { type RouteConfig, index, layout, route } from "@react-router/dev/routes";

export default [
  // Unauthenticated routes
  route("login", "routes/login.tsx"),
  route("logout", "routes/logout.tsx"),
  route("signup", "routes/signup.tsx"),
  route("forgot-password", "routes/forgot-password.tsx"),

  // Authenticated routes — session guard applied by _layout.tsx
  layout("routes/_layout.tsx", [
    // Onboarding wizard — session required, no profile completeness check
    route("onboarding", "routes/onboarding.tsx"),

    // Dashboard shell at /dashboard/* — session + profile completeness required
    route("dashboard", "routes/_layout.dashboard.tsx", [
      index("routes/dashboard.tsx"),
      // Sub-routes added by E02S03–E02S08 (leads, bookings, billing, analytics, settings)
      route("settings", "routes/dashboard.settings.tsx"),
    ]),
  ]),
] satisfies RouteConfig;
