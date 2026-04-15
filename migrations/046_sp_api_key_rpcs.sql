-- Migration 046: Service panel — Anthropic API key management RPCs

-- Ensure the row exists (no-op if already there)
INSERT INTO app_settings (key, value, is_secret)
VALUES ('anthropic_api_key', '', true)
ON CONFLICT (key) DO NOTHING;

-- Helper: is current caller superadmin?
CREATE OR REPLACE FUNCTION _sp_is_superadmin(p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM service_panel_users
    WHERE id = p_user_id AND role = 'superadmin' AND COALESCE(is_active, true)
  );
$$;

-- Info (masked) — superadmin only
DROP FUNCTION IF EXISTS sp_get_anthropic_key_info(uuid);
CREATE OR REPLACE FUNCTION sp_get_anthropic_key_info(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text;
BEGIN
  IF NOT _sp_is_superadmin(p_user_id) THEN
    RETURN jsonb_build_object('error', 'forbidden');
  END IF;
  SELECT value INTO v FROM app_settings WHERE key = 'anthropic_api_key';
  IF v IS NULL OR v = '' THEN
    RETURN jsonb_build_object('has_key', false, 'masked', '', 'length', 0);
  END IF;
  RETURN jsonb_build_object(
    'has_key', true,
    'length', length(v),
    'masked', CASE WHEN length(v) <= 8 THEN repeat('•', length(v))
                   ELSE left(v, 7) || repeat('•', 8) || right(v, 4) END
  );
END $$;
GRANT EXECUTE ON FUNCTION sp_get_anthropic_key_info(uuid) TO authenticated, anon;

-- Set — superadmin only
DROP FUNCTION IF EXISTS sp_set_anthropic_key(uuid, text);
CREATE OR REPLACE FUNCTION sp_set_anthropic_key(p_user_id uuid, p_value text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT _sp_is_superadmin(p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'forbidden');
  END IF;
  IF p_value IS NULL OR length(trim(p_value)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_key');
  END IF;
  UPDATE app_settings SET value = trim(p_value), updated_at = now() WHERE key = 'anthropic_api_key';
  IF NOT FOUND THEN
    INSERT INTO app_settings (key, value, is_secret) VALUES ('anthropic_api_key', trim(p_value), true);
  END IF;
  RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION sp_set_anthropic_key(uuid, text) TO authenticated, anon;

-- Raw fetch (only for the Test button) — superadmin only
DROP FUNCTION IF EXISTS sp_get_anthropic_key_raw(uuid);
CREATE OR REPLACE FUNCTION sp_get_anthropic_key_raw(p_user_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT _sp_is_superadmin(p_user_id) THEN
    RETURN NULL;
  END IF;
  RETURN (SELECT value FROM app_settings WHERE key = 'anthropic_api_key');
END $$;
GRANT EXECUTE ON FUNCTION sp_get_anthropic_key_raw(uuid) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('046_sp_api_key_rpcs.sql', 'Superadmin-gated RPCs for anthropic_api_key: info/set/raw (masked display, audit via RLS)')
ON CONFLICT (file_name) DO NOTHING;
