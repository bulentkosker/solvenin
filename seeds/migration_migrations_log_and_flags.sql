-- ===== MIGRATIONS LOG + FEATURE FLAGS =====
-- 2026-04-08

-- ============================================================================
-- 1. migrations_log — track which migrations have run
-- ============================================================================
CREATE TABLE IF NOT EXISTS migrations_log (
  id serial PRIMARY KEY,
  file_name varchar(255) UNIQUE NOT NULL,
  executed_at timestamptz DEFAULT now(),
  executed_by varchar(100) DEFAULT 'system',
  status varchar(20) DEFAULT 'success',
  duration_ms int,
  notes text
);

INSERT INTO migrations_log (file_name, notes) VALUES
  ('001_initial_schema.sql', 'Initial schema (companies, products, sales/purchase orders, contacts, etc.)'),
  ('002_add_is_service.sql', 'Add is_service boolean to products for product/service classification'),
  ('003_company_logo.sql', 'Add logo_url text column to companies (data URL storage)'),
  ('004_company_soft_delete.sql', 'Soft delete + audit log + recovery RPCs'),
  ('005_migrations_log.sql', 'This migration: tracks all schema changes'),
  ('006_feature_flags.sql', 'Feature flags table + helper RPCs')
ON CONFLICT (file_name) DO NOTHING;

-- ============================================================================
-- 2. feature_flags — runtime feature toggles
-- ============================================================================
CREATE TABLE IF NOT EXISTS feature_flags (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  flag_name varchar(100) UNIQUE NOT NULL,
  description text,
  is_enabled_globally boolean DEFAULT false,
  enabled_for_companies uuid[] DEFAULT '{}',
  enabled_for_plans varchar[] DEFAULT '{}',
  rollout_percentage int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_name ON feature_flags(flag_name);

INSERT INTO feature_flags (flag_name, description, is_enabled_globally, enabled_for_plans) VALUES
  ('elevator_module',         'Elevator/silo & weighbridge management',      false, '{}'),
  ('marketplace_integration', 'Marketplace integrations (Trendyol, Hepsiburada, etc.)', false, '{}'),
  ('offline_pos',             'Offline-first POS with IndexedDB queue',      false, '{"professional"}'),
  ('silo_management',         'Silo inventory tracking',                     false, '{}'),
  ('advanced_reports',        'Advanced cross-module analytics',             true,  '{}'),
  ('maintenance_mode',        'Global maintenance lock — redirects all users to /maintenance.html', false, '{}'),
  ('app_version',             '1.0.0',                                       false, '{}')
ON CONFLICT (flag_name) DO NOTHING;

-- ============================================================================
-- 3. RLS — anyone can READ flags (the app needs them on every page),
--    only superadmin/support panel users can WRITE (via SECURITY DEFINER RPCs)
-- ============================================================================
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS feature_flags_read ON feature_flags;
CREATE POLICY feature_flags_read ON feature_flags
  FOR SELECT USING (true);

-- We do NOT create a FOR ALL/INSERT/UPDATE policy for end users because
-- the service panel is a separate auth system (own table service_panel_users
-- with its own bcrypt password, no link to auth.users). All writes go through
-- the SECURITY DEFINER sp_* functions below which bypass RLS.

ALTER TABLE migrations_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS migrations_log_read ON migrations_log;
CREATE POLICY migrations_log_read ON migrations_log FOR SELECT USING (true);

-- ============================================================================
-- 4. SECURITY DEFINER helpers for the service panel
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_feature_flags()
RETURNS json LANGUAGE sql SECURITY DEFINER AS $$
  SELECT COALESCE(json_agg(row_to_json(f) ORDER BY f.flag_name), '[]'::json) FROM (
    SELECT id, flag_name, description, is_enabled_globally,
           enabled_for_companies, enabled_for_plans, rollout_percentage,
           created_at, updated_at
    FROM feature_flags
  ) f;
$$;

CREATE OR REPLACE FUNCTION sp_update_feature_flag(
  p_flag_name varchar,
  p_is_enabled_globally boolean,
  p_enabled_for_plans varchar[],
  p_enabled_for_companies uuid[],
  p_rollout_percentage int
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE feature_flags SET
    is_enabled_globally = p_is_enabled_globally,
    enabled_for_plans = COALESCE(p_enabled_for_plans, '{}'),
    enabled_for_companies = COALESCE(p_enabled_for_companies, '{}'),
    rollout_percentage = COALESCE(p_rollout_percentage, 0),
    updated_at = now()
  WHERE flag_name = p_flag_name;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'flag_not_found');
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Lightweight maintenance toggle (no params besides the bool — used by the
-- service panel's big red maintenance button)
CREATE OR REPLACE FUNCTION sp_set_maintenance_mode(p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE feature_flags SET
    is_enabled_globally = p_enabled,
    updated_at = now()
  WHERE flag_name = 'maintenance_mode';
  RETURN jsonb_build_object('success', true, 'enabled', p_enabled);
END;
$$;

-- ============================================================================
-- 5. GRANTS
-- ============================================================================
GRANT EXECUTE ON FUNCTION sp_feature_flags() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_update_feature_flag(varchar, boolean, varchar[], uuid[], int) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_set_maintenance_mode(boolean) TO authenticated, anon;
