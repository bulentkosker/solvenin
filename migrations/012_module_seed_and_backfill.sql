-- Migration: 012_module_seed_and_backfill
-- Description: Update create_company_for_user to seed full module catalog +
--              backfill existing companies with all module rows
-- Backward Compatible: YES — adds rows, no schema change
-- Rollback: not strictly necessary; the catalog rows are append-only

-- The existing company_modules table uses these column names:
--   module      varchar  -- the key (e.g. 'inventory', 'pos')
--   is_active   boolean  -- enabled flag
--
-- Adapting to that — NOT renaming to module_key/is_enabled — because
-- migration RULES.md forbids column renames on a populated table.

CREATE OR REPLACE FUNCTION create_company_for_user(
  p_name text,
  p_country_code text,
  p_base_currency text,
  p_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_slug text;
  v_company_id uuid;
  v_user_email text;
BEGIN
  SELECT email INTO v_user_email FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_user');
  END IF;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug) || '-' || extract(epoch from now())::bigint::text;

  INSERT INTO companies (
    name, slug, country_code, base_currency, plan, status,
    owner_id, max_users, subscription_status, subscription_end
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

  -- Seed full module catalog: standard ON, sector OFF
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
    (v_company_id, 'reports',     true),
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

-- One-time backfill: every existing company gets every module row.
-- Standard ones default to active=true, sector ones to active=false.
-- ON CONFLICT preserves any existing rows so previous toggles are respected.
INSERT INTO company_modules (company_id, module, is_active)
SELECT c.id, m.module, m.is_active
FROM companies c
CROSS JOIN (VALUES
  ('inventory',   true),
  ('sales',       true),
  ('purchasing',  true),
  ('contacts',    true),
  ('finance',     true),
  ('accounting',  true),
  ('hr',          true),
  ('production',  true),
  ('projects',    true),
  ('shipping',    true),
  ('maintenance', true),
  ('crm',         true),
  ('reports',     true),
  ('pos',         false),
  ('restaurant',  false),
  ('hotel',       false),
  ('clinic',      false),
  ('elevator',    false),
  ('ecommerce',   false)
) AS m(module, is_active)
WHERE c.deleted_at IS NULL
ON CONFLICT (company_id, module) DO NOTHING;

INSERT INTO migrations_log (file_name, notes)
VALUES ('012_module_seed_and_backfill.sql', 'Update create_company_for_user to seed all 19 modules + backfill existing companies')
ON CONFLICT (file_name) DO NOTHING;
