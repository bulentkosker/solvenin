-- 014_drop_reports_module.sql
-- Removes the standalone "reports" module from company_modules.
-- Reports are surfaced as cross-cutting children under each parent
-- module (Stok > Raporlar, Satış > Raporlar, ...). The standalone
-- module key was redundant: it never had its own top-level NAV entry
-- and only existed to gate child links — which now inherit from
-- their parent module's visibility instead.
--
-- Backward-compat: removing rows is safe; no schema change. The
-- reports children in sidebar.js no longer reference any module key.

-- 1. Drop the data
DELETE FROM company_modules WHERE module = 'reports';

-- 2. Replace the create_company_for_user RPC with a version that
--    does NOT seed a 'reports' row.
CREATE OR REPLACE FUNCTION create_company_for_user(
  p_user_id       uuid,
  p_name          text,
  p_country_code  text,
  p_base_currency text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_slug       text;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid user');
  END IF;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'))
            || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  INSERT INTO companies (
    name, slug, country_code, base_currency, plan, status,
    owner_id, max_users, subscription_status, trial_ends_at
  ) VALUES (
    p_name, v_slug, p_country_code, p_base_currency, 'free', 'active',
    p_user_id, 3, 'trial', now() + interval '14 days'
  )
  RETURNING id INTO v_company_id;

  INSERT INTO company_users (
    company_id, user_id, role, status, joined_at
  ) VALUES (
    v_company_id, p_user_id, 'owner', 'active', now()
  );

  INSERT INTO company_modules (company_id, module, is_active) VALUES
    (v_company_id, 'inventory',   true),
    (v_company_id, 'sales',       true),
    (v_company_id, 'purchasing',  true),
    (v_company_id, 'contacts',    true),
    (v_company_id, 'finance',     true),
    (v_company_id, 'accounting',  true),
    (v_company_id, 'hr',          true),
    (v_company_id, 'production',  true),
    (v_company_id, 'projects',    true),
    (v_company_id, 'shipping',    true),
    (v_company_id, 'maintenance', true),
    (v_company_id, 'crm',         true),
    (v_company_id, 'pos',         false),
    (v_company_id, 'restaurant',  false),
    (v_company_id, 'hotel',       false),
    (v_company_id, 'clinic',      false),
    (v_company_id, 'elevator',    false),
    (v_company_id, 'ecommerce',   false)
  ON CONFLICT (company_id, module) DO NOTHING;

  BEGIN
    INSERT INTO warehouses (company_id, name, is_default)
    VALUES (v_company_id, 'Main Warehouse', true);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'company_id', v_company_id, 'slug', v_slug);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION create_company_for_user(uuid, text, text, text) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('014_drop_reports_module.sql', 'Drop reports module — children inherit from parent module visibility')
ON CONFLICT (file_name) DO NOTHING;
