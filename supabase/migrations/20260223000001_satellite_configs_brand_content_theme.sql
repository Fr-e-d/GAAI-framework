-- E06S13: satellite_configs schema extension — brand, content & theme columns
-- Adds visual identity, SEO content, and go-live gating columns for multi-tenant satellite Worker (E06S14)

ALTER TABLE satellite_configs
  ADD COLUMN theme           JSONB,
  ADD COLUMN brand           JSONB,
  ADD COLUMN content         JSONB,
  ADD COLUMN structured_data JSONB,
  ADD COLUMN active          BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN updated_at      TIMESTAMPTZ DEFAULT now();

-- Document canonical JSONB shapes for developer reference
COMMENT ON COLUMN satellite_configs.theme IS 'Design tokens: {primary, accent, font, radius, logo_url}';
COMMENT ON COLUMN satellite_configs.brand IS 'Brand identity: {name, tagline}';
COMMENT ON COLUMN satellite_configs.content IS 'SEO/page content: {meta_title, meta_description, hero_headline, hero_sub, value_props[], vertical_label, vertical_description}';
COMMENT ON COLUMN satellite_configs.structured_data IS 'JSON-LD schema markup: {@context, @type, name, description, url, areaServed}';
COMMENT ON COLUMN satellite_configs.active IS 'Go-live gate — Worker returns 404 redirect for inactive satellites';

-- Seed: update existing 'default' row with placeholder values for new columns
UPDATE satellite_configs
SET
  theme = '{"primary": "#4F46E5", "accent": "#818CF8", "font": "Inter, sans-serif", "radius": "0.5rem", "logo_url": null}'::jsonb,
  brand = '{"name": "Callibrate", "tagline": "The AI expert your trusted peer would have recommended."}'::jsonb,
  content = '{"meta_title": "Find a pre-qualified AI expert | Callibrate", "meta_description": "Describe your AI project. Get matched with pre-qualified experts in minutes.", "hero_headline": "The AI expert your trusted peer would have recommended.", "hero_sub": "Describe your need. We find the expert who fits — budget, stage, sector.", "value_props": ["Pre-qualified on your real criteria", "Call booked directly in their calendar", "Results in under 2 minutes"], "vertical_label": "AI experts", "vertical_description": "Automate your business workflows with a pre-qualified AI expert."}'::jsonb,
  structured_data = '{"@context": "https://schema.org", "@type": "ProfessionalService", "name": "Callibrate", "description": "Matching platform between businesses and pre-qualified AI experts.", "url": "https://callibrate.ai", "areaServed": "Worldwide"}'::jsonb,
  active = false,
  updated_at = now()
WHERE id = 'default';
