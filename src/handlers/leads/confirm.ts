import { Env } from '../../types/env';
import { AuthUser } from '../../middleware/auth';
import { createServiceClient } from '../../lib/supabase';

// POST /api/leads/:id/confirm
// Expert explicitly confirms a lead (marks as converted / accepted).
// AC5: validates ownership + status='pending', then sets status='confirmed'.
export async function handleConfirmLead(
  request: Request,
  env: Env,
  user: AuthUser,
  leadId: string,
): Promise<Response> {
  const supabase = createServiceClient(env);

  // Fetch lead for validation
  const { data: lead, error: fetchErr } = await supabase
    .from('leads')
    .select('id, expert_id, status')
    .eq('id', leadId)
    .single();

  if (fetchErr || !lead) {
    return new Response(JSON.stringify({ error: 'Lead not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Ownership check (AC5)
  if (lead.expert_id !== user.id) {
    return new Response(JSON.stringify({ error: 'Forbidden' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Status check — only pending leads can be confirmed (AC5)
  if (lead.status !== 'pending') {
    return new Response(JSON.stringify({ error: 'Lead status must be pending' }), {
      status: 422,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Update lead to confirmed (AC5)
  const { error: updateErr } = await supabase
    .from('leads')
    .update({ status: 'confirmed', confirmed_at: new Date().toISOString() })
    .eq('id', leadId);

  if (updateErr) {
    return new Response(JSON.stringify({ error: 'Failed to confirm lead' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
