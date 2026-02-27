/**
 * Shared onboarding step inference utility.
 * Determines which wizard step to redirect to based on profile completeness.
 */

type PartialExpertProfile = {
  display_name?: string | null;
  profile?: Record<string, unknown> | null;
  preferences?: Record<string, unknown> | null;
} | null;

export function inferOnboardingStep(profile: PartialExpertProfile): number {
  if (!profile || !profile.display_name) return 1;
  const p = profile.profile as Record<string, unknown> | null;
  if (!p?.skills || (p.skills as unknown[]).length === 0) return 2;
  const prefs = profile.preferences as Record<string, unknown> | null;
  if (!prefs?.career_stage) return 3;
  return 4;
}
