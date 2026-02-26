-- Add utm_content column to prospects table for per-content-piece attribution
-- Complements existing utm_source + utm_campaign tracking
ALTER TABLE prospects ADD COLUMN utm_content TEXT;
