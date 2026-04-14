-- Migration 040: Custom user limit per company
-- NULL = use plan default (free:1, standard:10, pro:unlimited)

ALTER TABLE companies ADD COLUMN IF NOT EXISTS custom_user_limit integer DEFAULT NULL;

-- Updated check_can_add_user: respects custom_user_limit override
CREATE OR REPLACE FUNCTION check_can_add_user(p_company_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_owner_plan text;
  v_custom_limit integer;
  v_user_count integer;
  v_effective_limit integer;
BEGIN
  SELECT p.plan, c.custom_user_limit
    INTO v_owner_plan, v_custom_limit
  FROM companies c
  LEFT JOIN profiles p ON p.id = c.owner_id
  WHERE c.id = p_company_id;

  IF v_custom_limit IS NOT NULL THEN
    v_effective_limit := v_custom_limit;
  ELSE
    v_effective_limit := CASE COALESCE(v_owner_plan, 'free')
      WHEN 'free' THEN 1
      WHEN 'standard' THEN 10
      WHEN 'pro' THEN 999999
      ELSE 1
    END;
  END IF;

  SELECT COUNT(*) INTO v_user_count FROM company_users WHERE company_id = p_company_id;

  IF v_user_count >= v_effective_limit THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'error', CASE WHEN v_owner_plan = 'free' THEN 'free_plan_no_users' ELSE 'user_limit_reached' END,
      'limit', v_effective_limit,
      'current', v_user_count
    );
  END IF;

  RETURN jsonb_build_object('allowed', true, 'limit', v_effective_limit, 'current', v_user_count);
END $$;

GRANT EXECUTE ON FUNCTION check_can_add_user(uuid) TO authenticated;

-- Service panel RPC to update limit
CREATE OR REPLACE FUNCTION sp_update_user_limit(p_company_id uuid, p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE companies SET custom_user_limit = p_limit WHERE id = p_company_id;
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END $$;

GRANT EXECUTE ON FUNCTION sp_update_user_limit(uuid, integer) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('040_custom_user_limit.sql', 'Add custom_user_limit + update check_can_add_user + sp_update_user_limit RPC')
ON CONFLICT (file_name) DO NOTHING;
