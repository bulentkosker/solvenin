-- ============================================================
-- M059: Import Templates (Universal Parser System)
-- ============================================================
-- Her banka/kasa/format için template tabanlı parser sistemi.
-- System templates (onaylanmış), community (paylaşılan), private (kullanıcı).
-- AI tarafından oluşturulan template'ler buraya kaydedilir.
-- target_module: bank_statement, cash_register (genişletilebilir)
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────
-- 1. import_templates tablosu
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS import_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Sahiplik
  company_id UUID REFERENCES companies(id),  -- NULL = system template
  created_by UUID REFERENCES auth.users(id),

  -- Kimlik
  name TEXT NOT NULL,
  description TEXT,
  country_code VARCHAR(2),
  language_code VARCHAR(5),

  -- Banka tanıma
  bank_name TEXT,
  bank_identifier TEXT,

  -- Format
  file_format VARCHAR(10) NOT NULL,

  -- Hedef modül
  target_module VARCHAR(30) NOT NULL DEFAULT 'bank_statement',

  -- Auto-detection
  detection_rules JSONB,

  -- Locale
  locale JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Parser config
  parser_config JSONB NOT NULL,
  metadata_config JSONB,

  -- Sınıflandırma
  is_system BOOLEAN DEFAULT FALSE,
  is_public BOOLEAN DEFAULT FALSE,
  is_ai_generated BOOLEAN DEFAULT FALSE,

  -- Kullanım istatistiği
  usage_count INT DEFAULT 0,
  success_count INT DEFAULT 0,
  last_used_at TIMESTAMPTZ,

  -- Versiyonlama
  version INT DEFAULT 1,
  parent_template_id UUID REFERENCES import_templates(id),

  -- Standart alanlar
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,

  CONSTRAINT it_file_format_check
    CHECK (file_format IN ('pdf', 'xlsx', 'xls', 'csv', 'txt')),
  CONSTRAINT it_country_format_check
    CHECK (country_code IS NULL OR length(country_code) = 2),
  CONSTRAINT it_target_module_check
    CHECK (target_module IN ('bank_statement', 'cash_register'))
);

CREATE INDEX idx_it_company ON import_templates(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_it_system ON import_templates(is_system) WHERE is_system = TRUE AND deleted_at IS NULL;
CREATE INDEX idx_it_public ON import_templates(is_public) WHERE is_public = TRUE AND deleted_at IS NULL;
CREATE INDEX idx_it_country ON import_templates(country_code) WHERE deleted_at IS NULL;
CREATE INDEX idx_it_bank_identifier ON import_templates(bank_identifier) WHERE deleted_at IS NULL;
CREATE INDEX idx_it_usage ON import_templates(usage_count DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_it_target_module ON import_templates(target_module) WHERE deleted_at IS NULL;

COMMENT ON COLUMN import_templates.parser_config IS 'JSONB — field extraction rules. Her field için { method, pattern/position, transform } yapısı.';
COMMENT ON COLUMN import_templates.locale IS 'Tarih/sayı/para formatları. { decimal_separator, thousand_separator, date_format, currency, timezone }';
COMMENT ON COLUMN import_templates.detection_rules IS 'Yüklenen dosyanın bu template ile eşleşip eşleşmediğini tespit. { header_contains, bank_identifier_pattern, filename_pattern }';
COMMENT ON COLUMN import_templates.target_module IS 'bank_statement = banka ekstresi, cash_register = kasa fişi';

-- ──────────────────────────────────────────────────────────
-- 2. RLS
-- ──────────────────────────────────────────────────────────
ALTER TABLE import_templates ENABLE ROW LEVEL SECURITY;

-- SELECT: system + public + kendi company
CREATE POLICY "it_select_policy" ON import_templates
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL AND (
      is_system = TRUE
      OR is_public = TRUE
      OR company_id = ANY(get_my_company_ids())
    )
  );

-- INSERT: sadece kendi company, is_system = FALSE zorunlu
CREATE POLICY "it_insert_policy" ON import_templates
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = ANY(get_my_company_ids())
    AND is_system = FALSE
  );

-- UPDATE: sadece kendi template
CREATE POLICY "it_update_policy" ON import_templates
  FOR UPDATE TO authenticated
  USING (company_id = ANY(get_my_company_ids()))
  WITH CHECK (
    company_id = ANY(get_my_company_ids())
    AND is_system = FALSE
  );

-- DELETE: sadece kendi template
CREATE POLICY "it_delete_policy" ON import_templates
  FOR DELETE TO authenticated
  USING (company_id = ANY(get_my_company_ids()));

-- ──────────────────────────────────────────────────────────
-- 3. data_imports → template referansı
-- ──────────────────────────────────────────────────────────
ALTER TABLE data_imports
  ADD COLUMN IF NOT EXISTS template_id UUID REFERENCES import_templates(id);

CREATE INDEX IF NOT EXISTS idx_data_imports_template
  ON data_imports(template_id) WHERE template_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────
-- 4. Storage bucket: imports
-- ──────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'imports',
  'imports',
  false,
  10485760,
  ARRAY['application/pdf', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel', 'text/csv', 'text/plain']
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: dosya yolu = {company_id}/{import_id}/{filename}
CREATE POLICY "imports_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'imports'
    AND (storage.foldername(name))[1]::uuid = ANY(get_my_company_ids())
  );

CREATE POLICY "imports_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'imports'
    AND (storage.foldername(name))[1]::uuid = ANY(get_my_company_ids())
  );

CREATE POLICY "imports_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'imports'
    AND (storage.foldername(name))[1]::uuid = ANY(get_my_company_ids())
  );

-- ──────────────────────────────────────────────────────────
-- 5. Migrations log
-- ──────────────────────────────────────────────────────────
INSERT INTO migrations_log (file_name, notes)
VALUES ('059_import_templates.sql',
  'Universal import template sistemi (banka + kasa): import_templates tablosu, storage bucket, data_imports.template_id FK')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
