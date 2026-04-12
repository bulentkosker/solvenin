-- ============================================================
-- Migration 021: Cleanup unused tables and dead columns
-- ============================================================

-- Step 1: Drop unused empty tables
DROP TABLE IF EXISTS localization_accounts CASCADE;
DROP TABLE IF EXISTS invitations CASCADE;
DROP TABLE IF EXISTS equipment_categories CASCADE;
DROP TABLE IF EXISTS project_files CASCADE;
DROP TABLE IF EXISTS project_members CASCADE;
DROP TABLE IF EXISTS task_comments CASCADE;
DROP TABLE IF EXISTS task_groups CASCADE;

-- Step 2: Remove dead columns from products
ALTER TABLE products
  DROP COLUMN IF EXISTS pos_quick_button,
  DROP COLUMN IF EXISTS pos_button_color,
  DROP COLUMN IF EXISTS pos_button_order;

-- Step 3: Remove legacy duplicate FK columns
ALTER TABLE sales_orders DROP COLUMN IF EXISTS contact_id;
ALTER TABLE purchase_orders DROP COLUMN IF EXISTS contact_id;

-- migrations_log
INSERT INTO migrations_log (file_name, notes)
VALUES ('021_cleanup.sql',
  'Drop 7 unused tables, remove 3 dead product columns, remove 2 legacy contact_id columns')
ON CONFLICT (file_name) DO NOTHING;
