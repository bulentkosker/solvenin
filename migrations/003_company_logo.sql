-- Migration: 003_company_logo
-- Description: Adds logo_url text column to companies (data-URL storage)
-- Backward Compatible: YES (nullable, no default needed)
-- Rollback:
--   ALTER TABLE companies DROP COLUMN IF EXISTS logo_url;

-- UP
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS logo_url text;

INSERT INTO migrations_log (file_name, notes)
VALUES ('003_company_logo.sql', 'Add logo_url to companies (base64 data URL)')
ON CONFLICT (file_name) DO NOTHING;
