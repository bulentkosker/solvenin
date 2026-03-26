-- ============================================================
-- Chart of Accounts Templates — Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1) Templates table (public, read-only seed data per country)
CREATE TABLE IF NOT EXISTS chart_of_accounts_templates (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  country_code varchar(5) NOT NULL,
  account_code varchar(10) NOT NULL,
  account_name_local varchar(200) NOT NULL,
  account_name_en varchar(200) NOT NULL,
  account_type varchar(50) NOT NULL,
  parent_code varchar(10),
  level int DEFAULT 1,
  is_mandatory boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE(country_code, account_code)
);

ALTER TABLE chart_of_accounts_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Templates are public readable"
  ON chart_of_accounts_templates FOR SELECT
  USING (true);

-- 2) Add missing columns to existing chart_of_accounts if needed
-- (The table already exists with code, name, name_local, type, subtype, balance, is_system, is_active)
DO $$
BEGIN
  -- Add parent_code if not exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='chart_of_accounts' AND column_name='parent_code') THEN
    ALTER TABLE chart_of_accounts ADD COLUMN parent_code varchar(10);
  END IF;
  -- Add level if not exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='chart_of_accounts' AND column_name='level') THEN
    ALTER TABLE chart_of_accounts ADD COLUMN level int DEFAULT 1;
  END IF;
  -- Add country_code if not exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='chart_of_accounts' AND column_name='country_code') THEN
    ALTER TABLE chart_of_accounts ADD COLUMN country_code varchar(5);
  END IF;
END $$;
