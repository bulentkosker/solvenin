-- ============================================================
-- Tax Rates Templates — Migration
-- Run this in Supabase SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS tax_rates_templates (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  country_code varchar(5) NOT NULL,
  tax_name varchar(100) NOT NULL,
  tax_name_local varchar(100) NOT NULL,
  rate decimal(5,2) NOT NULL,
  tax_type varchar(50) NOT NULL,
  is_default boolean DEFAULT false,
  is_mandatory boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tax_rates_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tax rate templates are public readable"
  ON tax_rates_templates FOR SELECT USING (true);

-- Seed data
INSERT INTO tax_rates_templates (country_code, tax_name, tax_name_local, rate, tax_type, is_default, is_mandatory) VALUES
-- TR
('TR', 'VAT 20%',          'KDV %20 (Standart)',    20.00, 'vat', true,  true),
('TR', 'VAT 10%',          'KDV %10 (İndirimli)',   10.00, 'vat', false, true),
('TR', 'VAT 1%',           'KDV %1 (Temel)',         1.00, 'vat', false, true),
('TR', 'Withholding 20%',  'Stopaj %20',            20.00, 'withholding', false, true),
('TR', 'Withholding 10%',  'Stopaj %10',            10.00, 'withholding', false, true),
-- KZ
('KZ', 'VAT 12%',          'ҚҚС 12%',              12.00, 'vat', true,  true),
('KZ', 'Corporate Tax 20%','Корпоративтік салық 20%',20.00, 'income_tax', false, true),
('KZ', 'Income Tax 10%',   'ЖТС 10%',              10.00, 'income_tax', false, true),
-- DE
('DE', 'VAT 19%',          'MwSt 19%',              19.00, 'vat', true,  true),
('DE', 'VAT 7%',           'MwSt 7% (ermäßigt)',     7.00, 'vat', false, true),
('DE', 'VAT 0%',           'MwSt 0% (steuerfrei)',   0.00, 'vat', false, true),
-- FR
('FR', 'VAT 20%',          'TVA 20%',               20.00, 'vat', true,  true),
('FR', 'VAT 10%',          'TVA 10%',               10.00, 'vat', false, true),
('FR', 'VAT 5.5%',         'TVA 5,5%',               5.50, 'vat', false, true),
('FR', 'VAT 2.1%',         'TVA 2,1%',               2.10, 'vat', false, true),
-- ES
('ES', 'VAT 21%',          'IVA 21%',               21.00, 'vat', true,  true),
('ES', 'VAT 10%',          'IVA 10%',               10.00, 'vat', false, true),
('ES', 'VAT 4%',           'IVA 4%',                 4.00, 'vat', false, true),
-- BE
('BE', 'VAT 21%',          'BTW/TVA 21%',           21.00, 'vat', true,  true),
('BE', 'VAT 12%',          'BTW/TVA 12%',           12.00, 'vat', false, true),
('BE', 'VAT 6%',           'BTW/TVA 6%',             6.00, 'vat', false, true),
-- US
('US', 'Sales Tax 10%',    'Sales Tax 10%',         10.00, 'vat', true,  false),
('US', 'Federal Tax 21%',  'Federal Tax 21%',       21.00, 'income_tax', false, false),
-- GB
('GB', 'VAT 20%',          'VAT 20%',               20.00, 'vat', true,  true),
('GB', 'VAT 5%',           'VAT 5%',                 5.00, 'vat', false, true),
('GB', 'VAT 0%',           'VAT 0%',                 0.00, 'vat', false, true),
-- IFRS
('IFRS','VAT 10%',         'VAT 10%',               10.00, 'vat', true,  false)
ON CONFLICT DO NOTHING;
