-- ============================================================
-- Migration: Merge customers + suppliers → contacts
-- Run EACH STEP separately in Supabase SQL Editor
-- ============================================================

-- =====================
-- STEP 1: Create contacts table
-- =====================
CREATE TABLE IF NOT EXISTS contacts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  name varchar(255) NOT NULL,
  type varchar(20) DEFAULT 'customer',
  is_customer boolean DEFAULT false,
  is_supplier boolean DEFAULT false,
  email varchar(255),
  phone varchar(100),
  address text,
  city varchar(100),
  country varchar(100),
  tax_number varchar(100),
  contact_person varchar(255),
  notes text,
  currency_code varchar(3) DEFAULT 'USD',
  credit_limit decimal(18,2) DEFAULT 0,
  payment_terms int DEFAULT 30,
  is_active boolean DEFAULT true,
  deleted_at timestamptz,
  deleted_by uuid,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contacts_company ON contacts(company_id);
CREATE INDEX IF NOT EXISTS idx_contacts_type ON contacts(company_id, is_customer, is_supplier);

-- =====================
-- STEP 2: RLS (run separately)
-- =====================
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own company contacts" ON contacts;
CREATE POLICY "Users can manage own company contacts"
  ON contacts FOR ALL
  USING (company_id = ANY(get_my_company_ids()));

-- =====================
-- STEP 3: Migrate customers → contacts (run separately)
-- Only copies columns that exist in customers table
-- =====================
INSERT INTO contacts (id, company_id, name, is_customer, is_supplier, type,
  email, phone, address, city, country, tax_number, notes, is_active, created_at)
SELECT id, company_id, name, true, false, 'customer',
  email, phone, address, city, country, tax_number, notes, is_active, created_at
FROM customers
ON CONFLICT (id) DO NOTHING;

-- =====================
-- STEP 4: Migrate suppliers → contacts (run separately)
-- =====================
INSERT INTO contacts (id, company_id, name, is_customer, is_supplier, type,
  email, phone, address, city, country, tax_number, notes, is_active, created_at)
SELECT id, company_id, name, false, true, 'supplier',
  email, phone, address, city, country, tax_number, notes, is_active, created_at
FROM suppliers
ON CONFLICT (id) DO UPDATE SET
  is_supplier = true,
  type = 'both';

-- =====================
-- STEP 5: Sync extra columns if they exist (run separately, ignore errors)
-- =====================
-- UPDATE contacts c SET contact_person = cu.contact_person FROM customers cu WHERE c.id = cu.id AND cu.contact_person IS NOT NULL;
-- UPDATE contacts c SET currency_code = cu.currency_code FROM customers cu WHERE c.id = cu.id AND cu.currency_code IS NOT NULL;
-- UPDATE contacts c SET payment_terms = su.payment_terms FROM suppliers su WHERE c.id = su.id AND su.payment_terms IS NOT NULL;
-- UPDATE contacts c SET deleted_at = cu.deleted_at, deleted_by = cu.deleted_by FROM customers cu WHERE c.id = cu.id AND cu.deleted_at IS NOT NULL;

-- =====================
-- STEP 6: Verify (run separately)
-- =====================
SELECT type, count(*) FROM contacts GROUP BY type;
SELECT count(*) as contacts_total FROM contacts;
SELECT count(*) as customers_total FROM customers;
SELECT count(*) as suppliers_total FROM suppliers;
