import { Env } from '../types/env';
import { createSql } from '../lib/db';
import { captureEvent } from '../lib/posthog';

// ── Types ─────────────────────────────────────────────────────────────────────

interface AbandonedProject {
  id: string;
}

// ── AC1–AC3: Purge abandoned funnel data ─────────────────────────────────────

export async function purgeAbandonedFunnels(env: Env): Promise<void> {
  const sql = createSql(env);
  try {
    // Find prospect_projects for prospects with no email, created >24h ago,
    // with at least one non-null field to purge (freetext, requirements, extraction_confidence)
    const projects = await sql<AbandonedProject[]>`
      SELECT pp.id
      FROM prospect_projects pp
      JOIN prospects p ON p.id = pp.prospect_id
      WHERE p.email IS NULL
        AND p.created_at < NOW() - INTERVAL '24 hours'
        AND (
          pp.freetext IS NOT NULL
          OR pp.requirements IS NOT NULL
          OR pp.extraction_confidence IS NOT NULL
        )
    `;

    // If no abandoned projects, return early — no audit log row
    if (projects.length === 0) {
      return;
    }

    const projectIds = projects.map(p => p.id);
    const count = projectIds.length;

    // Soft-purge: null out PII fields but keep the row skeleton
    await sql`
      UPDATE prospect_projects
      SET freetext = NULL,
          requirements = NULL,
          extraction_confidence = NULL
      WHERE id = ANY(${sql.array(projectIds)})
    `;

    // Delete associated matches (no longer useful without project data)
    await sql`
      DELETE FROM matches
      WHERE project_id = ANY(${sql.array(projectIds)})
    `;

    // Insert audit log row
    await sql`
      INSERT INTO data_purge_log (purge_type, records_affected)
      VALUES ('abandoned_funnel', ${count})
    `;

    // Fire PostHog event (fire-and-forget — errors silently swallowed by captureEvent)
    captureEvent(env.POSTHOG_API_KEY, {
      distinctId: 'system',
      event: 'system.abandoned_funnel_purged',
      properties: { count },
    }).catch(() => {});

    console.log(`purgeAbandonedFunnels: purged ${count} abandoned project(s)`);
  } finally {
    await sql.end();
  }
}

// ── AC2: Cleanup expired OTP KV keys ─────────────────────────────────────────

export async function cleanupOtpKvKeys(env: Env): Promise<void> {
  const sql = createSql(env);
  try {
    const listed = await env.SESSIONS.list({ prefix: 'otp:' });

    if (!listed.list_complete) {
      console.warn('cleanupOtpKvKeys: list_complete=false — some OTP keys may not be scanned');
    }

    const nowSec = Math.floor(Date.now() / 1000);
    const expiredKeys = listed.keys.filter(
      k => typeof k.expiration === 'number' && k.expiration < nowSec
    );

    // Delete expired keys
    for (const k of expiredKeys) {
      await env.SESSIONS.delete(k.name);
    }

    const count = expiredKeys.length;

    // Always insert audit log row (even when count=0)
    await sql`
      INSERT INTO data_purge_log (purge_type, records_affected)
      VALUES ('otp_kv_cleanup', ${count})
    `;

    if (count > 0) {
      console.log(`cleanupOtpKvKeys: deleted ${count} expired OTP key(s)`);
    }
  } finally {
    await sql.end();
  }
}

// ── Top-level handler ─────────────────────────────────────────────────────────

export async function handleGdprCron(env: Env): Promise<void> {
  try {
    await purgeAbandonedFunnels(env);
  } catch (err) {
    console.error('handleGdprCron: purgeAbandonedFunnels failed', err);
  }

  try {
    await cleanupOtpKvKeys(env);
  } catch (err) {
    console.error('handleGdprCron: cleanupOtpKvKeys failed', err);
  }
}
