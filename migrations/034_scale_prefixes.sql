-- Migration 034: Replace single prefix/content with 3 prefix arrays
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS scale_prefix_weight text[] DEFAULT ARRAY['20','21'],
  ADD COLUMN IF NOT EXISTS scale_prefix_quantity text[] DEFAULT ARRAY['22','23'],
  ADD COLUMN IF NOT EXISTS scale_prefix_price text[] DEFAULT ARRAY['28','29'];

ALTER TABLE companies DROP COLUMN IF EXISTS weight_barcode_content;
ALTER TABLE companies DROP COLUMN IF EXISTS weight_barcode_prefix;

INSERT INTO migrations_log (file_name, notes)
VALUES ('034_scale_prefixes.sql', 'Replace scale barcode single prefix/content with 3 prefix arrays per content type')
ON CONFLICT (file_name) DO NOTHING;
