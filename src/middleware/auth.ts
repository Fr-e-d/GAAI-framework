import { Env } from '../types/env';
import { createServiceClient } from '../lib/supabase';

export type AuthUser = {
  id: string;
  email: string | undefined;
};

export type AuthResult =
  | { user: AuthUser; response?: never }
  | { user?: never; response: Response };

const UNAUTHORIZED = (): Response =>
  new Response(JSON.stringify({ error: 'Unauthorized' }), {
    status: 401,
    headers: { 'Content-Type': 'application/json' },
  });

export async function authenticate(
  request: Request,
  env: Env
): Promise<AuthResult> {
  const authHeader = request.headers.get('Authorization');

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { response: UNAUTHORIZED() };
  }

  const token = authHeader.slice(7);

  const supabase = createServiceClient(env);
  const { data, error } = await supabase.auth.getUser(token);

  if (error || !data.user) {
    return { response: UNAUTHORIZED() };
  }

  return {
    user: {
      id: data.user.id,
      email: data.user.email,
    },
  };
}
