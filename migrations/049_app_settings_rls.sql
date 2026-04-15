-- Migration 049: Fix app_settings RLS — authenticated read, no direct write
-- Root cause: existing "app_settings_admin_only" policy used USING(false),
-- which blocked ALL reads. sidebar.js + labels.html translate were failing
-- "API anahtarı bulunamadı" even though the row exists, because PostgREST
-- filtered the result to zero rows silently.

DROP POLICY IF EXISTS app_settings_admin_only ON app_settings;
DROP POLICY IF EXISTS app_settings_read ON app_settings;
DROP POLICY IF EXISTS app_settings_write ON app_settings;

-- Any authenticated user can read the anthropic_api_key row (needed for
-- AI chat / label translate / other client-side Claude calls)
CREATE POLICY app_settings_read ON app_settings
  FOR SELECT
  USING (auth.uid() IS NOT NULL AND key = 'anthropic_api_key');

-- All writes blocked at RLS level. sp_set_anthropic_key (SECURITY DEFINER)
-- is the only allowed write path and it gates on service_panel_users
-- role = 'superadmin'.
-- (No INSERT/UPDATE/DELETE policies → effectively blocked for authenticated)

INSERT INTO migrations_log (file_name, notes)
VALUES ('049_app_settings_rls.sql', 'Replace USING(false) ALL policy with authenticated SELECT on anthropic_api_key row only; writes only via sp_set_anthropic_key RPC')
ON CONFLICT (file_name) DO NOTHING;
