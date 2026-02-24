// ── BookingConfirmedWorkflow ──────────────────────────────────────────────────
// Triggered when a booking is confirmed. Dispatches an enriched expert
// notification (with prospect context) via the EMAIL_NOTIFICATIONS queue.
//
// Replaces: triggerN8nBookingConfirmed() from E06S06.
// Ref: DEC-59, E06S16.

import { WorkflowEntrypoint, WorkflowStep, WorkflowEvent } from 'cloudflare:workers';
import { Env } from '../types/env';

export type BookingConfirmedParams = {
  booking_id: string;
  expert_id: string;
  prospect_id: string;
  meeting_url: string;
  scheduled_at: string;
};

export class BookingConfirmedWorkflow extends WorkflowEntrypoint<Env, BookingConfirmedParams> {
  async run(event: WorkflowEvent<BookingConfirmedParams>, step: WorkflowStep): Promise<void> {
    const { booking_id, expert_id, prospect_id, meeting_url, scheduled_at } = event.payload;

    await step.do('dispatch-enriched-notification', async () => {
      await this.env.EMAIL_NOTIFICATIONS.send({
        type: 'booking.confirmed.enriched',
        booking_id,
        expert_id,
        prospect_id,
        meeting_url,
        scheduled_at,
      });
    });
  }
}
