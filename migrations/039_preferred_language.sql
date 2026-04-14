-- Migration 039: User preferred language
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS preferred_language varchar(5) DEFAULT 'tr';

INSERT INTO migrations_log (file_name, notes)
VALUES ('039_preferred_language.sql', 'Add preferred_language to profiles for cross-device sync')
ON CONFLICT (file_name) DO NOTHING;
