-- Solvenin CRM Module Migration
-- Created: 2026-04-05

CREATE TABLE IF NOT EXISTS crm_opportunities (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES contacts(id),
  title varchar(255) NOT NULL, stage varchar(50) DEFAULT 'lead',
  value decimal(18,2) DEFAULT 0, currency_code varchar(3) DEFAULT 'KZT',
  probability int DEFAULT 0, assigned_to uuid,
  expected_close_date date, lost_reason text, notes text,
  created_by uuid, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crm_activities (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES crm_opportunities(id) ON DELETE CASCADE,
  type varchar(50) NOT NULL, description text,
  next_action text, next_action_date date,
  created_by uuid, created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS crm_reminders (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES crm_opportunities(id) ON DELETE CASCADE,
  user_id uuid, reminder_date date NOT NULL, message text,
  is_read boolean DEFAULT false, created_at timestamptz DEFAULT now()
);
ALTER TABLE crm_opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm_reminders ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_opp_policy ON crm_opportunities FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY crm_act_policy ON crm_activities FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY crm_rem_policy ON crm_reminders FOR ALL USING (company_id = ANY(get_my_company_ids()));
CREATE INDEX IF NOT EXISTS idx_crm_opp_company ON crm_opportunities(company_id);
CREATE INDEX IF NOT EXISTS idx_crm_opp_stage ON crm_opportunities(company_id, stage);
CREATE INDEX IF NOT EXISTS idx_crm_opp_assigned ON crm_opportunities(assigned_to);
CREATE INDEX IF NOT EXISTS idx_crm_act_opportunity ON crm_activities(opportunity_id);
CREATE INDEX IF NOT EXISTS idx_crm_rem_user ON crm_reminders(user_id, reminder_date);
CREATE INDEX IF NOT EXISTS idx_crm_rem_unread ON crm_reminders(user_id, is_read);
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS opportunity_id uuid REFERENCES crm_opportunities(id);
ALTER TABLE sales_orders ADD COLUMN IF NOT EXISTS valid_until date;
