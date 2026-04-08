-- Migration: 013_vat_system
-- Description: Per-category and per-product VAT rate resolution
-- Backward Compatible: YES (new columns + RPC; only deactivates withholding rows)
-- Rollback:
--   DROP FUNCTION IF EXISTS get_product_tax_rate(uuid, uuid);
--   ALTER TABLE products DROP COLUMN tax_source, tax_rate_id, tax_rate_override;
--   ALTER TABLE categories DROP COLUMN tax_rate_id, tax_rate_override;
--   ALTER TABLE companies DROP COLUMN default_tax_rate_id;
--   ALTER TABLE sales_order_items DROP COLUMN tax_amount;
--   ALTER TABLE purchase_order_items DROP COLUMN tax_amount;

-- ============================================================================
-- 1. Categories: per-category VAT rate (link or override value)
-- ============================================================================
ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS tax_rate_id uuid REFERENCES tax_rates(id),
  ADD COLUMN IF NOT EXISTS tax_rate_override decimal(5,2);

CREATE INDEX IF NOT EXISTS idx_categories_tax_rate
  ON categories(company_id, tax_rate_id);

-- ============================================================================
-- 2. Products: tax source (category | fixed | manual) + override link
-- ============================================================================
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS tax_source varchar(20) DEFAULT 'category',
  ADD COLUMN IF NOT EXISTS tax_rate_id uuid REFERENCES tax_rates(id),
  ADD COLUMN IF NOT EXISTS tax_rate_override decimal(5,2);

UPDATE products SET tax_source = 'category' WHERE tax_source IS NULL;

CREATE INDEX IF NOT EXISTS idx_products_tax_source
  ON products(company_id, tax_source);

-- ============================================================================
-- 3. Order item tax amount
-- (sales_order_items.tax_rate_value already exists; we keep it as the rate)
-- ============================================================================
ALTER TABLE sales_order_items
  ADD COLUMN IF NOT EXISTS tax_amount decimal(18,2) DEFAULT 0;

ALTER TABLE purchase_order_items
  ADD COLUMN IF NOT EXISTS tax_amount decimal(18,2) DEFAULT 0;

-- ============================================================================
-- 4. Company-wide default VAT rate (for tax_source='fixed' and the
--    fallback when category has no rate)
-- ============================================================================
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS default_tax_rate_id uuid REFERENCES tax_rates(id);

-- ============================================================================
-- 5. Stopaj cleanup — withholding tax should not appear in sales/purchase
--    tax dropdowns. Mark inactive but DON'T delete (audit trail).
-- ============================================================================
UPDATE tax_rates
SET is_active = false
WHERE (type ILIKE '%stopaj%' OR type ILIKE '%withholding%' OR name ILIKE '%stopaj%')
  AND is_active = true;

-- ============================================================================
-- 6. RPC: resolve effective tax rate for a product
--    Falls back through:
--      tax_source='manual'   → product.tax_rate_id rate, else override, else 0
--      tax_source='fixed'    → company.default_tax_rate_id rate, else 0
--      tax_source='category' → category.tax_rate_id rate, else override
--                               (and if no category, fall back to company default)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_product_tax_rate(
  p_product_id uuid,
  p_company_id uuid
) RETURNS decimal
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_product products%ROWTYPE;
  v_category categories%ROWTYPE;
  v_tax_rate decimal := 0;
BEGIN
  SELECT * INTO v_product
  FROM products
  WHERE id = p_product_id AND company_id = p_company_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  CASE COALESCE(v_product.tax_source, 'category')
    WHEN 'manual' THEN
      IF v_product.tax_rate_id IS NOT NULL THEN
        SELECT rate INTO v_tax_rate FROM tax_rates WHERE id = v_product.tax_rate_id;
      ELSE
        v_tax_rate := COALESCE(v_product.tax_rate_override, 0);
      END IF;

    WHEN 'fixed' THEN
      SELECT COALESCE(tr.rate, 0) INTO v_tax_rate
      FROM companies c
      LEFT JOIN tax_rates tr ON tr.id = c.default_tax_rate_id
      WHERE c.id = p_company_id;

    ELSE -- 'category'
      IF v_product.category_id IS NOT NULL THEN
        SELECT * INTO v_category FROM categories WHERE id = v_product.category_id;
        IF FOUND THEN
          IF v_category.tax_rate_id IS NOT NULL THEN
            SELECT rate INTO v_tax_rate FROM tax_rates WHERE id = v_category.tax_rate_id;
          ELSE
            v_tax_rate := COALESCE(v_category.tax_rate_override, 0);
          END IF;
        END IF;
      END IF;
      -- Final fallback to company default
      IF COALESCE(v_tax_rate, 0) = 0 THEN
        SELECT COALESCE(tr.rate, 0) INTO v_tax_rate
        FROM companies c
        LEFT JOIN tax_rates tr ON tr.id = c.default_tax_rate_id
        WHERE c.id = p_company_id;
      END IF;
  END CASE;

  RETURN COALESCE(v_tax_rate, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_product_tax_rate(uuid, uuid) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('013_vat_system.sql', 'Per-category & per-product VAT resolution + stopaj deactivation')
ON CONFLICT (file_name) DO NOTHING;
