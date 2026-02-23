// email-notifications queue
export type EmailNotificationMessage =
  | { type: 'expert.registered'; expert_id: string; email: string; name: string }
  | { type: 'booking.confirmed'; booking_id: string; expert_id: string; prospect_id: string; meeting_url: string; scheduled_at: string }
  | { type: 'booking.confirmed.enriched'; booking_id: string; expert_id: string; prospect_id: string; meeting_url: string; scheduled_at: string }
  | { type: 'booking.completed'; booking_id: string; expert_id: string; prospect_id: string; scheduled_at: string }
  | { type: 'booking.cancelled'; booking_id: string }
  | { type: 'booking.rescheduled'; booking_id: string }
  | { type: 'booking.reminder_prospect'; booking_id: string }
  | { type: 'booking.reminder_expert'; booking_id: string }
  | { type: 'expert.billing.insufficient_balance'; expert_id: string }
  | { type: 'survey.call_experience'; booking_id: string; prospect_id: string }
  | { type: 'survey.project_satisfaction'; booking_id: string; prospect_id: string };

// lead-billing queue
export type LeadBillingMessage = {
  type: 'booking.created';
  booking_id: string;
  expert_id: string;
  prospect_id: string;
};

// score-computation queue
export type ScoreComputationMessage =
  | { type: 'feedback.call_experience'; expert_id: string }
  | { type: 'feedback.project_satisfaction'; expert_id: string }
  | { type: 'feedback.lead_evaluation'; expert_id: string };
