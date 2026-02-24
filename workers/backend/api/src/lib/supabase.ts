import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { Database } from '../types/database';
import { Env } from '../types/env';

export type TypedSupabaseClient = SupabaseClient<Database>;

export function createServiceClient(env: Env): TypedSupabaseClient {
  return createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
