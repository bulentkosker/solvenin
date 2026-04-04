-- Solvenin Multi-Currency Migration
-- Created: 2026-04-05

-- contacts
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS currency_code varchar(3);

-- sales_orders
ALTER TABLE sales_orders
  ADD COLUMN IF NOT EXISTS currency_code varchar(3),
  ADD COLUMN IF NOT EXISTS exchange_rate decimal(18,6) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_foreign decimal(18,2);

-- purchase_orders
ALTER TABLE purchase_orders
  ADD COLUMN IF NOT EXISTS currency_code varchar(3),
  ADD COLUMN IF NOT EXISTS exchange_rate decimal(18,6) DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_foreign decimal(18,2);

-- sales_order_items
ALTER TABLE sales_order_items
  ADD COLUMN IF NOT EXISTS unit_price_foreign decimal(18,2),
  ADD COLUMN IF NOT EXISTS total_foreign decimal(18,2);

-- purchase_order_items
ALTER TABLE purchase_order_items
  ADD COLUMN IF NOT EXISTS unit_price_foreign decimal(18,2),
  ADD COLUMN IF NOT EXISTS total_foreign decimal(18,2);

-- journal_entries
ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS currency_code varchar(3),
  ADD COLUMN IF NOT EXISTS exchange_rate decimal(18,6) DEFAULT 1;

-- journal_lines
ALTER TABLE journal_lines
  ADD COLUMN IF NOT EXISTS amount_foreign decimal(18,2);

-- fx_revaluations
CREATE TABLE IF NOT EXISTS fx_revaluations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  revaluation_date date NOT NULL,
  currency_code varchar(3) NOT NULL,
  rate_used decimal(18,6) NOT NULL,
  total_gain_loss decimal(18,2),
  journal_entry_id uuid REFERENCES journal_entries(id),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE fx_revaluations ENABLE ROW LEVEL SECURITY;
CREATE POLICY fx_reval_all ON fx_revaluations FOR ALL USING (company_id = ANY(get_my_company_ids()));

CREATE INDEX IF NOT EXISTS idx_fx_revaluations_company ON fx_revaluations(company_id, revaluation_date DESC);
CREATE INDEX IF NOT EXISTS idx_sales_orders_currency ON sales_orders(company_id, currency_code);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_currency ON purchase_orders(company_id, currency_code);
