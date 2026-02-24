export interface SatelliteTheme {
  primary: string;
  accent: string;
  font: string;
  radius: string;
  logo_url: string | null;
}

export interface SatelliteBrand {
  name: string;
  tagline: string;
}

export interface SatelliteContent {
  meta_title: string;
  meta_description: string;
  hero_headline: string;
  hero_sub: string;
  value_props: string[];
  vertical_label?: string;
  vertical_description?: string;
}

export interface SatelliteConfig {
  id: string;
  domain: string;
  label: string | null;
  vertical: string | null;
  active: boolean;
  theme: SatelliteTheme | null;
  brand: SatelliteBrand | null;
  content: SatelliteContent | null;
  structured_data: Record<string, unknown> | null;
  quiz_schema: unknown;
  matching_weights: unknown;
  tracking_enabled: boolean;
}
