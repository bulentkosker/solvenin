-- 061_rls_financial_tables.sql
-- Enable RLS on banks, bank_accounts, cash_registers, cash_transactions.
-- These tables had NO RLS — any authenticated user could see all companies' data.

BEGIN;

ALTER TABLE banks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "banks_company_access" ON banks
  FOR ALL TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (company_id = ANY(get_my_company_ids()));

ALTER TABLE bank_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bank_accounts_company_access" ON bank_accounts
  FOR ALL TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (company_id = ANY(get_my_company_ids()));

ALTER TABLE cash_registers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cash_registers_company_access" ON cash_registers
  FOR ALL TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (company_id = ANY(get_my_company_ids()));

ALTER TABLE cash_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cash_transactions_company_access" ON cash_transactions
  FOR ALL TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (company_id = ANY(get_my_company_ids()));

INSERT INTO migrations_log (file_name, notes)
VALUES ('061_rls_financial_tables.sql',
  'Enable RLS on banks, bank_accounts, cash_registers, cash_transactions — were completely unprotected')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
