-- ============================================================
-- M058: Bank Statement Import Infrastructure
-- ============================================================
-- Bank statement import (Halyk, BCC, etc.) altyapısı
-- - bank_transactions: import referansı, BIN, KNP, belge no vb.
-- - data_imports: bank_account, period, balance bilgileri
-- - data_import_lines: parse edilmiş her satır (review için)
-- - payments, contact_transactions: bank_transaction_id FK
-- - employees: BIN + contact_id (maaş eşleştirme)
-- - banks: bik (KZ için)
-- - app_settings: import mode ayarları
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────
-- 1. BANK_TRANSACTIONS genişletmeleri
-- ──────────────────────────────────────────────────────────
ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS import_id UUID REFERENCES data_imports(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reconciliation_status VARCHAR(20) DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS counterparty_bin VARCHAR(20),
  ADD COLUMN IF NOT EXISTS knp_code VARCHAR(10),
  ADD COLUMN IF NOT EXISTS document_number VARCHAR(50),
  ADD COLUMN IF NOT EXISTS external_reference VARCHAR(100),
  ADD COLUMN IF NOT EXISTS value_date DATE;

-- reconciliation_status CHECK
ALTER TABLE bank_transactions
  DROP CONSTRAINT IF EXISTS bank_transactions_reconciliation_status_check;
ALTER TABLE bank_transactions
  ADD CONSTRAINT bank_transactions_reconciliation_status_check
  CHECK (reconciliation_status IN ('manual', 'unmatched', 'matched', 'confirmed'));

-- source_type CHECK — mevcut: sales_order, purchase_order, payment, manual, opening, transfer
-- eklenen: bank_import, own_transfer
ALTER TABLE bank_transactions
  DROP CONSTRAINT IF EXISTS chk_bank_source_type;
ALTER TABLE bank_transactions
  ADD CONSTRAINT chk_bank_source_type
  CHECK (source_type IN (
    'sales_order', 'purchase_order', 'payment', 'manual', 'opening', 'transfer',
    'bank_import', 'own_transfer'
  ));

-- Unique index: aynı hesapta aynı external_reference iki kez import edilmesin
CREATE UNIQUE INDEX IF NOT EXISTS idx_bank_tx_external_ref_unique
  ON bank_transactions(account_id, external_reference)
  WHERE external_reference IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_bank_tx_import_id
  ON bank_transactions(import_id) WHERE import_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bank_tx_counterparty_bin
  ON bank_transactions(counterparty_bin) WHERE counterparty_bin IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bank_tx_reconciliation
  ON bank_transactions(company_id, reconciliation_status) WHERE deleted_at IS NULL;

COMMENT ON COLUMN bank_transactions.external_reference IS 'Banka dış referansı (Внешний референс / NT code). Duplicate önleme için unique.';
COMMENT ON COLUMN bank_transactions.reconciliation_status IS 'manual=elle girilen, unmatched=import eşleşmedi, matched=eşleşti, confirmed=onaylandı';
COMMENT ON COLUMN bank_transactions.knp_code IS 'KNP ödeme kodu (KZ spesifik, örn 710, 859, 911)';
COMMENT ON COLUMN bank_transactions.value_date IS 'Valör tarihi — transaction_date''den farklı olabilir';

-- ──────────────────────────────────────────────────────────
-- 2. DATA_IMPORTS genişletmeleri
-- ──────────────────────────────────────────────────────────
ALTER TABLE data_imports
  ADD COLUMN IF NOT EXISTS bank_account_id UUID REFERENCES bank_accounts(id),
  ADD COLUMN IF NOT EXISTS source VARCHAR(30),
  ADD COLUMN IF NOT EXISTS period_start DATE,
  ADD COLUMN IF NOT EXISTS period_end DATE,
  ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS closing_balance NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS total_debit NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS total_credit NUMERIC(18,2),
  ADD COLUMN IF NOT EXISTS raw_data JSONB,
  ADD COLUMN IF NOT EXISTS file_url TEXT,
  ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS imported_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN data_imports.source IS 'halyk, bcc, kaspi, manual, csv';

-- ──────────────────────────────────────────────────────────
-- 3. DATA_IMPORT_LINES (yeni tablo — parse edilmiş satırlar)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS data_import_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  import_id UUID NOT NULL REFERENCES data_imports(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES companies(id),
  line_number INT NOT NULL,

  -- Parse edilmiş veri
  transaction_date DATE NOT NULL,
  transaction_time TIME,
  document_number VARCHAR(50),
  debit NUMERIC(18,2) DEFAULT 0,
  credit NUMERIC(18,2) DEFAULT 0,
  counterparty_name TEXT,
  counterparty_bin VARCHAR(20),
  counterparty_iban VARCHAR(34),
  counterparty_bik VARCHAR(20),
  payment_details TEXT,
  knp_code VARCHAR(10),
  external_reference VARCHAR(100),

  -- Eşleştirme
  match_type VARCHAR(20) DEFAULT 'unmatched',
  matched_contact_id UUID REFERENCES contacts(id),
  matched_account_id UUID REFERENCES chart_of_accounts(id),
  matched_employee_id UUID REFERENCES employees(id),
  target_bank_account_id UUID REFERENCES bank_accounts(id),

  -- Durum
  is_duplicate BOOLEAN DEFAULT FALSE,
  duplicate_of_bank_tx_id UUID REFERENCES bank_transactions(id),
  is_confirmed BOOLEAN DEFAULT FALSE,
  is_skipped BOOLEAN DEFAULT FALSE,
  notes TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT dil_match_type_check
    CHECK (match_type IN ('unmatched', 'contact', 'expense_account', 'employee', 'own_transfer', 'duplicate', 'skipped'))
);

CREATE INDEX idx_dil_import_id ON data_import_lines(import_id);
CREATE INDEX idx_dil_company_id ON data_import_lines(company_id);
CREATE INDEX idx_dil_counterparty_bin ON data_import_lines(counterparty_bin) WHERE counterparty_bin IS NOT NULL;
CREATE INDEX idx_dil_transaction_date ON data_import_lines(transaction_date);
CREATE INDEX idx_dil_external_ref ON data_import_lines(external_reference) WHERE external_reference IS NOT NULL;

ALTER TABLE data_import_lines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "data_import_lines_policy" ON data_import_lines
  FOR ALL TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (company_id = ANY(get_my_company_ids()));

-- ──────────────────────────────────────────────────────────
-- 4. PAYMENTS: bank_transaction_id FK
-- ──────────────────────────────────────────────────────────
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS bank_transaction_id UUID REFERENCES bank_transactions(id);

CREATE INDEX IF NOT EXISTS idx_payments_bank_tx_id
  ON payments(bank_transaction_id) WHERE bank_transaction_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────
-- 5. CONTACT_TRANSACTIONS: bank_transaction_id FK
-- ──────────────────────────────────────────────────────────
ALTER TABLE contact_transactions
  ADD COLUMN IF NOT EXISTS bank_transaction_id UUID REFERENCES bank_transactions(id);

CREATE INDEX IF NOT EXISTS idx_contact_tx_bank_tx_id
  ON contact_transactions(bank_transaction_id) WHERE bank_transaction_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────
-- 6. EMPLOYEES: tax_number (BIN/IIN) + contact_id
-- ──────────────────────────────────────────────────────────
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS tax_number VARCHAR(20),
  ADD COLUMN IF NOT EXISTS contact_id UUID REFERENCES contacts(id);

CREATE INDEX IF NOT EXISTS idx_employees_tax_number
  ON employees(tax_number) WHERE tax_number IS NOT NULL;

-- ──────────────────────────────────────────────────────────
-- 7. BANKS: bik kolonu (KZ için)
-- ──────────────────────────────────────────────────────────
ALTER TABLE banks
  ADD COLUMN IF NOT EXISTS bik VARCHAR(20);

-- ──────────────────────────────────────────────────────────
-- 8. APP_SETTINGS: import mode ayarları
-- ──────────────────────────────────────────────────────────
INSERT INTO app_settings (key, value, is_secret) VALUES
  ('bank_import_commission_mode', 'expense_account', false),
  ('bank_import_tax_mode', 'expense_account', false),
  ('bank_import_salary_mode', 'employee', false),
  ('bank_import_auto_create_contacts', 'true', false),
  ('bank_import_duplicate_window_days', '3', false)
ON CONFLICT (key) DO NOTHING;

-- ──────────────────────────────────────────────────────────
-- 9. Migrations log
-- ──────────────────────────────────────────────────────────
INSERT INTO migrations_log (file_name, notes)
VALUES ('058_bank_statement_import.sql',
  'Bank statement import altyapısı: bank_transactions genişletme, data_import_lines, payments/contact_transactions FK, employees BIN, banks BIK, app_settings')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
