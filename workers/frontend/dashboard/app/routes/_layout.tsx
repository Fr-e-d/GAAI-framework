import { Outlet } from "react-router";
import type { LoaderFunctionArgs } from "react-router";
import { requireSession } from "~/lib/session.server";

export async function loader({ request, context }: LoaderFunctionArgs) {
  const { session, responseHeaders } = await requireSession(
    request,
    context.cloudflare.env,
  );
  return Response.json(
    { user: session.user },
    { headers: responseHeaders },
  );
}

export default function AuthLayout() {
  return <Outlet />;
}
