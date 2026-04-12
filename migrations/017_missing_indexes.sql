-- ============================================================
-- Migration 017: Add missing indexes on FK columns
-- ============================================================

-- cash_transactions
CREATE INDEX IF NOT EXISTS idx_cash_transactions_register_id ON cash_transactions(register_id);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_company_id ON cash_transactions(company_id);

-- bank_transactions
CREATE INDEX IF NOT EXISTS idx_bank_transactions_account_id ON bank_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_company_id ON bank_transactions(company_id);

-- payments
CREATE INDEX IF NOT EXISTS idx_payments_company_id ON payments(company_id);

-- serial_numbers
CREATE INDEX IF NOT EXISTS idx_serial_numbers_product_id ON serial_numbers(product_id);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_variant_id ON serial_numbers(variant_id);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_purchase_order_id ON serial_numbers(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_sales_order_id ON serial_numbers(sales_order_id);

-- product_lots
CREATE INDEX IF NOT EXISTS idx_product_lots_product_id ON product_lots(product_id);
CREATE INDEX IF NOT EXISTS idx_product_lots_company_id ON product_lots(company_id);

-- bom
CREATE INDEX IF NOT EXISTS idx_bom_company_id ON bom(company_id);

-- bom_inputs
CREATE INDEX IF NOT EXISTS idx_bom_inputs_bom_id ON bom_inputs(bom_id);

-- maintenance_history
CREATE INDEX IF NOT EXISTS idx_maintenance_history_equipment_id ON maintenance_history(equipment_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_history_company_id ON maintenance_history(company_id);

-- crm_quotes
CREATE INDEX IF NOT EXISTS idx_crm_quotes_contact_id ON crm_quotes(contact_id);
CREATE INDEX IF NOT EXISTS idx_crm_quotes_company_id ON crm_quotes(company_id);

-- employees
CREATE INDEX IF NOT EXISTS idx_employees_position_id ON employees(position_id);
CREATE INDEX IF NOT EXISTS idx_employees_company_id ON employees(company_id);

-- fx_revaluations
CREATE INDEX IF NOT EXISTS idx_fx_revaluations_journal_entry_id ON fx_revaluations(journal_entry_id);

-- stock_movements (typed FK columns from M016)
CREATE INDEX IF NOT EXISTS idx_stock_movements_sales_order_id ON stock_movements(sales_order_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_purchase_order_id ON stock_movements(purchase_order_id);

-- journal_entries (typed FK columns from M016)
CREATE INDEX IF NOT EXISTS idx_journal_entries_sales_order_id ON journal_entries(sales_order_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_purchase_order_id ON journal_entries(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_payment_id ON journal_entries(payment_id);

-- cash_transactions (typed FK columns from M016)
CREATE INDEX IF NOT EXISTS idx_cash_transactions_sales_order_id ON cash_transactions(sales_order_id);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_purchase_order_id ON cash_transactions(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_cash_transactions_payment_id ON cash_transactions(payment_id);

-- bank_transactions (typed FK columns from M016)
CREATE INDEX IF NOT EXISTS idx_bank_transactions_sales_order_id ON bank_transactions(sales_order_id);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_purchase_order_id ON bank_transactions(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_bank_transactions_payment_id ON bank_transactions(payment_id);

-- migrations_log
INSERT INTO migrations_log (file_name, notes)
VALUES ('017_missing_indexes.sql',
  'Add missing indexes on all FK columns for performance')
ON CONFLICT (file_name) DO NOTHING;
