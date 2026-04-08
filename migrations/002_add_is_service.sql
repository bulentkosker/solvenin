-- Migration: 002_add_is_service
-- Description: Adds is_service boolean to products for product/service split
-- Backward Compatible: YES (default false, existing rows untouched)
-- Rollback:
--   DROP INDEX IF EXISTS idx_products_is_service;
--   ALTER TABLE products DROP COLUMN IF EXISTS is_service;

-- UP
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS is_service boolean DEFAULT false;

UPDATE products SET is_service = false WHERE is_service IS NULL;

CREATE INDEX IF NOT EXISTS idx_products_is_service
  ON products(company_id, is_service);

INSERT INTO migrations_log (file_name, notes)
VALUES ('002_add_is_service.sql', 'Add is_service boolean to products')
ON CONFLICT (file_name) DO NOTHING;
