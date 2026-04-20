-- ============================================================
-- M058 ROLLBACK: Bank Statement Import Infrastructure
-- ============================================================
-- Bu script M058'i tamamen geri alır.
-- DİKKAT: data_import_lines tablosundaki veriler silinir!
-- ============================================================

BEGIN;

-- 9. migrations_log
DELETE FROM migrations_log WHERE file_name = '058_bank_statement_import.sql';

-- 8. app_settings
DELETE FROM app_settings WHERE key IN (
  'bank_import_commission_mode',
  'bank_import_tax_mode',
  'bank_import_salary_mode',
  'bank_import_auto_create_contacts',
  'bank_import_duplicate_window_days'
);

-- 7. banks: bik
ALTER TABLE banks DROP COLUMN IF EXISTS bik;

-- 6. employees: tax_number, contact_id
DROP INDEX IF EXISTS idx_employees_tax_number;
ALTER TABLE employees DROP COLUMN IF EXISTS contact_id;
ALTER TABLE employees DROP COLUMN IF EXISTS tax_number;

-- 5. contact_transactions: bank_transaction_id
DROP INDEX IF EXISTS idx_contact_tx_bank_tx_id;
ALTER TABLE contact_transactions DROP COLUMN IF EXISTS bank_transaction_id;

-- 4. payments: bank_transaction_id
DROP INDEX IF EXISTS idx_payments_bank_tx_id;
ALTER TABLE payments DROP COLUMN IF EXISTS bank_transaction_id;

-- 3. data_import_lines (DROP TABLE)
DROP POLICY IF EXISTS "data_import_lines_policy" ON data_import_lines;
DROP INDEX IF EXISTS idx_dil_import_id;
DROP INDEX IF EXISTS idx_dil_company_id;
DROP INDEX IF EXISTS idx_dil_counterparty_bin;
DROP INDEX IF EXISTS idx_dil_transaction_date;
DROP INDEX IF EXISTS idx_dil_external_ref;
DROP TABLE IF EXISTS data_import_lines;

-- 2. data_imports: eklenen kolonları kaldır
ALTER TABLE data_imports
  DROP COLUMN IF EXISTS bank_account_id,
  DROP COLUMN IF EXISTS source,
  DROP COLUMN IF EXISTS period_start,
  DROP COLUMN IF EXISTS period_end,
  DROP COLUMN IF EXISTS opening_balance,
  DROP COLUMN IF EXISTS closing_balance,
  DROP COLUMN IF EXISTS total_debit,
  DROP COLUMN IF EXISTS total_credit,
  DROP COLUMN IF EXISTS raw_data,
  DROP COLUMN IF EXISTS file_url,
  DROP COLUMN IF EXISTS imported_at,
  DROP COLUMN IF EXISTS imported_by,
  DROP COLUMN IF EXISTS deleted_at;

-- 1. bank_transactions: eklenen kolonları ve constraint'leri kaldır
DROP INDEX IF EXISTS idx_bank_tx_external_ref_unique;
DROP INDEX IF EXISTS idx_bank_tx_import_id;
DROP INDEX IF EXISTS idx_bank_tx_counterparty_bin;
DROP INDEX IF EXISTS idx_bank_tx_reconciliation;

ALTER TABLE bank_transactions
  DROP CONSTRAINT IF EXISTS bank_transactions_reconciliation_status_check;

-- source_type CHECK'i orijinaline geri al
ALTER TABLE bank_transactions
  DROP CONSTRAINT IF EXISTS chk_bank_source_type;
ALTER TABLE bank_transactions
  ADD CONSTRAINT chk_bank_source_type
  CHECK (source_type IN (
    'sales_order', 'purchase_order', 'payment', 'manual', 'opening', 'transfer'
  ));

ALTER TABLE bank_transactions
  DROP COLUMN IF EXISTS import_id,
  DROP COLUMN IF EXISTS reconciliation_status,
  DROP COLUMN IF EXISTS counterparty_bin,
  DROP COLUMN IF EXISTS knp_code,
  DROP COLUMN IF EXISTS document_number,
  DROP COLUMN IF EXISTS external_reference,
  DROP COLUMN IF EXISTS value_date;

COMMIT;
