-- 047_unique_constraints.sql
-- Add partial unique indexes on critical fields to prevent duplicate data.
-- Partial WHERE clauses keep soft-deleted / empty-string rows from blocking reuse.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode_company
  ON products(company_id, barcode)
  WHERE barcode IS NOT NULL AND barcode <> '' AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_sku_company
  ON products(company_id, sku)
  WHERE sku IS NOT NULL AND sku <> '' AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_products_plu_company
  ON products(company_id, plu_code)
  WHERE plu_code IS NOT NULL AND plu_code <> '' AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_orders_number_company
  ON sales_orders(company_id, order_number)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_orders_number_company
  ON purchase_orders(company_id, order_number)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_warehouses_name_company
  ON warehouses(company_id, name)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_cash_registers_name_company
  ON cash_registers(company_id, name)
  WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rates_name_company
  ON tax_rates(company_id, name)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_name_parent_company
  ON categories(company_id, COALESCE(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), name)
  WHERE deleted_at IS NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('047_unique_constraints.sql',
  'Unique indexes on barcode/sku/plu, order numbers, warehouse/register/tax/category names')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
