import { z } from 'zod';
import { Env } from '../../types/env';
import { createSql } from '../../lib/db';
import { getAccessToken, gcalFreebusy, gcalPatchEvent, GcalApiError } from '../../lib/gcalClient';
import type { BookingRow, ExpertRow } from '../../types/db';

// AC5 (E08S04): Strict validation for reschedule — ISO-8601 datetimes, start < end, start in future
const RescheduleBodySchema = z.object({
  new_start_at: z.string().datetime({ message: 'new_start_at must be a valid ISO-8601 datetime' }),
  new_end_at: z.string().datetime({ message: 'new_end_at must be a valid ISO-8601 datetime' }),
}).superRefine((data, ctx) => {
  const start = new Date(data.new_start_at);
  const end = new Date(data.new_end_at);
  if (start >= end) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'new_start_at must be before new_end_at',
      path: ['new_start_at'],
    });
  }
  if (start <= new Date()) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: 'new_start_at must be in the future',
      path: ['new_start_at'],
    });
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleReschedule(
  request: Request,
  env: Env,
  bookingId: string
): Promise<Response> {
  const sql = createSql(env);

  const [booking] = await sql<Pick<BookingRow, 'id' | 'expert_id' | 'gcal_event_id' | 'meeting_url' | 'status' | 'start_at' | 'end_at'>[]>`
    SELECT id, expert_id, gcal_event_id, meeting_url, status, start_at, end_at FROM bookings WHERE id = ${bookingId}`;

  if (!booking) return json({ error: 'Not Found' }, 404);
  if (booking.status !== 'confirmed') return json({ error: 'Booking is not confirmed' }, 409);
  if (!booking.gcal_event_id) return json({ error: 'No GCal event to reschedule' }, 409);

  let rawBody: unknown;
  try {
    rawBody = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  // AC5 (E08S04): Strict Zod validation — invalid datetime, end ≤ start, or past start → 422
  const parseResult = RescheduleBodySchema.safeParse(rawBody);
  if (!parseResult.success) {
    return json({ error: 'Validation error', details: parseResult.error.issues }, 422);
  }

  const { new_start_at: newStart, new_end_at: newEnd } = parseResult.data;

  // DB conflict check (excluding self)
  const conflicts = await sql<{ id: string }[]>`
    SELECT id FROM bookings WHERE expert_id = ${booking.expert_id!}
    AND status = ANY(ARRAY['held', 'confirmed']) AND id != ${bookingId}
    AND start_at < ${newEnd} AND end_at > ${newStart}`;

  if (conflicts.length > 0) {
    return json({ error: 'slot_taken' }, 409);
  }

  // Fetch expert for GCal
  const [expert] = await sql<Pick<ExpertRow, 'gcal_email'>[]>`
    SELECT gcal_email FROM experts WHERE id = ${booking.expert_id!}`;

  if (!expert?.gcal_email) return json({ error: 'Expert not found or GCal not connected' }, 422);

  let accessToken: string;
  try {
    accessToken = await getAccessToken(booking.expert_id!, env);
  } catch {
    return json({ error: 'gcal_token_error' }, 502);
  }

  // GCal freebusy re-check on new slot
  try {
    const busy = await gcalFreebusy(accessToken, expert.gcal_email, newStart, newEnd, booking.expert_id!, env);
    const slotStart = new Date(newStart);
    const slotEnd = new Date(newEnd);
    const slotTaken = busy.some(b => new Date(b.start) < slotEnd && new Date(b.end) > slotStart);
    if (slotTaken) return json({ error: 'slot_taken' }, 409);
  } catch (err) {
    if (err instanceof GcalApiError) {
      return json({ error: 'gcal_error', status: err.gcalStatus, message: err.gcalMessage }, 502);
    }
    return json({ error: 'gcal_error' }, 502);
  }

  // Patch GCal event
  let gcalResult: { eventId: string; meetingUrl: string | null; htmlLink: string | null };
  try {
    gcalResult = await gcalPatchEvent(
      accessToken,
      expert.gcal_email,
      booking.gcal_event_id,
      {
        start: { dateTime: newStart, timeZone: 'UTC' },
        end: { dateTime: newEnd, timeZone: 'UTC' },
      },
      booking.expert_id!,
      env
    );
  } catch (err) {
    if (err instanceof GcalApiError) {
      return json({ error: 'gcal_error', status: err.gcalStatus, message: err.gcalMessage }, 502);
    }
    return json({ error: 'gcal_error' }, 502);
  }

  // Update booking
  await sql`UPDATE bookings SET start_at = ${newStart}, end_at = ${newEnd}, scheduled_at = ${newStart} WHERE id = ${bookingId}`;

  // Push notification
  await env.EMAIL_NOTIFICATIONS.send({
    type: 'booking.rescheduled',
    booking_id: bookingId,
  });

  return json({
    booking_id: bookingId,
    meeting_url: gcalResult.meetingUrl ?? booking.meeting_url,
    new_start_at: newStart,
    new_end_at: newEnd,
  });
}
