-- ============================================================
-- Migration: POS button groups + receipt header fields
-- ============================================================

-- 1. Button groups table
CREATE TABLE IF NOT EXISTS pos_button_groups (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  register_id uuid REFERENCES cash_registers(id) ON DELETE SET NULL,
  name text NOT NULL,
  color text DEFAULT '#3B82F6',
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pos_button_groups_company ON pos_button_groups(company_id);

ALTER TABLE pos_button_groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pos_button_groups_select ON pos_button_groups;
CREATE POLICY pos_button_groups_select ON pos_button_groups
  FOR SELECT USING (company_id = ANY(get_my_company_ids()));

DROP POLICY IF EXISTS pos_button_groups_insert ON pos_button_groups;
CREATE POLICY pos_button_groups_insert ON pos_button_groups
  FOR INSERT WITH CHECK (company_id = ANY(get_my_company_ids()));

DROP POLICY IF EXISTS pos_button_groups_update ON pos_button_groups;
CREATE POLICY pos_button_groups_update ON pos_button_groups
  FOR UPDATE USING (company_id = ANY(get_my_company_ids()));

DROP POLICY IF EXISTS pos_button_groups_delete ON pos_button_groups;
CREATE POLICY pos_button_groups_delete ON pos_button_groups
  FOR DELETE USING (company_id = ANY(get_my_company_ids()));

-- 2. group_id on pos_quick_buttons
ALTER TABLE pos_quick_buttons
  ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES pos_button_groups(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_pos_quick_buttons_group ON pos_quick_buttons(group_id);

-- 3. Migrate existing buttons: create default "Genel" group per company
DO $$
DECLARE
  c RECORD;
  new_group_id uuid;
BEGIN
  FOR c IN
    SELECT DISTINCT company_id
    FROM pos_quick_buttons
    WHERE group_id IS NULL AND is_active = true
  LOOP
    INSERT INTO pos_button_groups (company_id, name, color, sort_order)
    VALUES (c.company_id, 'Genel', '#3B82F6', 0)
    RETURNING id INTO new_group_id;

    UPDATE pos_quick_buttons
       SET group_id = new_group_id
     WHERE company_id = c.company_id AND group_id IS NULL;
  END LOOP;
END $$;
