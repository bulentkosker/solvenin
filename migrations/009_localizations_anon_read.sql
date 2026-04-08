-- Migration: 009_localizations_anon_read
-- Description: Open SELECT on localizations + tax templates to anon role
-- Backward Compatible: YES (loosens an existing restriction; reference data only)
-- Rollback:
--   DROP POLICY localizations_public_read ON localizations;
--   CREATE POLICY localizations_public_read ON localizations
--     FOR SELECT TO authenticated USING (true);
--   ...same for the tax tables

-- The previous localizations_public_read policy was scoped to
-- "TO authenticated", which silently returned an empty result for any
-- request made before the supabase-js client had a hydrated session.
-- This made the "New Company" modal in sidebar.js stuck on its
-- "Loading..." placeholder when the user clicked it during the first
-- few hundred ms after a page load.
--
-- localizations / localization_tax_rates / tax_rates_templates are all
-- reference data — country list, default language, standard tax rate
-- templates per country. None of it is private. Exposing it to anon
-- as well as authenticated removes the race condition entirely.

DROP POLICY IF EXISTS localizations_public_read ON localizations;
CREATE POLICY localizations_public_read ON localizations
  FOR SELECT
  TO authenticated, anon
  USING (true);

ALTER TABLE localization_tax_rates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS localization_tax_rates_public_read ON localization_tax_rates;
CREATE POLICY localization_tax_rates_public_read ON localization_tax_rates
  FOR SELECT
  TO authenticated, anon
  USING (true);

ALTER TABLE tax_rates_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tax_rates_templates_public_read ON tax_rates_templates;
CREATE POLICY tax_rates_templates_public_read ON tax_rates_templates
  FOR SELECT
  TO authenticated, anon
  USING (true);

INSERT INTO migrations_log (file_name, notes)
VALUES ('009_localizations_anon_read.sql', 'Open localizations + tax templates SELECT to anon role to fix new-company modal "Loading..." race')
ON CONFLICT (file_name) DO NOTHING;
