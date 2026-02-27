import { type RouteConfig, index, layout, route } from "@react-router/dev/routes";

export default [
  // Unauthenticated routes
  route("login", "routes/login.tsx"),
  route("logout", "routes/logout.tsx"),

  // Authenticated routes — auth guard applied by _layout.tsx
  layout("routes/_layout.tsx", [
    // Dashboard shell at /dashboard/*
    route("dashboard", "routes/_layout.dashboard.tsx", [
      index("routes/dashboard.tsx"),
      // Sub-routes added by E02S02–E02S08 (leads, bookings, billing, analytics, settings)
    ]),
  ]),
] satisfies RouteConfig;
