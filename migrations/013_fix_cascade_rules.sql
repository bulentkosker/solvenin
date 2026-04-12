-- ============================================================
-- Migration 013: Fix CASCADE rules
-- Change SET NULL → RESTRICT on critical FKs to prevent
-- orphaned records and data integrity loss
-- ============================================================

-- 1. stock_movements.product_id: SET NULL → RESTRICT
ALTER TABLE stock_movements
  DROP CONSTRAINT IF EXISTS stock_movements_product_id_fkey;
ALTER TABLE stock_movements
  ADD CONSTRAINT stock_movements_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;

-- 2. journal_lines.account_id: SET NULL → RESTRICT
ALTER TABLE journal_lines
  DROP CONSTRAINT IF EXISTS journal_lines_account_id_fkey;
ALTER TABLE journal_lines
  ADD CONSTRAINT journal_lines_account_id_fkey
    FOREIGN KEY (account_id) REFERENCES chart_of_accounts(id) ON DELETE RESTRICT;

-- 3. sales_order_items.product_id: SET NULL → RESTRICT
ALTER TABLE sales_order_items
  DROP CONSTRAINT IF EXISTS sales_order_items_product_id_fkey;
ALTER TABLE sales_order_items
  ADD CONSTRAINT sales_order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;

-- 4. purchase_order_items.product_id: SET NULL → RESTRICT
ALTER TABLE purchase_order_items
  DROP CONSTRAINT IF EXISTS purchase_order_items_product_id_fkey;
ALTER TABLE purchase_order_items
  ADD CONSTRAINT purchase_order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT;

-- 5. payments.order_id: NO ACTION → RESTRICT
ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS payments_order_id_fkey;
ALTER TABLE payments
  ADD CONSTRAINT payments_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

-- 6. pos_quick_buttons.product_id: SET NULL → CASCADE
ALTER TABLE pos_quick_buttons
  DROP CONSTRAINT IF EXISTS pos_quick_buttons_product_id_fkey;
ALTER TABLE pos_quick_buttons
  ADD CONSTRAINT pos_quick_buttons_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;

-- 7. shipments.order_id: add RESTRICT
ALTER TABLE shipments
  DROP CONSTRAINT IF EXISTS shipments_order_id_fkey;
ALTER TABLE shipments
  ADD CONSTRAINT shipments_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

-- migrations_log
INSERT INTO migrations_log (file_name, notes)
VALUES ('013_fix_cascade_rules.sql',
  'Fix CASCADE rules: product_id/account_id SET NULL → RESTRICT, payments RESTRICT, pos_quick_buttons CASCADE')
ON CONFLICT (file_name) DO NOTHING;
