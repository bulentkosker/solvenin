-- ===== PRODUCT vs SERVICE FLAG =====
-- 2026-04-08
-- A new is_service boolean is added (default false) so existing rows
-- remain unaffected. We do NOT reuse the existing products.product_type
-- column because that already classifies items along a different axis
-- (raw_material / finished_good / consumable / by_product / waste).
-- The two flags are orthogonal: a service is_service=true with any
-- product_type, a physical good is is_service=false.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS is_service boolean DEFAULT false;

UPDATE products SET is_service = false WHERE is_service IS NULL;

CREATE INDEX IF NOT EXISTS idx_products_is_service
  ON products(company_id, is_service);
