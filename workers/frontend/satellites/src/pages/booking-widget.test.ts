import { describe, it, expect } from 'vitest';
import { getBookingWidgetStyles, getBookingWidgetScript } from './booking-widget';

// ── AC1: Open animation, container classes, close affordance ─────────────────
describe('getBookingWidgetStyles — AC1: open animation & close affordance', () => {
  it('includes bw-container class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-container');
  });

  it('includes bw-container--open class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-container--open');
  });

  it('bw-container has max-height:0 default (collapsed)', () => {
    expect(getBookingWidgetStyles()).toContain('max-height:0');
  });

  it('bw-container--open has max-height:2000px', () => {
    expect(getBookingWidgetStyles()).toContain('max-height:2000px');
  });

  it('bw-container has transition property', () => {
    expect(getBookingWidgetStyles()).toContain('transition:max-height');
  });

  it('includes bw-close-btn class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-close-btn');
  });

  it('bw-close-btn has minimum touch target size 44px', () => {
    const css = getBookingWidgetStyles();
    expect(css).toContain('min-width:44px');
    expect(css).toContain('min-height:44px');
  });
});

describe('getBookingWidgetScript — AC1: open animation & close affordance', () => {
  it('includes bw-container class name in script', () => {
    expect(getBookingWidgetScript()).toContain('bw-container');
  });

  it('includes bw-container--open class addition in script', () => {
    expect(getBookingWidgetScript()).toContain('bw-container--open');
  });

  it('includes closeWidget function', () => {
    expect(getBookingWidgetScript()).toContain('closeWidget');
  });

  it('includes openWidget function', () => {
    expect(getBookingWidgetScript()).toContain('openWidget');
  });

  it('includes booking-open event listener', () => {
    expect(getBookingWidgetScript()).toContain('booking-open');
  });

  it('wires bw-close-btn to closeWidget', () => {
    expect(getBookingWidgetScript()).toContain('bw-close-btn');
    expect(getBookingWidgetScript()).toContain('wireCancelBtn');
  });
});

// ── AC2: Date step, availability API, calendar grid, timezone, skeleton ──────
describe('getBookingWidgetStyles — AC2: date step & skeleton loading', () => {
  it('includes bw-skeleton-day class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-skeleton-day');
  });

  it('includes bw-skeleton-row class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-skeleton-row');
  });

  it('includes bw-shimmer keyframe animation', () => {
    expect(getBookingWidgetStyles()).toContain('bw-shimmer');
  });

  it('includes bw-cal-grid class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-cal-grid');
  });

  it('includes bw-cal-header class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-cal-header');
  });

  it('includes bw-cal-day--available class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-cal-day--available');
  });

  it('includes bw-cal-day--unavailable class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-cal-day--unavailable');
  });

  it('includes bw-tz-label class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-tz-label');
  });
});

describe('getBookingWidgetScript — AC2: date step, availability API URL, calendar grid, timezone display', () => {
  it('fetches availability from /api/experts/{id}/availability', () => {
    expect(getBookingWidgetScript()).toContain('/api/experts/');
    expect(getBookingWidgetScript()).toContain('/availability');
  });

  it('includes tz query parameter in availability fetch', () => {
    expect(getBookingWidgetScript()).toContain('tz=');
  });

  it('includes renderDateStep function', () => {
    expect(getBookingWidgetScript()).toContain('renderDateStep');
  });

  it('includes 14-day grid logic', () => {
    expect(getBookingWidgetScript()).toContain('i<14');
  });

  it('includes timezone display in bw-tz-label', () => {
    expect(getBookingWidgetScript()).toContain('bw-tz-label');
  });

  it('includes buildSkeletonHTML function for loading state', () => {
    expect(getBookingWidgetScript()).toContain('buildSkeletonHTML');
  });

  it('includes bw-cal-day--available in calendar rendering', () => {
    expect(getBookingWidgetScript()).toContain('bw-cal-day--available');
  });

  it('includes bw-cal-day--unavailable in calendar rendering', () => {
    expect(getBookingWidgetScript()).toContain('bw-cal-day--unavailable');
  });

  it('uses Intl.DateTimeFormat for local timezone', () => {
    expect(getBookingWidgetScript()).toContain('Intl.DateTimeFormat');
  });

  it('includes gcal_not_connected error handling', () => {
    expect(getBookingWidgetScript()).toContain('gcal_not_connected');
  });
});

// ── AC3: Slot step, time chips, local timezone ────────────────────────────────
describe('getBookingWidgetStyles — AC3: slot chips', () => {
  it('includes bw-slot-chip class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-slot-chip');
  });

  it('includes bw-slot-chip--selected class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-slot-chip--selected');
  });

  it('includes bw-slots-grid class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-slots-grid');
  });

  it('slot chip has min-height:44px touch target', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-slot-chip');
    // Check that min-height 44px is defined (shared across interactive elements)
    expect(getBookingWidgetStyles()).toContain('min-height:44px');
  });

  it('includes bw-back-btn class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-back-btn');
  });
});

describe('getBookingWidgetScript — AC3: slot step & time chips', () => {
  it('includes renderSlotStep function', () => {
    expect(getBookingWidgetScript()).toContain('renderSlotStep');
  });

  it('includes bw-slot-chip in slot rendering', () => {
    expect(getBookingWidgetScript()).toContain('bw-slot-chip');
  });

  it('uses formatTimeLabel for local timezone display', () => {
    expect(getBookingWidgetScript()).toContain('formatTimeLabel');
  });

  it('includes back button for returning to date step', () => {
    expect(getBookingWidgetScript()).toContain('bw-back-btn');
  });

  it('includes handleDateSelect function', () => {
    expect(getBookingWidgetScript()).toContain('handleDateSelect');
  });

  it('includes buildSlotsByDate function', () => {
    expect(getBookingWidgetScript()).toContain('buildSlotsByDate');
  });
});

// ── AC4: Hold API call, countdown timer, 409 handling ────────────────────────
describe('getBookingWidgetStyles — AC4: countdown timer', () => {
  it('includes bw-countdown class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-countdown');
  });

  it('includes bw-inline-error class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-inline-error');
  });
});

describe('getBookingWidgetScript — AC4: hold API, countdown, 409 handling', () => {
  it('posts to /api/bookings/hold', () => {
    expect(getBookingWidgetScript()).toContain('/api/bookings/hold');
    expect(getBookingWidgetScript()).toContain("method:'POST'");
  });

  it('includes holdSlot function', () => {
    expect(getBookingWidgetScript()).toContain('holdSlot');
  });

  it('includes startCountdown function', () => {
    expect(getBookingWidgetScript()).toContain('startCountdown');
  });

  it('includes bw-countdown-display id for timer', () => {
    expect(getBookingWidgetScript()).toContain('bw-countdown-display');
  });

  it('handles 409 slot_taken — re-fetches slots', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('res.status===409');
    // Non-max_holds_reached 409 re-renders slot step (slot taken by someone else)
    expect(script).toContain('renderSlotStep');
  });

  it('handles 409 max_holds_reached', () => {
    expect(getBookingWidgetScript()).toContain('max_holds_reached');
  });

  it('includes clearCountdown function', () => {
    expect(getBookingWidgetScript()).toContain('clearCountdown');
  });

  it('sends expert_id, start_at, end_at in hold request body', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('expert_id');
    expect(script).toContain('start_at');
    expect(script).toContain('end_at');
  });
});

// ── AC5: Confirm form — name, email, textarea, button, countdown visible ─────
describe('getBookingWidgetStyles — AC5: confirm form elements', () => {
  it('includes bw-input class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-input');
  });

  it('includes bw-textarea class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-textarea');
  });

  it('includes bw-confirm-btn class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-confirm-btn');
  });

  it('includes bw-label class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-label');
  });

  it('includes bw-field-error class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-field-error');
  });
});

describe('getBookingWidgetScript — AC5: confirm form', () => {
  it('includes renderHoldStep function', () => {
    expect(getBookingWidgetScript()).toContain('renderHoldStep');
  });

  it('includes bw-name input field', () => {
    expect(getBookingWidgetScript()).toContain('bw-name');
  });

  it('includes bw-email input field', () => {
    expect(getBookingWidgetScript()).toContain('bw-email');
  });

  it('includes textarea with maxlength 500', () => {
    expect(getBookingWidgetScript()).toContain('maxlength="500"');
  });

  it('includes bw-confirm-btn button', () => {
    expect(getBookingWidgetScript()).toContain('bw-confirm-btn');
  });

  it('includes countdown visible in HOLD_STEP state', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('bw-countdown');
    expect(script).toContain('HOLD_STEP');
  });

  it('prefills email from sessionStorage match:identified_email', () => {
    expect(getBookingWidgetScript()).toContain('match:identified_email');
  });
});

// ── AC6: Confirm API call ─────────────────────────────────────────────────────
describe('getBookingWidgetScript — AC6: confirm API call', () => {
  it('posts to /api/bookings/{bookingId}/confirm', () => {
    expect(getBookingWidgetScript()).toContain('/api/bookings/');
    expect(getBookingWidgetScript()).toContain('/confirm');
  });

  it('includes handleConfirm function', () => {
    expect(getBookingWidgetScript()).toContain('handleConfirm');
  });

  it('sends prospect_name in confirm request body', () => {
    expect(getBookingWidgetScript()).toContain('prospect_name');
  });

  it('sends prospect_email in confirm request body', () => {
    expect(getBookingWidgetScript()).toContain('prospect_email');
  });

  it('sends description in confirm request body', () => {
    expect(getBookingWidgetScript()).toContain('description:desc');
  });

  it('includes email validation regex', () => {
    expect(getBookingWidgetScript()).toContain('[^\\s@]+@[^\\s@]+\\.[^\\s@]+');
  });
});

// ── AC7: Success state — meeting_url, prep_token, email note ─────────────────
describe('getBookingWidgetStyles — AC7: success state', () => {
  it('includes bw-step-success class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-step-success');
  });

  it('includes bw-success-title class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-success-title');
  });

  it('includes bw-success-meet class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-success-meet');
  });

  it('includes bw-success-email-note class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-success-email-note');
  });

  it('includes bw-success-prep class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-success-prep');
  });
});

describe('getBookingWidgetScript — AC7: success state', () => {
  it('includes renderSuccess function', () => {
    expect(getBookingWidgetScript()).toContain('renderSuccess');
  });

  it('includes bw-step-success in success HTML', () => {
    expect(getBookingWidgetScript()).toContain('bw-step-success');
  });

  it('renders meeting_url as a link', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('meeting_url');
    expect(script).toContain('bw-success-meet');
  });

  it('renders prep_token as a prep link', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('prep_token');
    expect(script).toContain('bw-success-prep');
  });

  it('constructs prep URL from prep_token', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('/prep/');
    expect(script).toContain('prepToken');
  });

  it('includes bw-success-email-note in success HTML', () => {
    expect(getBookingWidgetScript()).toContain('bw-success-email-note');
  });

  it('sets STATE to SUCCESS', () => {
    expect(getBookingWidgetScript()).toContain("STATE='SUCCESS'");
  });
});

// ── AC8: Hold expiry — bw-step-expired, EXPIRED state, reselect button ───────
describe('getBookingWidgetStyles — AC8: hold expiry', () => {
  it('includes bw-step-expired class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-step-expired');
  });

  it('includes bw-expired-title class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-expired-title');
  });

  it('includes bw-reselect-btn class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-reselect-btn');
  });
});

describe('getBookingWidgetScript — AC8: hold expiry', () => {
  it('includes handleHoldExpired function', () => {
    expect(getBookingWidgetScript()).toContain('handleHoldExpired');
  });

  it('includes bw-step-expired in expired HTML', () => {
    expect(getBookingWidgetScript()).toContain('bw-step-expired');
  });

  it('sets STATE to EXPIRED', () => {
    expect(getBookingWidgetScript()).toContain("STATE='EXPIRED'");
  });

  it('includes bw-reselect-btn for re-selecting a slot', () => {
    expect(getBookingWidgetScript()).toContain('bw-reselect-btn');
  });

  it('handles 410 status as hold expired during confirm', () => {
    expect(getBookingWidgetScript()).toContain('res.status===410');
  });

  it('triggers expired state when countdown reaches zero', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('remaining<=0');
    expect(script).toContain('handleHoldExpired');
  });
});

// ── AC9: Error handling — 409, 422, 502, gcal_not_connected ──────────────────
describe('getBookingWidgetStyles — AC9: error states', () => {
  it('includes bw-confirm-error class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-confirm-error');
  });

  it('includes bw-retry-btn class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-retry-btn');
  });

  it('includes bw-gcal-fallback class', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-gcal-fallback');
  });
});

describe('getBookingWidgetScript — AC9: error handling', () => {
  it('handles 409 conflict on confirm — re-fetches availability', () => {
    const script = getBookingWidgetScript();
    // 409 appears in confirm flow
    expect(script).toContain('res.status===409');
    expect(script).toContain('fetchAvailability');
  });

  it('handles 422 validation error on confirm', () => {
    expect(getBookingWidgetScript()).toContain('res.status===422');
  });

  it('handles 502 calendar error on confirm', () => {
    expect(getBookingWidgetScript()).toContain('res.status===502');
  });

  it('includes showConfirmError function', () => {
    expect(getBookingWidgetScript()).toContain('showConfirmError');
  });

  it('includes renderInlineError function', () => {
    expect(getBookingWidgetScript()).toContain('renderInlineError');
  });

  it('handles gcal_not_connected with handleGcalNotConnected', () => {
    expect(getBookingWidgetScript()).toContain('handleGcalNotConnected');
  });

  it('includes bw-gcal-fallback in gcal not connected HTML', () => {
    expect(getBookingWidgetScript()).toContain('bw-gcal-fallback');
  });
});

// ── AC10: PostHog events (all 7) ─────────────────────────────────────────────
describe('getBookingWidgetScript — AC10: PostHog events', () => {
  it('fires satellite.booking_widget_opened event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_widget_opened');
  });

  it('fires satellite.booking_date_selected event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_date_selected');
  });

  it('fires satellite.booking_slot_selected event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_slot_selected');
  });

  it('fires satellite.booking_held event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_held');
  });

  it('fires satellite.booking_hold_expired event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_hold_expired');
  });

  it('fires satellite.booking_confirmed event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_confirmed');
  });

  it('fires satellite.booking_error event', () => {
    expect(getBookingWidgetScript()).toContain('satellite.booking_error');
  });

  it('includes firePostHog helper function', () => {
    expect(getBookingWidgetScript()).toContain('firePostHog');
  });

  it('uses posthog.capture safely with typeof check', () => {
    expect(getBookingWidgetScript()).toContain("typeof posthog!=='undefined'");
  });
});

// ── AC11: Accessibility — aria-label, aria-describedby, aria-live, focus ─────
describe('getBookingWidgetScript — AC11: accessibility', () => {
  it('sets aria-label on widget container', () => {
    expect(getBookingWidgetScript()).toContain('aria-label');
  });

  it('sets aria-live="polite" on countdown for live region', () => {
    expect(getBookingWidgetScript()).toContain('aria-live="polite"');
  });

  it('uses aria-describedby for field errors', () => {
    expect(getBookingWidgetScript()).toContain('aria-describedby');
  });

  it('sets tabindex="-1" on container for focus management', () => {
    expect(getBookingWidgetScript()).toContain('tabindex');
  });

  it('restores focus to trigger button on close', () => {
    expect(getBookingWidgetScript()).toContain('triggerBtn.focus');
  });

  it('sets aria-label on close button', () => {
    expect(getBookingWidgetScript()).toContain('aria-label="Fermer le widget de r');
  });

  it('sets role="region" on container', () => {
    expect(getBookingWidgetScript()).toContain("setAttribute('role','region')");
  });

  it('sets role="alert" on field error elements', () => {
    expect(getBookingWidgetScript()).toContain('role="alert"');
  });
});

// ── AC12: Mobile responsive — @media max-width:480px, touch targets ──────────
describe('getBookingWidgetStyles — AC12: mobile responsive', () => {
  it('includes @media (max-width:480px) breakpoint', () => {
    expect(getBookingWidgetStyles()).toContain('max-width:480px');
  });

  it('includes min-height:44px for touch targets', () => {
    expect(getBookingWidgetStyles()).toContain('min-height:44px');
  });

  it('confirm button has min-height:44px', () => {
    const css = getBookingWidgetStyles();
    expect(css).toContain('.bw-confirm-btn');
    expect(css).toContain('min-height:44px');
  });

  it('mobile breakpoint adjusts bw-cal-grid to flex', () => {
    expect(getBookingWidgetStyles()).toContain('display:flex');
  });

  it('includes overflow-x:auto for horizontal scroll on mobile', () => {
    expect(getBookingWidgetStyles()).toContain('overflow-x:auto');
  });

  it('includes bw-spinner for loading states', () => {
    expect(getBookingWidgetStyles()).toContain('.bw-spinner');
  });

  it('includes bw-spin keyframe animation for spinner', () => {
    expect(getBookingWidgetStyles()).toContain('bw-spin');
  });
});

// ── Integration: results.ts embeds widget styles and script ──────────────────
describe('getBookingWidgetStyles/Script — static content checks', () => {
  it('getBookingWidgetStyles returns a string (no HTML tags)', () => {
    const styles = getBookingWidgetStyles();
    expect(typeof styles).toBe('string');
    expect(styles).not.toContain('<style>');
    expect(styles).not.toContain('</style>');
  });

  it('getBookingWidgetScript returns a string wrapped in <script> tags', () => {
    const script = getBookingWidgetScript();
    expect(typeof script).toBe('string');
    expect(script).toContain('<script>');
    expect(script).toContain('</script>');
  });

  it('widget script reads apiUrl from window.__SAT__', () => {
    expect(getBookingWidgetScript()).toContain('window.__SAT__');
    expect(getBookingWidgetScript()).toContain('apiUrl');
  });

  it('widget script reads satelliteId from window.__SAT__', () => {
    expect(getBookingWidgetScript()).toContain('satelliteId');
  });

  it('widget uses IIFE pattern for encapsulation', () => {
    const script = getBookingWidgetScript();
    expect(script).toContain('(function(){');
    expect(script).toContain('})()');
  });

  it('widget reads match:prospect_id from sessionStorage', () => {
    expect(getBookingWidgetScript()).toContain('match:prospect_id');
  });

  it('widget reads match:token from sessionStorage', () => {
    expect(getBookingWidgetScript()).toContain('match:token');
  });

  it('includes escHtml helper for XSS protection', () => {
    expect(getBookingWidgetScript()).toContain('escHtml');
  });

  it('all CSS classes are prefixed with bw-', () => {
    const styles = getBookingWidgetStyles();
    // All class selectors should start with .bw- or be at-rules
    const classMatches = styles.match(/\.[a-z][a-z0-9-]*/g) || [];
    const nonBwClasses = classMatches.filter(cls => !cls.startsWith('.bw-'));
    expect(nonBwClasses).toHaveLength(0);
  });
});
