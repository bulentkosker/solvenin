-- ============================================================
-- Migration 037: Service panel — owner-based subscription updates
-- ============================================================

-- DROP first because return signatures change
DROP FUNCTION IF EXISTS sp_companies();
DROP FUNCTION IF EXISTS sp_users();

-- 1. Updated sp_companies: include owner_email instead of plan
CREATE OR REPLACE FUNCTION sp_companies()
RETURNS TABLE(
  id uuid, name text, country_code text,
  created_at timestamptz, is_frozen boolean, freeze_reason text,
  logo_url text, user_count bigint, invoice_count bigint,
  stock_count bigint, partner_name text,
  owner_id uuid, owner_email text, owner_plan text
)
LANGUAGE sql SECURITY DEFINER
AS $$
SELECT
  c.id, c.name::text, c.country_code::text,
  c.created_at, c.is_frozen, c.freeze_reason::text, c.logo_url::text,
  (SELECT COUNT(*) FROM company_users cu WHERE cu.company_id = c.id) AS user_count,
  (SELECT COUNT(*) FROM sales_orders so WHERE so.company_id = c.id AND so.is_active = true) AS invoice_count,
  (SELECT COUNT(*) FROM stock_movements sm WHERE sm.company_id = c.id AND sm.is_active = true) AS stock_count,
  NULL::text AS partner_name,
  c.owner_id,
  u.email::text AS owner_email,
  COALESCE(p.plan, 'free')::text AS owner_plan
FROM companies c
LEFT JOIN auth.users u ON u.id = c.owner_id
LEFT JOIN profiles p ON p.id = c.owner_id
WHERE c.deleted_at IS NULL
ORDER BY c.created_at DESC;
$$;

-- 2. Updated sp_users: include plan_status, plan_end (plan_expires_at)
CREATE OR REPLACE FUNCTION sp_users()
RETURNS TABLE(
  id uuid, full_name text, email text, company_name text, company_role text,
  plan text, plan_status text, plan_end timestamptz,
  trial_used boolean, created_at timestamptz
)
LANGUAGE sql SECURITY DEFINER
AS $$
SELECT
  p.id, p.full_name::text, u.email::text,
  (SELECT c.name FROM companies c
   JOIN company_users cu ON cu.company_id = c.id AND cu.user_id = p.id
   ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text AS company_name,
  (SELECT cu.role FROM company_users cu WHERE cu.user_id = p.id ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text AS company_role,
  COALESCE(p.plan, 'free')::text AS plan,
  COALESCE(p.plan_status, 'active')::text AS plan_status,
  p.plan_expires_at AS plan_end,
  COALESCE(p.trial_used, false) AS trial_used,
  p.created_at
FROM profiles p
JOIN auth.users u ON u.id = p.id
ORDER BY p.created_at DESC;
$$;

-- 3. New RPC: sp_update_user_plan
CREATE OR REPLACE FUNCTION sp_update_user_plan(
  p_user_id uuid,
  p_plan varchar,
  p_plan_end timestamptz,
  p_plan_status varchar
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid user');
  END IF;

  UPDATE profiles SET
    plan = COALESCE(p_plan, plan),
    plan_expires_at = p_plan_end,
    plan_status = COALESCE(p_plan_status, plan_status)
  WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION sp_update_user_plan(uuid, varchar, timestamptz, varchar) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('037_sp_user_plan.sql',
  'Service panel: sp_companies adds owner_email/owner_plan, sp_users adds plan_status/plan_end, new sp_update_user_plan RPC')
ON CONFLICT (file_name) DO NOTHING;
