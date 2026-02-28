import type { ExpertAvailabilityRuleRow } from '../types/db';

export interface AvailabilityRules {
  working_hours: Record<string, [string, string]>; // e.g. { mon: ["09:00","18:00"], ... }
  buffer_minutes: number;
  min_notice_hours: number;
  booking_window_days: number;
}

export const DEFAULT_AVAILABILITY_RULES: AvailabilityRules = {
  working_hours: {
    mon: ['09:00', '18:00'],
    tue: ['09:00', '18:00'],
    wed: ['09:00', '18:00'],
    thu: ['09:00', '18:00'],
    fri: ['09:00', '18:00'],
  },
  buffer_minutes: 15,
  min_notice_hours: 4,
  booking_window_days: 14,
};

export function mergeRules(overrides?: Record<string, unknown> | null): AvailabilityRules {
  if (!overrides) return DEFAULT_AVAILABILITY_RULES;
  return {
    working_hours: (overrides.working_hours as Record<string, [string, string]>) ?? DEFAULT_AVAILABILITY_RULES.working_hours,
    buffer_minutes: typeof overrides.buffer_minutes === 'number' ? overrides.buffer_minutes : DEFAULT_AVAILABILITY_RULES.buffer_minutes,
    min_notice_hours: typeof overrides.min_notice_hours === 'number' ? overrides.min_notice_hours : DEFAULT_AVAILABILITY_RULES.min_notice_hours,
    booking_window_days: typeof overrides.booking_window_days === 'number' ? overrides.booking_window_days : DEFAULT_AVAILABILITY_RULES.booking_window_days,
  };
}

// Day abbreviation (0=Sun, 1=Mon, ..., 6=Sat) → rule key
const DAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;

function parseTimeToMinutes(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return (h ?? 0) * 60 + (m ?? 0);
}

function dateToUTCMidnight(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function overlaps(
  startA: Date, endA: Date,
  startB: Date, endB: Date
): boolean {
  return startA < endB && endA > startB;
}

export interface FreeSlot {
  start_at: string; // UTC ISO string
  end_at: string;   // UTC ISO string
}

export interface ComputeFreeSlotsParams {
  busyIntervals: Array<{ start: string; end: string }>; // from GCal freebusy
  heldBookings: Array<{ start_at: string; end_at: string }>; // from DB
  rules: AvailabilityRules;
  now: Date;
}

export function computeFreeSlots(params: ComputeFreeSlotsParams): FreeSlot[] {
  const { busyIntervals, heldBookings, rules, now } = params;
  const SLOT_DURATION_MS = 20 * 60 * 1000;
  const BUFFER_MS = rules.buffer_minutes * 60 * 1000;
  const MIN_NOTICE_MS = rules.min_notice_hours * 60 * 60 * 1000;

  // Combine all busy intervals (freebusy + held/confirmed bookings)
  const allBusy: Array<{ start: Date; end: Date }> = [
    ...busyIntervals.map(b => ({ start: new Date(b.start), end: new Date(b.end) })),
    ...heldBookings.map(b => ({ start: new Date(b.start_at), end: new Date(b.end_at) })),
  ];

  const earliestStart = new Date(now.getTime() + MIN_NOTICE_MS);
  const windowEnd = new Date(now.getTime() + rules.booking_window_days * 24 * 60 * 60 * 1000);

  const slots: FreeSlot[] = [];

  // Iterate each day in the window
  let dayStart = dateToUTCMidnight(now);
  const dayEndLimit = dateToUTCMidnight(windowEnd);
  dayEndLimit.setUTCDate(dayEndLimit.getUTCDate() + 1); // inclusive

  while (dayStart < dayEndLimit) {
    const dayKey = DAY_KEYS[dayStart.getUTCDay()];
    const workingHours = rules.working_hours[dayKey ?? ''];

    if (!workingHours) {
      // Weekend or non-working day — skip
      dayStart = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
      continue;
    }

    const [workStart, workEnd] = workingHours;
    const workStartMinutes = parseTimeToMinutes(workStart);
    const workEndMinutes = parseTimeToMinutes(workEnd);

    // Enumerate 20-min slots with buffer gap between them
    // Effective spacing = slot duration + buffer (buffer on each side → buffer between end of slot and start of next)
    const spacingMs = SLOT_DURATION_MS + BUFFER_MS;

    let slotStart = new Date(dayStart.getTime() + workStartMinutes * 60 * 1000);
    const dayWorkEnd = new Date(dayStart.getTime() + workEndMinutes * 60 * 1000);

    while (slotStart.getTime() + SLOT_DURATION_MS <= dayWorkEnd.getTime()) {
      const slotEnd = new Date(slotStart.getTime() + SLOT_DURATION_MS);

      // Filter: min notice
      if (slotStart >= earliestStart) {
        // Filter: not overlapping any busy interval (with buffer around busy)
        const slotStartWithBuffer = new Date(slotStart.getTime() - BUFFER_MS);
        const slotEndWithBuffer = new Date(slotEnd.getTime() + BUFFER_MS);

        const isBusy = allBusy.some(b =>
          overlaps(slotStartWithBuffer, slotEndWithBuffer, b.start, b.end)
        );

        if (!isBusy && slotStart < windowEnd) {
          slots.push({
            start_at: slotStart.toISOString(),
            end_at: slotEnd.toISOString(),
          });
        }
      }

      slotStart = new Date(slotStart.getTime() + spacingMs);
    }

    dayStart = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
  }

  return slots;
}

// Day abbreviation (0=Sun, 1=Mon, ..., 6=Sat) — same order as DAY_KEYS above
const DAY_KEYS_EXPORT = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;

/**
 * Convert a local time string (HH:MM or HH:MM:SS) to a UTC HH:MM string,
 * given the expert's IANA timezone.
 *
 * Strategy: interpret "2024-01-15T{time}:00" as UTC, then determine the offset
 * by comparing what that UTC moment looks like in the expert's timezone vs. UTC.
 * The reference date 2024-01-15 (Monday in January) minimises DST ambiguity for
 * the majority of winter-schedule experts; for full DST accuracy, a per-slot
 * approach would be needed (out of scope for MVP).
 */
function localTimeToUTC(timeStr: string, timezone: string): string {
  // Normalise to HH:MM
  const hhmm = timeStr.slice(0, 5);

  // Parse as a UTC Date at a fixed winter reference date to get a stable Date object
  const refDateUTC = new Date(`2024-01-15T${hhmm}:00Z`);

  // Obtain what that UTC instant looks like in the expert's timezone
  const localAsDisplayed = new Date(refDateUTC.toLocaleString('en-US', { timeZone: 'UTC' }));
  const expertLocal = new Date(refDateUTC.toLocaleString('en-US', { timeZone: timezone }));

  // Offset between UTC and the expert's timezone at this reference instant
  // offset > 0 means expert is ahead of UTC (e.g. UTC+1 → expert time is 1h later than UTC)
  const offsetMs = localAsDisplayed.getTime() - expertLocal.getTime();

  // The expert specifies times in local time. To convert local → UTC we ADD the negative offset.
  // local + offset = UTC  ⟹  UTC = local - (expert_local - UTC) = local + offsetMs
  const utcTime = new Date(refDateUTC.getTime() + offsetMs);

  const utcHH = String(utcTime.getUTCHours()).padStart(2, '0');
  const utcMM = String(utcTime.getUTCMinutes()).padStart(2, '0');
  return `${utcHH}:${utcMM}`;
}

/**
 * Convert DB availability rules (stored in expert local time) to working_hours
 * format in UTC, compatible with computeFreeSlots().
 *
 * @param rules - Rows from expert_availability_rules (may include inactive ones)
 * @param timezone - Expert's IANA timezone (e.g., 'Europe/Brussels')
 * @returns working_hours map keyed by day abbreviation (sun/mon/tue/wed/thu/fri/sat)
 */
export function expandRulesToWorkingHours(
  rules: ExpertAvailabilityRuleRow[],
  timezone: string,
): Record<string, [string, string]> {
  const result: Record<string, [string, string]> = {};

  // Validate timezone — fall back to UTC if invalid
  let tz = timezone;
  try {
    Intl.DateTimeFormat('en-GB', { timeZone: tz });
  } catch {
    console.warn(`expandRulesToWorkingHours: invalid timezone "${timezone}", falling back to UTC`);
    tz = 'UTC';
  }

  for (const rule of rules) {
    // Only active rules
    if (!rule.is_active) continue;

    const dayKey = DAY_KEYS_EXPORT[rule.day_of_week];
    if (!dayKey) continue;

    // First rule per day wins (overlap prevention means there shouldn't be conflicts)
    if (result[dayKey]) continue;

    const startUTC = localTimeToUTC(rule.start_time, tz);
    const endUTC = localTimeToUTC(rule.end_time, tz);

    result[dayKey] = [startUTC, endUTC];
  }

  return result;
}
