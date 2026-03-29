-- ============================================================
-- Fix: company_users RLS — allow members to see each other
-- Run in Supabase SQL Editor
-- ============================================================

-- Drop existing restrictive SELECT policy
DROP POLICY IF EXISTS "Users can view own company members" ON company_users;
DROP POLICY IF EXISTS "company_users_select" ON company_users;

-- Allow users to see ALL members of companies they belong to
CREATE POLICY "Users can view own company members"
  ON company_users FOR SELECT
  USING (
    company_id IN (
      SELECT company_id FROM company_users WHERE user_id = auth.uid()
    )
  );

-- Also fix profiles RLS — allow reading profiles of same-company users
DROP POLICY IF EXISTS "Users can view same company profiles" ON profiles;

CREATE POLICY "Users can view same company profiles"
  ON profiles FOR SELECT
  USING (
    id = auth.uid()
    OR id IN (
      SELECT cu2.user_id FROM company_users cu1
      JOIN company_users cu2 ON cu1.company_id = cu2.company_id
      WHERE cu1.user_id = auth.uid()
    )
  );
