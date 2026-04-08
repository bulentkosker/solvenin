-- Migration: 005_migrations_log
-- Description: Creates the migrations_log table itself
-- Backward Compatible: YES (new table)
-- Rollback:
--   DROP TABLE IF EXISTS migrations_log;

-- UP
CREATE TABLE IF NOT EXISTS migrations_log (
  id serial PRIMARY KEY,
  file_name varchar(255) UNIQUE NOT NULL,
  executed_at timestamptz DEFAULT now(),
  executed_by varchar(100) DEFAULT 'system',
  status varchar(20) DEFAULT 'success',
  duration_ms int,
  notes text
);

ALTER TABLE migrations_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS migrations_log_read ON migrations_log;
CREATE POLICY migrations_log_read ON migrations_log FOR SELECT USING (true);

INSERT INTO migrations_log (file_name, notes)
VALUES ('005_migrations_log.sql', 'Create migrations_log table')
ON CONFLICT (file_name) DO NOTHING;
