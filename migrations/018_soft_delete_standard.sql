-- ============================================================
-- Migration 018: Standardize soft delete across all tables
-- Standard: deleted_at timestamptz (NULL = active)
-- ============================================================

-- ============================================================
-- STEP 1: Add deleted_at to tables that only have is_active
-- ============================================================

-- warehouses
ALTER TABLE warehouses ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE warehouses ADD COLUMN IF NOT EXISTS deleted_by uuid;
UPDATE warehouses SET deleted_at = now() WHERE is_active = false AND deleted_at IS NULL;

-- pos_quick_buttons
ALTER TABLE pos_quick_buttons ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
UPDATE pos_quick_buttons SET deleted_at = now() WHERE is_active = false AND deleted_at IS NULL;

-- company_modules (is_active here means "enabled", not soft delete — skip)

-- ============================================================
-- STEP 2: Add deleted_at to important tables missing both
-- ============================================================

ALTER TABLE payments ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE shipments ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE chart_of_accounts ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE tax_rates ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE crm_opportunities ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE crm_quotes ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE production_orders ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE projects ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE equipment ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE work_orders ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE pos_sessions ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE cash_transactions ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

-- Migrate is_active=false where both columns exist on these tables
DO $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'categories','shipments','crm_opportunities','crm_quotes',
      'production_orders','projects','tasks','equipment','work_orders',
      'pos_sessions','tax_rates','chart_of_accounts'
    ])
  LOOP
    BEGIN
      EXECUTE format(
        'UPDATE %I SET deleted_at = now() WHERE is_active = false AND deleted_at IS NULL',
        tbl
      );
    EXCEPTION WHEN undefined_column THEN
      -- table doesn't have is_active, skip
      NULL;
    END;
  END LOOP;
END $$;

-- ============================================================
-- STEP 3: Add partial indexes on deleted_at for performance
-- ============================================================

DO $$
DECLARE
  tbl text;
BEGIN
  FOR tbl IN
    SELECT DISTINCT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'deleted_at'
      AND table_name NOT LIKE '_tmp%'
  LOOP
    BEGIN
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS idx_%s_deleted_at ON %I(deleted_at) WHERE deleted_at IS NOT NULL',
        tbl, tbl
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;

-- ============================================================
-- STEP 4: Ensure key RLS policies check deleted_at IS NULL
-- Only update policies that currently filter by is_active
-- Using get_my_company_ids() SECURITY DEFINER pattern
-- ============================================================

-- products
DROP POLICY IF EXISTS "products_company_read" ON products;
CREATE POLICY "products_company_read" ON products
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- contacts
DROP POLICY IF EXISTS "contacts_company_read" ON contacts;
CREATE POLICY "contacts_company_read" ON contacts
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- sales_orders
DROP POLICY IF EXISTS "sales_orders_company_read" ON sales_orders;
CREATE POLICY "sales_orders_company_read" ON sales_orders
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- purchase_orders
DROP POLICY IF EXISTS "purchase_orders_company_read" ON purchase_orders;
CREATE POLICY "purchase_orders_company_read" ON purchase_orders
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- stock_movements
DROP POLICY IF EXISTS "stock_movements_company_read" ON stock_movements;
CREATE POLICY "stock_movements_company_read" ON stock_movements
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- warehouses
DROP POLICY IF EXISTS "warehouses_company_read" ON warehouses;
CREATE POLICY "warehouses_company_read" ON warehouses
  FOR SELECT USING (
    company_id = ANY(get_my_company_ids())
    AND deleted_at IS NULL
  );

-- ============================================================
-- STEP 5: migrations_log
-- ============================================================

INSERT INTO migrations_log (file_name, notes)
VALUES ('018_soft_delete_standard.sql',
  'Standardize soft delete: added deleted_at to 18 tables, migrated is_active=false, partial indexes, updated RLS policies')
ON CONFLICT (file_name) DO NOTHING;
