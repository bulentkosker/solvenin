-- Migration 035: AI Assistant toggle per user
ALTER TABLE company_users ADD COLUMN IF NOT EXISTS ai_assistant_enabled boolean DEFAULT false;

INSERT INTO migrations_log (file_name, notes)
VALUES ('035_ai_assistant_toggle.sql', 'Add ai_assistant_enabled to company_users')
ON CONFLICT (file_name) DO NOTHING;
