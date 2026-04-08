-- Migration: 006_feature_flags
-- Description: Feature flags + sp_* helper RPCs for runtime toggles
-- Backward Compatible: YES (new table + new RPCs, no existing code changes)
-- Rollback:
--   DROP FUNCTION IF EXISTS sp_set_maintenance_mode(boolean);
--   DROP FUNCTION IF EXISTS sp_update_feature_flag(varchar, boolean, varchar[], uuid[], int);
--   DROP FUNCTION IF EXISTS sp_feature_flags();
--   DROP TABLE IF EXISTS feature_flags;

-- UP
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
  ('marketplace_integration', 'Marketplace integrations',                    false, '{}'),
  ('offline_pos',             'Offline-first POS with IndexedDB queue',      false, '{"professional"}'),
  ('silo_management',         'Silo inventory tracking',                     false, '{}'),
  ('advanced_reports',        'Advanced cross-module analytics',             true,  '{}'),
  ('maintenance_mode',        'Global maintenance lock',                     false, '{}'),
  ('app_version',             '1.0.0',                                       false, '{}')
ON CONFLICT (flag_name) DO NOTHING;

ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS feature_flags_read ON feature_flags;
CREATE POLICY feature_flags_read ON feature_flags FOR SELECT USING (true);

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

GRANT EXECUTE ON FUNCTION sp_feature_flags() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_update_feature_flag(varchar, boolean, varchar[], uuid[], int) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sp_set_maintenance_mode(boolean) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('006_feature_flags.sql', 'Feature flags table + sp_* RPCs')
ON CONFLICT (file_name) DO NOTHING;
