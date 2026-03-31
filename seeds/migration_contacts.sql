-- ============================================================
-- Migration: Merge customers + suppliers → contacts
-- Run in Supabase SQL Editor — Step by step
-- ============================================================

-- =====================
-- STEP 1: Create contacts table
-- =====================
CREATE TABLE IF NOT EXISTS contacts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  name varchar(255) NOT NULL,
  type varchar(20) DEFAULT 'customer', -- customer, supplier, both
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
-- STEP 2: RLS
-- =====================
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own company contacts" ON contacts;
CREATE POLICY "Users can manage own company contacts"
  ON contacts FOR ALL
  USING (company_id IN (SELECT get_my_company_ids()));

-- =====================
-- STEP 3: Migrate customers → contacts
-- =====================
INSERT INTO contacts (id, company_id, name, is_customer, is_supplier, type,
  email, phone, address, city, country, tax_number,
  contact_person, notes, currency_code, is_active, deleted_at, deleted_by, created_at)
SELECT id, company_id, name, true, false, 'customer',
  email, phone, address, city, country, tax_number,
  contact_person, notes,
  COALESCE(currency_code, 'USD'),
  is_active, deleted_at, deleted_by, created_at
FROM customers
ON CONFLICT (id) DO NOTHING;

-- =====================
-- STEP 4: Migrate suppliers → contacts
-- If same UUID exists (unlikely), mark as both
-- =====================
INSERT INTO contacts (id, company_id, name, is_customer, is_supplier, type,
  email, phone, address, city, country, tax_number,
  contact_person, notes, currency_code, payment_terms,
  is_active, deleted_at, deleted_by, created_at)
SELECT id, company_id, name, false, true, 'supplier',
  email, phone, address, city, country, tax_number,
  contact_person, notes,
  COALESCE(currency_code, 'USD'),
  COALESCE(payment_terms, 30),
  is_active, deleted_at, deleted_by, created_at
FROM suppliers
ON CONFLICT (id) DO UPDATE SET
  is_supplier = true,
  type = 'both',
  payment_terms = COALESCE(EXCLUDED.payment_terms, contacts.payment_terms);

-- =====================
-- STEP 5: Update type column for consistency
-- =====================
UPDATE contacts SET type = 'both' WHERE is_customer = true AND is_supplier = true;
UPDATE contacts SET type = 'customer' WHERE is_customer = true AND is_supplier = false;
UPDATE contacts SET type = 'supplier' WHERE is_customer = false AND is_supplier = true;

-- =====================
-- STEP 6: Verify
-- =====================
SELECT type, count(*) FROM contacts GROUP BY type;
SELECT count(*) as contacts_total FROM contacts;
SELECT count(*) as customers_total FROM customers;
SELECT count(*) as suppliers_total FROM suppliers;

-- =====================
-- NOTE: Do NOT drop customers/suppliers tables yet.
-- Frontend will be updated to use contacts first.
-- After verification, old tables can be dropped.
-- =====================
