// email-notifications queue
export type EmailNotificationMessage =
  | { type: 'expert.registered'; expert_id: string; email: string; name: string }
  | { type: 'booking.confirmed'; booking_id: string; expert_id: string; prospect_id: string; meeting_url: string; scheduled_at: string }
  | { type: 'booking.completed'; booking_id: string; expert_id: string; prospect_id: string; scheduled_at: string };

// lead-billing queue
export type LeadBillingMessage = {
  type: 'booking.created';
  booking_id: string;
  expert_id: string;
  prospect_id: string;
};
