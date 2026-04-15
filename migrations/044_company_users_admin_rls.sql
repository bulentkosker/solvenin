-- Migration 044: Allow owner/admin to UPDATE/DELETE company_users rows in their companies
-- Bug: existing policies restrict UPDATE/DELETE to user_id = auth.uid() only,
-- which blocks suspend/unsuspend and remove-user actions from admins.

-- Drop self-only policies
DROP POLICY IF EXISTS company_users_update ON company_users;
DROP POLICY IF EXISTS company_users_delete ON company_users;

-- UPDATE: admin of the company OR the user themselves
CREATE POLICY company_users_update ON company_users
  FOR UPDATE
  USING (
    user_id = auth.uid()
    OR company_id = ANY (get_my_admin_company_ids())
  )
  WITH CHECK (
    user_id = auth.uid()
    OR company_id = ANY (get_my_admin_company_ids())
  );

-- DELETE: admin of the company OR the user themselves
CREATE POLICY company_users_delete ON company_users
  FOR DELETE
  USING (
    user_id = auth.uid()
    OR company_id = ANY (get_my_admin_company_ids())
  );

INSERT INTO migrations_log (file_name, notes)
VALUES ('044_company_users_admin_rls.sql',
  'Admins can UPDATE/DELETE company_users rows in their companies (fixes suspend + remove user)')
ON CONFLICT (file_name) DO NOTHING;
