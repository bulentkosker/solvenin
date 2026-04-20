-- 060_fix_subscription_sync.sql
-- Fix: sp_update_subscription now syncs plan + max_users to owner's profiles row.
-- check_user_limit trigger reads profiles.plan, not companies.plan.

BEGIN;

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

  -- Sync to owner profile so check_user_limit trigger sees correct values
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

INSERT INTO migrations_log (file_name, notes)
VALUES ('060_fix_subscription_sync.sql',
  'sp_update_subscription syncs plan+max_users to owner profiles + auto-fixes NULL owner_id')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
