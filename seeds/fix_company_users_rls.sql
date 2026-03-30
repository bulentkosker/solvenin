-- ============================================================
-- Fix: company_users RLS — allow members to see each other
-- Self-referencing RLS causes recursion; bypass with SECURITY DEFINER
-- Run in Supabase SQL Editor
-- ============================================================

CREATE OR REPLACE FUNCTION get_my_company_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT ARRAY(
    SELECT company_id FROM company_users WHERE user_id = auth.uid()
  );
$$;

DROP POLICY IF EXISTS "Users can view own company members" ON company_users;

CREATE POLICY "Users can view own company members"
  ON company_users FOR SELECT
  USING (company_id = ANY(get_my_company_ids()));
