-- ============================================================
-- Fix: company_users RLS — allow members to see each other
-- Run in Supabase SQL Editor
-- ============================================================

-- Step 1: Create a SECURITY DEFINER function to avoid
-- self-referencing RLS circular dependency.
-- This function runs with the definer's privileges,
-- bypassing RLS on company_users for the subquery.
CREATE OR REPLACE FUNCTION get_my_company_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT company_id FROM company_users WHERE user_id = auth.uid();
$$;

-- Step 2: Fix company_users SELECT policy
DROP POLICY IF EXISTS "Users can view own company members" ON company_users;
DROP POLICY IF EXISTS "company_users_select" ON company_users;

CREATE POLICY "Users can view own company members"
  ON company_users FOR SELECT
  USING (
    company_id IN (SELECT get_my_company_ids())
  );

-- Step 3: Fix profiles RLS — allow reading profiles of same-company users
DROP POLICY IF EXISTS "Users can view same company profiles" ON profiles;

CREATE POLICY "Users can view same company profiles"
  ON profiles FOR SELECT
  USING (
    id = auth.uid()
    OR id IN (
      SELECT cu.user_id FROM company_users cu
      WHERE cu.company_id IN (SELECT get_my_company_ids())
    )
  );
