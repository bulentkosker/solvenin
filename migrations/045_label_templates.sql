-- Migration 045: Universal Label Maker — template storage per customer

CREATE TABLE IF NOT EXISTS label_templates (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES contacts(id) ON DELETE SET NULL,
  name text NOT NULL,
  label_type varchar(20),
  template_data jsonb NOT NULL DEFAULT '{}',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_label_templates_company_id ON label_templates(company_id);
CREATE INDEX IF NOT EXISTS idx_label_templates_contact_id ON label_templates(contact_id);

ALTER TABLE label_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS label_templates_select ON label_templates;
DROP POLICY IF EXISTS label_templates_insert ON label_templates;
DROP POLICY IF EXISTS label_templates_update ON label_templates;
DROP POLICY IF EXISTS label_templates_delete ON label_templates;

CREATE POLICY label_templates_select ON label_templates FOR SELECT
  USING (company_id = ANY (get_my_company_ids()));
CREATE POLICY label_templates_insert ON label_templates FOR INSERT
  WITH CHECK (company_id = ANY (get_my_company_ids()));
CREATE POLICY label_templates_update ON label_templates FOR UPDATE
  USING (company_id = ANY (get_my_company_ids()))
  WITH CHECK (company_id = ANY (get_my_company_ids()));
CREATE POLICY label_templates_delete ON label_templates FOR DELETE
  USING (company_id = ANY (get_my_company_ids()));

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION _label_templates_touch() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS label_templates_touch ON label_templates;
CREATE TRIGGER label_templates_touch BEFORE UPDATE ON label_templates
  FOR EACH ROW EXECUTE FUNCTION _label_templates_touch();

INSERT INTO migrations_log (file_name, notes)
VALUES ('045_label_templates.sql', 'Universal label maker — per-customer templates stored as jsonb')
ON CONFLICT (file_name) DO NOTHING;
