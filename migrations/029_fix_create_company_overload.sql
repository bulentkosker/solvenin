-- ============================================================
-- Migration 029: Fix create_company_for_user function overload
--
-- Bug: Two overloads with same param types in different order:
--   (text, text, text, uuid) from M011/M012
--   (uuid, text, text, text) from M014
-- PostgREST can't disambiguate named params → PGRST203 error
--
-- Fix: Drop the old overload, keep only M014 version
-- ============================================================

DROP FUNCTION IF EXISTS create_company_for_user(text, text, text, uuid);

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('029_fix_create_company_overload.sql',
  'Drop old create_company_for_user(text,text,text,uuid) overload — keep only (uuid,text,text,text) from M014')
ON CONFLICT (file_name) DO NOTHING;
