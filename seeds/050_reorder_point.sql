-- 050_reorder_point.sql
-- Add per-product reorder_point and lead_time_days columns.
-- Replaces the global low_stock_threshold approach with per-product intelligence.

BEGIN;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS reorder_point decimal DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS lead_time_days integer DEFAULT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('050_reorder_point.sql',
  'Add reorder_point and lead_time_days to products for per-product reorder intelligence')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
