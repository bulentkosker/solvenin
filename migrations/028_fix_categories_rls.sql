-- ============================================================
-- Migration 028: Fix categories RLS — use SECURITY DEFINER function
--
-- Bug: INSERT policy used EXISTS (SELECT FROM company_users ...)
-- which triggers RLS recursion since company_users also has RLS.
-- Fix: Use get_my_company_ids() SECURITY DEFINER function
-- which bypasses RLS on company_users.
-- Also adds deleted_at IS NULL to SELECT policy (from M018).
-- ============================================================

DROP POLICY IF EXISTS categories_select ON categories;
DROP POLICY IF EXISTS categories_insert ON categories;
DROP POLICY IF EXISTS categories_update ON categories;
DROP POLICY IF EXISTS categories_delete ON categories;
DROP POLICY IF EXISTS categories_company_read ON categories;

CREATE POLICY categories_select ON categories
  FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);

CREATE POLICY categories_insert ON categories
  FOR INSERT WITH CHECK (company_id = ANY(get_my_company_ids()));

CREATE POLICY categories_update ON categories
  FOR UPDATE USING (company_id = ANY(get_my_company_ids()));

CREATE POLICY categories_delete ON categories
  FOR DELETE USING (company_id = ANY(get_my_company_ids()));

INSERT INTO migrations_log (file_name, notes)
VALUES ('028_fix_categories_rls.sql',
  'Fix categories RLS: EXISTS subquery → get_my_company_ids() SECURITY DEFINER to prevent recursion')
ON CONFLICT (file_name) DO NOTHING;
