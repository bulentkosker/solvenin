-- Migration 047: app_settings.updated_at + auto-touch trigger
-- Required by sp_set_anthropic_key (it writes updated_at on UPDATE)

ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

UPDATE app_settings SET updated_at = COALESCE(updated_at, created_at, now())
  WHERE updated_at IS NULL;

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_settings_updated_at ON app_settings;
CREATE TRIGGER app_settings_updated_at
  BEFORE UPDATE ON app_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

INSERT INTO migrations_log (file_name, notes)
VALUES ('047_app_settings_updated_at.sql', 'app_settings.updated_at column + BEFORE UPDATE trigger')
ON CONFLICT (file_name) DO NOTHING;
