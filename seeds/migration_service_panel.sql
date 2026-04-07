CREATE OR REPLACE FUNCTION sp_login(p_email text, p_password text) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE u RECORD;
BEGIN
  SELECT id, email, name, role, is_active INTO u FROM service_panel_users
  WHERE email = p_email AND password_hash = p_password AND is_active = true;
  IF u.id IS NULL THEN RETURN json_build_object('ok', false, 'error', 'invalid'); END IF;
  UPDATE service_panel_users SET last_login = now() WHERE id = u.id;
  RETURN json_build_object('ok', true, 'id', u.id, 'email', u.email, 'name', u.name, 'role', u.role);
END;
$BODY$;

CREATE OR REPLACE FUNCTION sp_dashboard_stats() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'companies', (SELECT COUNT(*) FROM companies WHERE COALESCE(is_frozen,false)=false),
  'users', (SELECT COUNT(*) FROM profiles),
  'demos', (SELECT COUNT(*) FROM demo_accounts WHERE is_active=true AND expires_at>now()),
  'partners', (SELECT COUNT(*) FROM service_panel_users WHERE role='partner'),
  'invoices', (SELECT COUNT(*) FROM sales_orders WHERE status IN ('invoiced','paid','overdue') AND is_active=true),
  'contacts', (SELECT COUNT(*) FROM contacts WHERE is_active=true),
  'movements', (SELECT COUNT(*) FROM stock_movements WHERE is_active=true),
  'plan_free', (SELECT COUNT(*) FROM companies WHERE COALESCE(plan,'free')='free' AND COALESCE(is_frozen,false)=false),
  'plan_standard', (SELECT COUNT(*) FROM companies WHERE plan='standard' AND COALESCE(is_frozen,false)=false),
  'plan_pro', (SELECT COUNT(*) FROM companies WHERE plan='professional' AND COALESCE(is_frozen,false)=false),
  'new_companies_30d', (SELECT COUNT(*) FROM companies WHERE created_at > now() - interval '30 days'),
  'new_users_30d', (SELECT COUNT(*) FROM profiles WHERE created_at > now() - interval '30 days'),
  'new_demos_30d', (SELECT COUNT(*) FROM demo_accounts WHERE created_at > now() - interval '30 days')
);
$BODY$;

CREATE OR REPLACE FUNCTION sp_companies() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(c) ORDER BY c.created_at DESC), '[]'::json) FROM (
  SELECT c.id, c.name, c.country_code, c.plan, c.created_at, c.is_frozen, c.freeze_reason, c.logo_url,
    (SELECT COUNT(*) FROM company_users cu WHERE cu.company_id = c.id) as user_count,
    (SELECT COUNT(*) FROM sales_orders so WHERE so.company_id = c.id AND so.status IN ('invoiced','paid','overdue') AND so.is_active=true) as invoice_count,
    (SELECT COUNT(*) FROM stock_movements sm WHERE sm.company_id = c.id AND sm.is_active=true) as stock_count,
    (SELECT spu.name FROM service_panel_users spu WHERE spu.id = c.partner_id) as partner_name
  FROM companies c
) c;
$BODY$;

CREATE OR REPLACE FUNCTION sp_users() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(u) ORDER BY u.created_at DESC), '[]'::json) FROM (
  SELECT p.id, p.full_name, p.plan, p.created_at,
    (SELECT email FROM auth.users au WHERE au.id = p.id) as email,
    (SELECT c.name FROM companies c JOIN company_users cu ON cu.company_id = c.id WHERE cu.user_id = p.id LIMIT 1) as company_name,
    (SELECT cu.role FROM company_users cu WHERE cu.user_id = p.id LIMIT 1) as company_role
  FROM profiles p
) u;
$BODY$;

CREATE OR REPLACE FUNCTION sp_recent_logs(p_limit int DEFAULT 20) RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(l)), '[]'::json) FROM (
  SELECT sl.action, sl.details, sl.created_at, spu.email as user_email, c.name as company_name
  FROM service_panel_logs sl
  LEFT JOIN service_panel_users spu ON spu.id = sl.user_id
  LEFT JOIN companies c ON c.id = sl.target_company_id
  ORDER BY sl.created_at DESC LIMIT p_limit
) l;
$BODY$;

CREATE OR REPLACE FUNCTION sp_company_users(p_company_id uuid) RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(u)), '[]'::json) FROM (
  SELECT p.id, p.full_name, cu.role,
    (SELECT email FROM auth.users au WHERE au.id = p.id) as email
  FROM company_users cu JOIN profiles p ON p.id = cu.user_id
  WHERE cu.company_id = p_company_id
) u;
$BODY$;

CREATE OR REPLACE FUNCTION sp_demos() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.created_at DESC), '[]'::json) FROM (
  SELECT da.id, da.email, da.password, da.language, da.expires_at, da.is_active, da.created_at,
    spu.name as creator_name, c.name as company_name
  FROM demo_accounts da
  LEFT JOIN service_panel_users spu ON spu.id = da.created_by
  LEFT JOIN companies c ON c.id = da.company_id
) d;
$BODY$;

CREATE OR REPLACE FUNCTION sp_log(p_user_id uuid, p_action text, p_company_id uuid DEFAULT NULL, p_details jsonb DEFAULT NULL) RETURNS void LANGUAGE sql SECURITY DEFINER AS $BODY$
INSERT INTO service_panel_logs (user_id, action, target_company_id, details) VALUES (p_user_id, p_action, p_company_id, p_details);
$BODY$;

CREATE OR REPLACE FUNCTION sp_panel_users() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(u) ORDER BY u.created_at DESC), '[]'::json) FROM (
  SELECT id, email, name, role, is_active, last_login, created_at FROM service_panel_users
) u;
$BODY$;

CREATE OR REPLACE FUNCTION sp_update_company(p_user_id uuid, p_company_id uuid, p_field text, p_value text) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
BEGIN
  IF p_field = 'plan' THEN
    UPDATE companies SET plan = p_value WHERE id = p_company_id;
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

CREATE OR REPLACE FUNCTION cleanup_expired_demos() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE demo RECORD;
BEGIN
  FOR demo IN SELECT * FROM demo_accounts WHERE expires_at < now() AND is_active = true LOOP
    DELETE FROM companies WHERE id = demo.company_id;
    UPDATE demo_accounts SET is_active = false WHERE id = demo.id;
  END LOOP;
END;
$BODY$;
