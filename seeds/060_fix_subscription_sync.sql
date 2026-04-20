-- 060_fix_subscription_sync.sql
-- Fix: sp_update_subscription syncs to profiles + sp_update_user_plan saves plan_user_count.

BEGIN;

-- Fix 1: sp_update_subscription syncs to owner's profiles row
CREATE OR REPLACE FUNCTION sp_update_subscription(
  p_user_id uuid, p_company_id uuid,
  p_plan text, p_max_users int, p_status text,
  p_start date, p_end date, p_note text
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE old_row RECORD; v_owner_id uuid;
BEGIN
  SELECT plan, max_users, subscription_status, subscription_end, owner_id
  INTO old_row FROM companies WHERE id = p_company_id;

  INSERT INTO subscription_history (
    company_id, changed_by, old_plan, new_plan, old_max_users, new_max_users,
    old_status, new_status, old_end_date, new_end_date, note
  ) VALUES (
    p_company_id, p_user_id, old_row.plan, p_plan,
    old_row.max_users, p_max_users,
    old_row.subscription_status, p_status,
    old_row.subscription_end, p_end, p_note
  );

  UPDATE companies SET
    plan = p_plan, max_users = p_max_users,
    subscription_status = p_status,
    subscription_start = p_start, subscription_end = p_end
  WHERE id = p_company_id;

  v_owner_id := old_row.owner_id;
  IF v_owner_id IS NULL THEN
    SELECT user_id INTO v_owner_id FROM company_users WHERE company_id = p_company_id AND role = 'owner' LIMIT 1;
    IF v_owner_id IS NOT NULL THEN
      UPDATE companies SET owner_id = v_owner_id WHERE id = p_company_id;
    END IF;
  END IF;

  IF v_owner_id IS NOT NULL THEN
    UPDATE profiles SET
      plan = p_plan,
      plan_user_count = p_max_users,
      plan_status = p_status,
      plan_expires_at = p_end
    WHERE id = v_owner_id;
  END IF;

  INSERT INTO service_panel_logs (user_id, action, target_company_id, details)
  VALUES (p_user_id, 'update_subscription', p_company_id,
    json_build_object('plan', p_plan, 'max_users', p_max_users, 'status', p_status, 'end', p_end, 'note', p_note)::jsonb);

  RETURN json_build_object('ok', true);
END;
$BODY$;

-- Fix 2: sp_update_user_plan was NOT saving plan_user_count
CREATE OR REPLACE FUNCTION sp_update_user_plan(
  p_user_id uuid,
  p_plan text DEFAULT NULL,
  p_plan_end timestamptz DEFAULT NULL,
  p_plan_status text DEFAULT NULL,
  p_plan_user_count int DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  v_count int;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid user');
  END IF;

  v_count := COALESCE(p_plan_user_count, CASE COALESCE(p_plan, (SELECT plan FROM profiles WHERE id = p_user_id))
    WHEN 'free' THEN 1 WHEN 'standard' THEN 3 WHEN 'pro' THEN 999999 ELSE 1 END);

  UPDATE profiles SET
    plan = COALESCE(p_plan, plan),
    plan_expires_at = p_plan_end,
    plan_status = COALESCE(p_plan_status, plan_status),
    plan_user_count = v_count
  WHERE id = p_user_id;

  UPDATE companies SET
    plan = COALESCE(p_plan, plan),
    max_users = v_count
  WHERE owner_id = p_user_id;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$BODY$;

-- Fix 3: sp_update_company plan change also syncs to profiles
CREATE OR REPLACE FUNCTION sp_update_company(p_user_id uuid, p_company_id uuid, p_field text, p_value text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  v_owner_id uuid;
BEGIN
  IF p_field = 'plan' THEN
    UPDATE companies SET plan = p_value WHERE id = p_company_id;
    SELECT owner_id INTO v_owner_id FROM companies WHERE id = p_company_id;
    IF v_owner_id IS NOT NULL THEN
      UPDATE profiles SET
        plan = p_value,
        plan_user_count = CASE p_value
          WHEN 'free' THEN 1 WHEN 'standard' THEN 3 WHEN 'pro' THEN 999999 ELSE 1 END
      WHERE id = v_owner_id;
    END IF;
  ELSIF p_field = 'max_users' THEN
    UPDATE companies SET max_users = p_value::int WHERE id = p_company_id;
    SELECT owner_id INTO v_owner_id FROM companies WHERE id = p_company_id;
    IF v_owner_id IS NOT NULL THEN
      UPDATE profiles SET plan_user_count = p_value::int WHERE id = v_owner_id;
    END IF;
  ELSIF p_field = 'is_frozen' THEN
    UPDATE companies SET is_frozen = (p_value = 'true') WHERE id = p_company_id;
  ELSIF p_field = 'freeze_reason' THEN
    UPDATE companies SET freeze_reason = p_value WHERE id = p_company_id;
  ELSIF p_field = 'trial_ends_at' THEN
    UPDATE companies SET trial_ends_at = p_value::timestamptz WHERE id = p_company_id;
  ELSIF p_field = 'invoice_limit_override' THEN
    UPDATE companies SET invoice_limit_override = p_value::int WHERE id = p_company_id;
  ELSIF p_field = 'service_notes' THEN
    UPDATE companies SET service_notes = p_value WHERE id = p_company_id;
  END IF;
  INSERT INTO service_panel_logs (user_id, action, target_company_id, details)
  VALUES (p_user_id, 'update_company_' || p_field, p_company_id, json_build_object('field', p_field, 'value', p_value)::jsonb);
  RETURN json_build_object('ok', true);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('060_fix_subscription_sync.sql',
  'Fix all 3 plan update functions to sync companies↔profiles: sp_update_subscription, sp_update_user_plan, sp_update_company')
ON CONFLICT (file_name) DO UPDATE SET notes = EXCLUDED.notes;

COMMIT;
