// ── BookingCompletedWorkflow ──────────────────────────────────────────────────
// Triggered when a booking is completed. Waits 7 days then dispatches a
// call experience survey email. Waits 38 more days then dispatches a
// project satisfaction survey email. Both via EMAIL_NOTIFICATIONS queue.
//
// Sleep acceleration for staging via SURVEY_DELAY_7D_MS / SURVEY_DELAY_38D_MS
// secrets (absent in production → real durations used).
//
// Replaces: triggerN8nBookingCompleted() from E06S06.
// Ref: DEC-59, E06S16.

import { WorkflowEntrypoint, WorkflowStep, WorkflowEvent } from 'cloudflare:workers';
import { Env } from '../types/env';

export type BookingCompletedParams = {
  booking_id: string;
  expert_id: string;
  prospect_id: string;
  scheduled_at: string;
};

export class BookingCompletedWorkflow extends WorkflowEntrypoint<Env, BookingCompletedParams> {
  async run(event: WorkflowEvent<BookingCompletedParams>, step: WorkflowStep): Promise<void> {
    const { booking_id, prospect_id } = event.payload;

    // AC8: Use accelerated delays in staging (secrets absent → real durations)
    const delay7d = parseInt(this.env.SURVEY_DELAY_7D_MS ?? String(7 * 24 * 60 * 60 * 1000));
    const delay38d = parseInt(this.env.SURVEY_DELAY_38D_MS ?? String(38 * 24 * 60 * 60 * 1000));

    await step.sleep('wait-7-days', delay7d);

    await step.do('dispatch-call-experience-survey', async () => {
      await this.env.EMAIL_NOTIFICATIONS.send({
        type: 'survey.call_experience',
        booking_id,
        prospect_id,
      });
    });

    await step.sleep('wait-38-days', delay38d);

    await step.do('dispatch-project-satisfaction-survey', async () => {
      await this.env.EMAIL_NOTIFICATIONS.send({
        type: 'survey.project_satisfaction',
        booking_id,
        prospect_id,
      });
    });
  }
}
