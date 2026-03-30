-- ============================================================
-- Fix: company_users INSERT RLS — allow owner/admin to add users
-- Uses SECURITY DEFINER function to avoid self-referencing recursion
-- Run in Supabase SQL Editor
-- ============================================================

-- Function: returns company_ids where current user is owner or admin
CREATE OR REPLACE FUNCTION get_my_admin_company_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT ARRAY(
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  );
$$;

DROP POLICY IF EXISTS "Admins can insert company users" ON company_users;

CREATE POLICY "Admins can insert company users"
  ON company_users FOR INSERT
  WITH CHECK (
    company_id = ANY(get_my_admin_company_ids())
  );
