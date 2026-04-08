-- ===== COMPANY SOFT DELETE + AUDIT + RECOVERY =====
-- 2026-04-08
-- Real companies → soft delete → 30-day trash → permanent delete
-- Demo companies → instant permanent delete (still audited)
-- All actions logged to company_audit_log

-- ============================================================================
-- 1. SCHEMA: companies columns
-- ============================================================================
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS delete_reason text,
  ADD COLUMN IF NOT EXISTS is_demo boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_companies_deleted_at
  ON companies(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_is_demo ON companies(is_demo);

-- ============================================================================
-- 2. AUDIT LOG TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS company_audit_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL,
  company_name varchar(255),
  action varchar(50) NOT NULL,
  performed_by uuid REFERENCES auth.users(id),
  performed_by_email varchar(255),
  performed_by_role varchar(50),
  delete_reason text,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_company_audit_log_company
  ON company_audit_log(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_company_audit_log_action
  ON company_audit_log(action, created_at DESC);

-- Lock down: nobody reads via PostgREST. Service panel uses SECURITY DEFINER
-- RPCs (sp_*) that bypass RLS, and the regular app has no business reading
-- this table directly.
ALTER TABLE company_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_audit_log_deny_all ON company_audit_log;
CREATE POLICY company_audit_log_deny_all ON company_audit_log FOR ALL USING (false);

-- ============================================================================
-- 3. UPDATE EXISTING POLICIES on companies to hide soft-deleted rows
-- ============================================================================
DROP POLICY IF EXISTS companies_select ON companies;
DROP POLICY IF EXISTS company_access ON companies;
DROP POLICY IF EXISTS companies_visible ON companies;
DROP POLICY IF EXISTS companies_modify ON companies;

CREATE POLICY companies_visible ON companies
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  );

CREATE POLICY companies_modify ON companies
  FOR ALL
  USING (
    deleted_at IS NULL
    AND id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  )
  WITH CHECK (
    id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid())
  );

-- ============================================================================
-- 4. UPDATE get_my_companies / get_my_company_ids to filter deleted rows
-- (DROP first because return type may differ from existing definition)
-- ============================================================================
DROP FUNCTION IF EXISTS get_my_companies();
CREATE FUNCTION get_my_companies()
RETURNS TABLE(company_id uuid, company_name text, plan text, status text, role text, is_active boolean)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    c.id AS company_id,
    c.name::text AS company_name,
    c.plan::text,
    c.status::text,
    cu.role::text,
    (p.active_company_id = c.id) as is_active
  FROM companies c
  JOIN company_users cu ON cu.company_id = c.id AND cu.user_id = auth.uid()
  JOIN profiles p ON p.id = auth.uid()
  WHERE cu.status = 'active'
    AND c.deleted_at IS NULL
  ORDER BY c.name;
$$;

-- get_my_company_ids has the same signature (returns uuid[]) so CREATE OR REPLACE works
CREATE OR REPLACE FUNCTION get_my_company_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT ARRAY(
    SELECT cu.company_id
    FROM company_users cu
    JOIN companies c ON c.id = cu.company_id
    WHERE cu.user_id = auth.uid()
      AND c.deleted_at IS NULL
  );
$$;
GRANT EXECUTE ON FUNCTION get_my_companies() TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_company_ids() TO authenticated;

-- ============================================================================
-- 5. cleanup_expired_demos — only delete is_demo=true, with audit
-- (DROP first because original return type was void, new is jsonb)
-- ============================================================================
DROP FUNCTION IF EXISTS cleanup_expired_demos();
CREATE FUNCTION cleanup_expired_demos()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  demo RECORD;
  v_count int := 0;
BEGIN
  FOR demo IN
    SELECT da.id AS demo_id, da.company_id, da.expires_at, c.name AS company_name
    FROM demo_accounts da
    JOIN companies c ON c.id = da.company_id
    WHERE da.expires_at < now()
      AND da.is_active = true
      AND c.is_demo = true
  LOOP
    INSERT INTO company_audit_log (
      company_id, company_name, action,
      performed_by_role, delete_reason, details
    ) VALUES (
      demo.company_id, demo.company_name,
      'permanently_deleted', 'system',
      'Demo expired',
      jsonb_build_object('expires_at', demo.expires_at, 'demo_id', demo.demo_id)
    );

    DELETE FROM companies WHERE id = demo.company_id;
    UPDATE demo_accounts SET is_active = false WHERE id = demo.demo_id;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('deleted', v_count);
END;
$$;

-- ============================================================================
-- 6. soft_delete_company — owner-initiated from settings
-- ============================================================================
CREATE OR REPLACE FUNCTION soft_delete_company(
  p_company_id uuid,
  p_user_id uuid,
  p_user_email varchar,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company companies%ROWTYPE;
  v_role text;
BEGIN
  -- Find the company
  SELECT * INTO v_company FROM companies
  WHERE id = p_company_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'company_not_found');
  END IF;

  -- Verify the caller is owner of this company
  SELECT role INTO v_role FROM company_users
  WHERE company_id = p_company_id AND user_id = p_user_id;
  IF v_role IS NULL OR v_role NOT IN ('owner', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authorized');
  END IF;

  -- Demo company → instant permanent delete (still audited)
  IF v_company.is_demo THEN
    INSERT INTO company_audit_log (
      company_id, company_name, action,
      performed_by, performed_by_email, performed_by_role, delete_reason
    ) VALUES (
      p_company_id, v_company.name,
      'permanently_deleted',
      p_user_id, p_user_email, v_role,
      p_reason
    );

    DELETE FROM companies WHERE id = p_company_id;
    RETURN jsonb_build_object('success', true, 'type', 'permanent');
  END IF;

  -- Real company → soft delete
  UPDATE companies SET
    deleted_at = now(),
    deleted_by = p_user_id,
    delete_reason = p_reason
  WHERE id = p_company_id;

  INSERT INTO company_audit_log (
    company_id, company_name, action,
    performed_by, performed_by_email, performed_by_role,
    delete_reason, details
  ) VALUES (
    p_company_id, v_company.name,
    'soft_deleted',
    p_user_id, p_user_email, v_role,
    p_reason,
    jsonb_build_object(
      'plan', v_company.plan,
      'permanent_delete_after', (now() + interval '30 days')::text
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'type', 'soft',
    'permanent_delete_after', (now() + interval '30 days')::text
  );
END;
$$;

-- ============================================================================
-- 7. restore_company — UNDO soft delete, called from service panel
-- ============================================================================
CREATE OR REPLACE FUNCTION restore_company(
  p_company_id uuid,
  p_performed_by uuid,
  p_performed_by_email varchar
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company companies%ROWTYPE;
BEGIN
  SELECT * INTO v_company FROM companies
  WHERE id = p_company_id AND deleted_at IS NOT NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'company_not_found_or_not_deleted');
  END IF;

  UPDATE companies SET
    deleted_at = NULL,
    deleted_by = NULL,
    delete_reason = NULL
  WHERE id = p_company_id;

  INSERT INTO company_audit_log (
    company_id, company_name, action,
    performed_by, performed_by_email, performed_by_role
  ) VALUES (
    p_company_id, v_company.name,
    'restored',
    p_performed_by, p_performed_by_email, 'superadmin'
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 8. permanently_delete_company — only after 30 days, called from service panel
-- ============================================================================
CREATE OR REPLACE FUNCTION permanently_delete_company(
  p_company_id uuid,
  p_performed_by uuid,
  p_performed_by_email varchar
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company companies%ROWTYPE;
BEGIN
  SELECT * INTO v_company FROM companies
  WHERE id = p_company_id
    AND deleted_at IS NOT NULL
    AND deleted_at < now() - interval '30 days';

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'cannot_permanently_delete_before_30_days'
    );
  END IF;

  INSERT INTO company_audit_log (
    company_id, company_name, action,
    performed_by, performed_by_email, performed_by_role,
    details
  ) VALUES (
    p_company_id, v_company.name,
    'permanently_deleted',
    p_performed_by, p_performed_by_email, 'superadmin',
    jsonb_build_object(
      'soft_deleted_at', v_company.deleted_at,
      'delete_reason', v_company.delete_reason
    )
  );

  DELETE FROM companies WHERE id = p_company_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 9. SERVICE PANEL helpers — SECURITY DEFINER wrappers (bypass RLS)
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_trash_companies()
RETURNS json
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(row_to_json(c) ORDER BY c.deleted_at DESC), '[]'::json) FROM (
    SELECT
      c.id,
      c.name,
      c.plan,
      c.is_demo,
      c.deleted_at,
      c.delete_reason,
      au.email AS deleted_by_email,
      EXTRACT(DAY FROM (c.deleted_at + interval '30 days' - now()))::int AS days_left,
      (c.deleted_at + interval '30 days') AS permanent_delete_after,
      (SELECT COUNT(*) FROM company_users cu WHERE cu.company_id = c.id) AS user_count
    FROM companies c
    LEFT JOIN auth.users au ON au.id = c.deleted_by
    WHERE c.deleted_at IS NOT NULL
  ) c;
$$;

CREATE OR REPLACE FUNCTION sp_company_audit_log(p_company_id uuid)
RETURNS json
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(row_to_json(l) ORDER BY l.created_at DESC), '[]'::json) FROM (
    SELECT id, company_id, company_name, action,
           performed_by, performed_by_email, performed_by_role,
           delete_reason, details, created_at
    FROM company_audit_log
    WHERE company_id = p_company_id
  ) l;
$$;

CREATE OR REPLACE FUNCTION sp_expired_trash_count()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COUNT(*)::int FROM companies
  WHERE deleted_at IS NOT NULL
    AND deleted_at < now() - interval '30 days';
$$;

-- ============================================================================
-- 10. GRANTS — make RPCs callable from frontend
-- ============================================================================
GRANT EXECUTE ON FUNCTION soft_delete_company(uuid, uuid, varchar, text) TO authenticated;
GRANT EXECUTE ON FUNCTION restore_company(uuid, uuid, varchar) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION permanently_delete_company(uuid, uuid, varchar) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_trash_companies() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_company_audit_log(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_expired_trash_count() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION cleanup_expired_demos() TO authenticated;
