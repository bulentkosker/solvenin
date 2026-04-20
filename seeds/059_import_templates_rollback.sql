-- ============================================================
-- M059 ROLLBACK: Import Templates
-- ============================================================
-- DİKKAT: import_templates tablosundaki veriler silinir!
-- Storage bucket'ta dosya varsa bucket silinemez — uyarı verir.
-- ============================================================

BEGIN;

-- 5. migrations_log
DELETE FROM migrations_log WHERE file_name = '059_import_templates.sql';

-- 4. Storage policies + bucket
DROP POLICY IF EXISTS "imports_select" ON storage.objects;
DROP POLICY IF EXISTS "imports_insert" ON storage.objects;
DROP POLICY IF EXISTS "imports_delete" ON storage.objects;

-- Bucket silme — içinde dosya varsa bu satır hata verir (CASCADE yok).
-- Bu durumda önce dosyaları manuel silmeniz gerekir.
DELETE FROM storage.buckets WHERE id = 'imports';

-- 3. data_imports.template_id
DROP INDEX IF EXISTS idx_data_imports_template;
ALTER TABLE data_imports DROP COLUMN IF EXISTS template_id;

-- 2. RLS policies
DROP POLICY IF EXISTS "it_select_policy" ON import_templates;
DROP POLICY IF EXISTS "it_insert_policy" ON import_templates;
DROP POLICY IF EXISTS "it_update_policy" ON import_templates;
DROP POLICY IF EXISTS "it_delete_policy" ON import_templates;

-- 1. Indexes + table
DROP INDEX IF EXISTS idx_it_company;
DROP INDEX IF EXISTS idx_it_system;
DROP INDEX IF EXISTS idx_it_public;
DROP INDEX IF EXISTS idx_it_country;
DROP INDEX IF EXISTS idx_it_bank_identifier;
DROP INDEX IF EXISTS idx_it_usage;
DROP INDEX IF EXISTS idx_it_target_module;
DROP TABLE IF EXISTS import_templates;

COMMIT;
