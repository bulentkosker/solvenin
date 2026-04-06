-- Update subscription + log history
CREATE OR REPLACE FUNCTION sp_update_subscription(
  p_user_id uuid, p_company_id uuid,
  p_plan text, p_max_users int, p_status text,
  p_start date, p_end date, p_note text
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE old_row RECORD;
BEGIN
  SELECT plan, max_users, subscription_status, subscription_end
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

  INSERT INTO service_panel_logs (user_id, action, target_company_id, details)
  VALUES (p_user_id, 'update_subscription', p_company_id,
    json_build_object('plan', p_plan, 'max_users', p_max_users, 'status', p_status, 'end', p_end, 'note', p_note)::jsonb);

  RETURN json_build_object('ok', true);
END;
$BODY$;

-- Subscription history
CREATE OR REPLACE FUNCTION sp_subscription_history(p_company_id uuid)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(h) ORDER BY h.created_at DESC), '[]'::json) FROM (
  SELECT sh.*, spu.name as changed_by_name
  FROM subscription_history sh
  LEFT JOIN service_panel_users spu ON spu.id = sh.changed_by
  WHERE sh.company_id = p_company_id
  ORDER BY sh.created_at DESC LIMIT 50
) h;
$BODY$;

-- Get company subscription info (for app pages)
CREATE OR REPLACE FUNCTION get_company_subscription(p_company_id uuid)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'plan', plan, 'max_users', max_users,
  'subscription_status', subscription_status,
  'subscription_start', subscription_start,
  'subscription_end', subscription_end,
  'is_frozen', is_frozen,
  'user_count', (SELECT COUNT(*) FROM company_users WHERE company_id = p_company_id),
  'days_left', CASE WHEN subscription_end IS NULL THEN NULL
    ELSE EXTRACT(DAY FROM (subscription_end::timestamp - now()))::int END
) FROM companies WHERE id = p_company_id;
$BODY$;
