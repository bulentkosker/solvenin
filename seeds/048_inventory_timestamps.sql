-- 048_inventory_timestamps.sql
-- Add missing created_at / updated_at to inventory_sheet_items + trigger.
-- inventory_sessions and inventory_sheets already have these columns and
-- equivalent BEFORE UPDATE triggers (inv_sessions_touch / inv_sheets_touch),
-- so the ADD COLUMN IF NOT EXISTS statements on those tables are no-ops
-- kept for intent/documentation.

BEGIN;

ALTER TABLE inventory_sheet_items
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

ALTER TABLE inventory_sheet_items
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE inventory_sessions
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE inventory_sheets
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

DROP TRIGGER IF EXISTS inventory_sheet_items_updated_at ON inventory_sheet_items;
CREATE TRIGGER inventory_sheet_items_updated_at
  BEFORE UPDATE ON inventory_sheet_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

INSERT INTO migrations_log (file_name, notes)
VALUES ('048_inventory_timestamps.sql',
  'Add created_at/updated_at to inventory_sheet_items + BEFORE UPDATE trigger')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
