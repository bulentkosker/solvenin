-- Migration: 007_companies_insert_policy
-- Description: Fix RLS so authenticated users can create new companies
-- Backward Compatible: YES (loosens an existing restriction)
-- Rollback:
--   DROP POLICY IF EXISTS companies_insert ON companies;
--   DROP POLICY IF EXISTS companies_update ON companies;
--   DROP POLICY IF EXISTS companies_delete ON companies;
--   CREATE POLICY companies_modify ON companies
--     FOR ALL
--     USING (deleted_at IS NULL AND id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid()))
--     WITH CHECK (id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid()));
--
-- The previous companies_modify policy (added in 004_company_soft_delete)
-- was FOR ALL with WITH CHECK requiring the new row's id to already exist
-- in company_users — impossible for INSERT (chicken-and-egg). New users
-- couldn't create their first company at all.
--
-- Fix: split FOR ALL into per-command policies. INSERT becomes WITH CHECK
-- (true) for any authenticated user. The follow-up company_users INSERT
-- happens immediately in the app's "create company" flow, and without
-- that link the new row is invisible via SELECT (companies_visible) so
-- the user can't actually do anything with an unattached company.

-- UP
DROP POLICY IF EXISTS companies_modify ON companies;

DROP POLICY IF EXISTS companies_insert ON companies;
CREATE POLICY companies_insert ON companies
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS companies_update ON companies;
CREATE POLICY companies_update ON companies
  FOR UPDATE
  USING (
    deleted_at IS NULL
    AND id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  )
  WITH CHECK (
    id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS companies_delete ON companies;
CREATE POLICY companies_delete ON companies
  FOR DELETE
  USING (
    id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  );

INSERT INTO migrations_log (file_name, notes)
VALUES ('007_companies_insert_policy.sql', 'Split companies FOR ALL into per-command policies — fixes new-company creation')
ON CONFLICT (file_name) DO NOTHING;
