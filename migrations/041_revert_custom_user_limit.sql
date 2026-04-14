-- Migration 041: Revert M040 — plan management stays on users only
-- Decision: no per-company user limit override. Owner's plan controls everything.

ALTER TABLE companies DROP COLUMN IF EXISTS custom_user_limit;
DROP FUNCTION IF EXISTS sp_update_user_limit(uuid, integer);

-- Simpler check: free plan = no additional users, paid plan = unlimited (at least for now)
CREATE OR REPLACE FUNCTION check_can_add_user(p_company_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_owner_plan text;
BEGIN
  SELECT p.plan INTO v_owner_plan
  FROM companies c LEFT JOIN profiles p ON p.id = c.owner_id
  WHERE c.id = p_company_id;
  IF COALESCE(v_owner_plan, 'free') = 'free' THEN
    RETURN jsonb_build_object('allowed', false, 'error', 'free_plan_no_users');
  END IF;
  RETURN jsonb_build_object('allowed', true);
END $$;

GRANT EXECUTE ON FUNCTION check_can_add_user(uuid) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('041_revert_custom_user_limit.sql', 'Revert M040: plan management is on users only')
ON CONFLICT (file_name) DO NOTHING;
