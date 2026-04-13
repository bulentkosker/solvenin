-- Migration 032: Stock settings columns
ALTER TABLE companies ADD COLUMN IF NOT EXISTS low_stock_threshold integer DEFAULT 10;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS default_barcode_format varchar(20) DEFAULT 'EAN-13';

INSERT INTO migrations_log (file_name, notes)
VALUES ('032_stock_settings.sql', 'Add low_stock_threshold and default_barcode_format to companies')
ON CONFLICT (file_name) DO NOTHING;
