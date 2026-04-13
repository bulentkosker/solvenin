-- Migration 031: Add allow_negative_stock to companies
ALTER TABLE companies ADD COLUMN IF NOT EXISTS allow_negative_stock boolean DEFAULT true;

INSERT INTO migrations_log (file_name, notes)
VALUES ('031_allow_negative_stock.sql', 'Add allow_negative_stock boolean to companies')
ON CONFLICT (file_name) DO NOTHING;
