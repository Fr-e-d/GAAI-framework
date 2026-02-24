-- E06S37: Outcome-based expert profiles + extraction enhancement (DEC-81)
-- Adds outcome_tags TEXT[] to experts table.
-- Updates merge_expert_profile RPC to accept the new column.

-- AC1: add column
ALTER TABLE experts
  ADD COLUMN IF NOT EXISTS outcome_tags TEXT[] NOT NULL DEFAULT '{}';

-- Update merge_expert_profile to support outcome_tags (AC3)
CREATE OR REPLACE FUNCTION public.merge_expert_profile(
  p_id                     uuid,
  p_display_name           text    DEFAULT NULL,
  p_headline               text    DEFAULT NULL,
  p_bio                    text    DEFAULT NULL,
  p_rate_min               numeric DEFAULT NULL,
  p_rate_max               numeric DEFAULT NULL,
  p_availability           text    DEFAULT NULL,
  p_profile                jsonb   DEFAULT NULL,
  p_preferences            jsonb   DEFAULT NULL,
  p_admissibility_criteria jsonb   DEFAULT NULL,
  p_outcome_tags           text[]  DEFAULT NULL
)
RETURNS SETOF experts
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.experts
  SET
    display_name           = COALESCE(p_display_name, display_name),
    headline               = COALESCE(p_headline, headline),
    bio                    = COALESCE(p_bio, bio),
    rate_min               = COALESCE(p_rate_min, rate_min),
    rate_max               = COALESCE(p_rate_max, rate_max),
    availability           = COALESCE(p_availability, availability),
    profile                = CASE WHEN p_profile IS NOT NULL
                               THEN COALESCE(profile, '{}'::jsonb) || p_profile
                               ELSE profile END,
    preferences            = CASE WHEN p_preferences IS NOT NULL
                               THEN COALESCE(preferences, '{}'::jsonb) || p_preferences
                               ELSE preferences END,
    admissibility_criteria = CASE WHEN p_admissibility_criteria IS NOT NULL
                               THEN p_admissibility_criteria
                               ELSE admissibility_criteria END,
    outcome_tags           = CASE WHEN p_outcome_tags IS NOT NULL
                               THEN p_outcome_tags
                               ELSE outcome_tags END
  WHERE id = p_id;

  RETURN QUERY SELECT * FROM public.experts WHERE id = p_id;
END;
$$;
