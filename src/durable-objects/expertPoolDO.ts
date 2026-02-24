// ExpertPoolDO — singleton write coordinator for expert pool (E06S25)
// AC1: extends DurableObject with fetch() and alarm() handlers
// AC2: batches profile change events with 5-second alarm window
// AC3: on alarm: batch D1 upsert + batch Vectorize embed/upsert
// AC4: singleton — always accessed via idFromName('expert-pool-coordinator')
// AC5: DO failure does NOT block HTTP response (callers use ctx.waitUntil)

import { DurableObject } from 'cloudflare:workers';
import { upsertToD1 } from '../lib/d1ExpertPool';
import { buildEmbeddingText } from '../lib/vectorize';
import type { Env } from '../types/env';
import type { ExpertPoolEntry } from '../lib/expertPool';
import type { Json } from '../types/database';

export interface ProfileEvent {
  id: string;
  profile: Record<string, unknown>;
  preferences: Record<string, unknown>;
  rate_min: number | null;
  rate_max: number | null;
  composite_score: number | null;
  total_leads: number;
  availability: string | null;
}

// Alarm window: batch writes after 5 seconds of last event
const ALARM_DELAY_MS = 5_000;

export class ExpertPoolDO extends DurableObject<Env> {
  // In-memory queue: keyed by expert_id — last write wins (idempotent for same expert)
  private pendingEvents = new Map<string, ProfileEvent>();

  // AC1: fetch() handler — receives profile change events from Workers
  async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    let event: ProfileEvent;
    try {
      event = (await request.json()) as ProfileEvent;
    } catch {
      return new Response('Invalid JSON', { status: 400 });
    }

    if (!event?.id) {
      return new Response('Missing id', { status: 400 });
    }

    // AC2: Queue event — last write wins for same expert
    this.pendingEvents.set(event.id, event);

    // AC2: Set 5-second alarm only if not already scheduled
    const currentAlarm = await this.ctx.storage.getAlarm();
    if (currentAlarm === null) {
      await this.ctx.storage.setAlarm(Date.now() + ALARM_DELAY_MS);
    }

    return new Response('accepted', { status: 202 });
  }

  // AC1: alarm() handler — processes batched events
  async alarm(): Promise<void> {
    if (this.pendingEvents.size === 0) return;

    const events = [...this.pendingEvents.values()];
    this.pendingEvents.clear();

    // AC3: Batch D1 upsert — AC6 (cron sync is safety net on DO failure)
    if (this.env.EXPERT_DB) {
      try {
        const entries: ExpertPoolEntry[] = events.map((e) => ({
          id: e.id,
          profile: e.profile as Json,
          preferences: e.preferences as Json,
          rate_min: e.rate_min,
          rate_max: e.rate_max,
          composite_score: e.composite_score,
          total_leads: e.total_leads,
        }));
        await upsertToD1(this.env.EXPERT_DB, entries);
      } catch (err) {
        console.error('ExpertPoolDO: D1 batch upsert failed', err);
        // Non-fatal: cron sync (*/5) acts as safety net (AC6)
      }
    }

    // AC3: Batch Vectorize embed/upsert
    if (this.env.AI && this.env.VECTORIZE) {
      for (const event of events) {
        try {
          const text = buildEmbeddingText({
            skills: (event.profile['skills'] ?? []) as string[],
            industries: (event.profile['industries'] ?? []) as string[],
            project_types: (event.profile['project_types'] ?? []) as string[],
            languages: (event.profile['languages'] ?? []) as string[],
          });

          const result = (await this.env.AI.run('@cf/baai/bge-base-en-v1.5', {
            text: [text],
          })) as { data: number[][] };

          const vector = result.data[0];
          if (!vector || vector.length === 0) {
            console.warn('ExpertPoolDO: empty embedding for expert', event.id);
            continue;
          }

          const metadata: Record<string, string | number | boolean> = {
            expert_id: event.id,
          };
          if (event.rate_min != null) metadata['rate_min'] = event.rate_min;
          if (event.rate_max != null) metadata['rate_max'] = event.rate_max;
          if (event.availability != null) metadata['availability'] = event.availability;

          await this.env.VECTORIZE.upsert([
            {
              id: event.id,
              values: vector,
              metadata,
            },
          ]);
        } catch (err) {
          console.error('ExpertPoolDO: Vectorize upsert failed for expert', event.id, err);
          // Non-fatal: continue with remaining experts
        }
      }
    }
  }
}

// Helper: notify ExpertPoolDO from request handlers (fire-and-forget via ctx.waitUntil)
// AC5: DO failure does NOT block the HTTP response
export function notifyExpertPoolDO(
  env: Env,
  ctx: ExecutionContext,
  event: ProfileEvent,
): void {
  if (!env.EXPERT_POOL_DO) return;
  ctx.waitUntil(
    (async () => {
      try {
        // AC4: singleton — always use idFromName('expert-pool-coordinator')
        const doId = env.EXPERT_POOL_DO!.idFromName('expert-pool-coordinator');
        const doStub = env.EXPERT_POOL_DO!.get(doId);
        await doStub.fetch('https://do.internal/event', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(event),
        });
      } catch (err) {
        console.error('ExpertPoolDO: notification failed', err);
        // Non-fatal: cron sync (*/5) acts as safety net (AC6)
      }
    })(),
  );
}
