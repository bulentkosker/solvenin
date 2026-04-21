-- ============================================================
-- M065: data_import_lines — Step 3 alanları
-- ============================================================
-- Step 3 eşleştirme UI için eksik alanlar:
--   suggested_contact_id  — 0.80 <= fuzzy < 0.95 önerileri
--   suggestion_reason     — commission_keyword / tax_keyword / salary_pattern
--   confidence            — match skoru (0..1)
--   auto_bin_update       — fuzzy eşleşen carinin BIN'i boşsa, eklenecek BIN
--   match_type'a 'suggestion' eklendi
-- ============================================================

BEGIN;

ALTER TABLE data_import_lines
  ADD COLUMN IF NOT EXISTS suggested_contact_id UUID REFERENCES contacts(id),
  ADD COLUMN IF NOT EXISTS suggestion_reason TEXT,
  ADD COLUMN IF NOT EXISTS confidence NUMERIC(4,3),
  ADD COLUMN IF NOT EXISTS auto_bin_update VARCHAR(20);

-- match_type constraint — 'suggestion' eklendi
ALTER TABLE data_import_lines
  DROP CONSTRAINT IF EXISTS dil_match_type_check;
ALTER TABLE data_import_lines
  ADD CONSTRAINT dil_match_type_check
  CHECK (match_type IN (
    'unmatched', 'contact', 'suggestion', 'expense_account',
    'employee', 'own_transfer', 'duplicate', 'skipped'
  ));

CREATE INDEX IF NOT EXISTS idx_dil_suggested_contact
  ON data_import_lines(suggested_contact_id)
  WHERE suggested_contact_id IS NOT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('065_data_import_lines_step3.sql',
  'Step 3 eşleştirme alanları: suggested_contact_id, suggestion_reason, confidence, auto_bin_update + match_type ''suggestion''');

COMMIT;
