-- ============================================================
-- M073: companies.default_salary_account_id + default_advance_account_id
-- ============================================================
-- Maaş ve Avans kategorileri kasa/banka modal'ında artık hesap sormuyor —
-- şirket bazlı varsayılan hesap Settings'ten seçiliyor, kayıt anında
-- otomatik dolduruluyor. Per-company çünkü her şirketin kendi chart of
-- accounts'u var; global app_settings burada işe yaramaz.
-- ============================================================

BEGIN;

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS default_salary_account_id UUID
    REFERENCES chart_of_accounts(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS default_advance_account_id UUID
    REFERENCES chart_of_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_companies_default_salary_account
  ON companies(default_salary_account_id) WHERE default_salary_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_default_advance_account
  ON companies(default_advance_account_id) WHERE default_advance_account_id IS NOT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('073_company_default_payroll_accounts.sql',
  'companies: default_salary_account_id + default_advance_account_id (FK to chart_of_accounts) — Settings UI sets per-company defaults, cashbank Salary/Advance categories use them automatically.');

COMMIT;
