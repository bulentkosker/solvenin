-- ============================================================
-- M059 ROLLBACK: Bank Import Templates
-- ============================================================
-- DİKKAT: bank_import_templates tablosundaki veriler silinir!
-- Storage bucket'ta dosya varsa bucket silinemez — uyarı verir.
-- ============================================================

BEGIN;

-- 5. migrations_log
DELETE FROM migrations_log WHERE file_name = '059_bank_import_templates.sql';

-- 4. Storage policies + bucket
DROP POLICY IF EXISTS "bank_imports_select" ON storage.objects;
DROP POLICY IF EXISTS "bank_imports_insert" ON storage.objects;
DROP POLICY IF EXISTS "bank_imports_delete" ON storage.objects;

-- Bucket silme — içinde dosya varsa bu satır hata verir (CASCADE yok).
-- Bu durumda önce dosyaları manuel silmeniz gerekir.
DELETE FROM storage.buckets WHERE id = 'bank-imports';

-- 3. data_imports.template_id
DROP INDEX IF EXISTS idx_data_imports_template;
ALTER TABLE data_imports DROP COLUMN IF EXISTS template_id;

-- 2. RLS policies
DROP POLICY IF EXISTS "bit_select_policy" ON bank_import_templates;
DROP POLICY IF EXISTS "bit_insert_policy" ON bank_import_templates;
DROP POLICY IF EXISTS "bit_update_policy" ON bank_import_templates;
DROP POLICY IF EXISTS "bit_delete_policy" ON bank_import_templates;

-- 1. Indexes + table
DROP INDEX IF EXISTS idx_bit_company;
DROP INDEX IF EXISTS idx_bit_system;
DROP INDEX IF EXISTS idx_bit_public;
DROP INDEX IF EXISTS idx_bit_country;
DROP INDEX IF EXISTS idx_bit_bank_identifier;
DROP INDEX IF EXISTS idx_bit_usage;
DROP TABLE IF EXISTS bank_import_templates;

COMMIT;
