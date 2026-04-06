-- Data Management Migration — 2026-04-06
CREATE TABLE IF NOT EXISTS data_backups (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  backup_type varchar(30) DEFAULT 'manual',
  file_name varchar(255), file_url text, file_size bigint,
  status varchar(20) DEFAULT 'pending',
  created_by uuid,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS data_imports (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  import_type varchar(50),
  file_name varchar(255),
  total_rows int DEFAULT 0, success_rows int DEFAULT 0, error_rows int DEFAULT 0,
  errors jsonb, status varchar(20) DEFAULT 'pending',
  created_by uuid,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE data_backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY data_backups_policy ON data_backups FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY data_imports_policy ON data_imports FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE INDEX IF NOT EXISTS idx_data_backups_company ON data_backups(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_data_imports_company ON data_imports(company_id, created_at DESC);
