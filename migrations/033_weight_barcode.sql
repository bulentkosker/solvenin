-- Migration 033: Weight barcode settings + product PLU
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS weight_barcode_format varchar(10) DEFAULT 'EAN-13',
  ADD COLUMN IF NOT EXISTS weight_barcode_prefix varchar(2) DEFAULT '20',
  ADD COLUMN IF NOT EXISTS weight_barcode_content varchar(10) DEFAULT 'price',
  ADD COLUMN IF NOT EXISTS weight_barcode_plu_length integer DEFAULT 5,
  ADD COLUMN IF NOT EXISTS weight_barcode_decimals integer DEFAULT 3;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS is_weight_product boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS plu_code varchar(5);

CREATE INDEX IF NOT EXISTS idx_products_plu_code ON products(plu_code) WHERE plu_code IS NOT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('033_weight_barcode.sql', 'Weight barcode settings on companies + is_weight_product/plu_code on products')
ON CONFLICT (file_name) DO NOTHING;
