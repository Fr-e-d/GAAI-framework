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
