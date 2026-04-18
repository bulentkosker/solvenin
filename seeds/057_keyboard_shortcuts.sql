-- 057_keyboard_shortcuts.sql
-- Per-user customizable keyboard shortcuts stored on company_users.

BEGIN;

ALTER TABLE company_users ADD COLUMN IF NOT EXISTS keyboard_shortcuts jsonb
  DEFAULT '{"save":"ctrl+enter","newLine":"ctrl+shift+enter","closeModal":"escape","nextField":"enter","search":"ctrl+f","newRecord":"ctrl+shift+n"}';

INSERT INTO migrations_log (file_name, notes)
VALUES ('057_keyboard_shortcuts.sql', 'keyboard_shortcuts jsonb column on company_users')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
