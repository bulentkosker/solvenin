-- CRM Quotes Migration — 2026-04-05
CREATE TABLE IF NOT EXISTS crm_quotes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES crm_opportunities(id),
  contact_id uuid REFERENCES contacts(id),
  quote_number varchar(50), status varchar(30) DEFAULT 'draft',
  valid_until date, currency_code varchar(3), exchange_rate decimal(18,6) DEFAULT 1,
  subtotal decimal(18,2) DEFAULT 0, tax_amount decimal(18,2) DEFAULT 0,
  discount decimal(18,2) DEFAULT 0, total decimal(18,2) DEFAULT 0,
  notes text, terms text,
  converted_to_order_id uuid REFERENCES sales_orders(id),
  created_by uuid, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crm_quote_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  quote_id uuid REFERENCES crm_quotes(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id), description text,
  quantity decimal(18,3) DEFAULT 1, unit varchar(50),
  unit_price decimal(18,2) DEFAULT 0, unit_price_foreign decimal(18,2),
  discount_percent decimal(5,2) DEFAULT 0, tax_rate decimal(5,2) DEFAULT 0,
  total decimal(18,2) DEFAULT 0, total_foreign decimal(18,2)
);
ALTER TABLE crm_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_quote_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_quotes_policy ON crm_quotes FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY crm_qi_policy ON crm_quote_items FOR ALL USING (quote_id IN (SELECT id FROM crm_quotes WHERE company_id = ANY(get_my_company_ids())));
CREATE INDEX IF NOT EXISTS idx_crm_quotes_company ON crm_quotes(company_id);
CREATE INDEX IF NOT EXISTS idx_crm_quotes_opportunity ON crm_quotes(opportunity_id);
CREATE INDEX IF NOT EXISTS idx_crm_quote_items_quote ON crm_quote_items(quote_id);
