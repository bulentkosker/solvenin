-- ============================================================
-- Migration 015: Add missing foreign keys
-- Add FK constraints on orphaned user ID fields and cross-table refs
-- Each wrapped in DO block to skip gracefully if constraint exists
-- or column/table is missing
-- ============================================================

-- 1. pos_sessions.cashier_id → auth.users(id)
DO $$ BEGIN
  ALTER TABLE pos_sessions
    ADD CONSTRAINT pos_sessions_cashier_id_fkey
      FOREIGN KEY (cashier_id) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 2. pos_sessions.opened_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE pos_sessions
    ADD CONSTRAINT pos_sessions_opened_by_fkey
      FOREIGN KEY (opened_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 3. maintenance_history.work_order_id → work_orders(id)
DO $$ BEGIN
  ALTER TABLE maintenance_history
    ADD CONSTRAINT maintenance_history_work_order_id_fkey
      FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 4. serial_numbers.purchase_order_item_id → purchase_order_items(id)
DO $$ BEGIN
  ALTER TABLE serial_numbers
    ADD CONSTRAINT serial_numbers_purchase_order_item_id_fkey
      FOREIGN KEY (purchase_order_item_id) REFERENCES purchase_order_items(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 5. serial_numbers.sales_order_item_id → sales_order_items(id)
DO $$ BEGIN
  ALTER TABLE serial_numbers
    ADD CONSTRAINT serial_numbers_sales_order_item_id_fkey
      FOREIGN KEY (sales_order_item_id) REFERENCES sales_order_items(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 6. crm_opportunities.assigned_to → auth.users(id)
DO $$ BEGIN
  ALTER TABLE crm_opportunities
    ADD CONSTRAINT crm_opportunities_assigned_to_fkey
      FOREIGN KEY (assigned_to) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 7. tasks.assignee_id → auth.users(id)
DO $$ BEGIN
  ALTER TABLE tasks
    ADD CONSTRAINT tasks_assignee_id_fkey
      FOREIGN KEY (assignee_id) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 8. journal_entries.created_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE journal_entries
    ADD CONSTRAINT journal_entries_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 9. crm_quotes.created_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE crm_quotes
    ADD CONSTRAINT crm_quotes_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 10. data_backups.created_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE data_backups
    ADD CONSTRAINT data_backups_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 11. data_imports.created_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE data_imports
    ADD CONSTRAINT data_imports_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- 12. repair_logs.performed_by → auth.users(id)
DO $$ BEGIN
  ALTER TABLE repair_logs
    ADD CONSTRAINT repair_logs_performed_by_fkey
      FOREIGN KEY (performed_by) REFERENCES auth.users(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_column THEN NULL;
         WHEN undefined_table THEN NULL;
END $$;

-- migrations_log
INSERT INTO migrations_log (file_name, notes)
VALUES ('015_missing_foreign_keys.sql',
  'Add missing FK constraints on user ID fields and cross-table references')
ON CONFLICT (file_name) DO NOTHING;
