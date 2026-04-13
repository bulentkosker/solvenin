-- ============================================================
-- Migration 030: Pre-production audit fixes
-- ============================================================

-- Note: exec_sql doesn't support explicit transactions.
-- Each exec_sql call runs in an implicit transaction.

-- Fix 2: Missing company_id indexes (16 tables)
CREATE INDEX IF NOT EXISTS idx_bank_accounts_company_id ON bank_accounts(company_id);
CREATE INDEX IF NOT EXISTS idx_crm_activities_company_id ON crm_activities(company_id);
CREATE INDEX IF NOT EXISTS idx_crm_reminders_company_id ON crm_reminders(company_id);
CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON profiles(company_id) WHERE company_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_warehouses_company_id ON warehouses(company_id);
CREATE INDEX IF NOT EXISTS idx_tax_rates_company_id ON tax_rates(company_id);
CREATE INDEX IF NOT EXISTS idx_cash_registers_company_id ON cash_registers(company_id);
CREATE INDEX IF NOT EXISTS idx_leave_types_company_id ON leave_types(company_id);
CREATE INDEX IF NOT EXISTS idx_service_providers_company_id ON service_providers(company_id);
CREATE INDEX IF NOT EXISTS idx_failure_records_company_id ON failure_records(company_id);
CREATE INDEX IF NOT EXISTS idx_tax_regimes_company_id ON tax_regimes(company_id);
CREATE INDEX IF NOT EXISTS idx_pos_quick_buttons_company_id ON pos_quick_buttons(company_id);
CREATE INDEX IF NOT EXISTS idx_product_attributes_company_id ON product_attributes(company_id);
CREATE INDEX IF NOT EXISTS idx_product_attribute_values_company_id ON product_attribute_values(company_id);
CREATE INDEX IF NOT EXISTS idx_demo_accounts_company_id ON demo_accounts(company_id) WHERE company_id IS NOT NULL;

-- Fix 3: Recalculate negative stock (will be done via RPC after migration)

-- Fix 4: Remove orphan contacts with NULL company_id
DELETE FROM contacts WHERE company_id IS NULL;

-- Fix 5: Remove anon from create_company_for_user
REVOKE EXECUTE ON FUNCTION create_company_for_user(uuid, text, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION create_company_for_user(uuid, text, text, text) TO authenticated;

-- Fix 6: Tighten companies_insert policy
DROP POLICY IF EXISTS "companies_insert" ON companies;
CREATE POLICY "companies_insert" ON companies
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Fix 8: set_pos_pin — add user validation
CREATE OR REPLACE FUNCTION set_pos_pin(
  p_company_id uuid,
  p_user_id uuid,
  p_pin text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  IF p_pin IS NULL OR p_pin = '' THEN
    UPDATE company_users
    SET pos_pin = NULL
    WHERE company_id = p_company_id AND user_id = p_user_id;
    RETURN;
  END IF;

  IF p_pin !~ '^\d{4}$' THEN
    RAISE EXCEPTION 'PIN must be exactly 4 digits';
  END IF;

  UPDATE company_users
  SET pos_pin = encode(digest(p_pin, 'sha256'), 'hex')
  WHERE company_id = p_company_id AND user_id = p_user_id;
END;
$$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('030_pre_production_fixes.sql',
  'Pre-prod: 15 company_id indexes, orphan cleanup, anon revoke, companies_insert tighten, set_pos_pin validation')
ON CONFLICT (file_name) DO NOTHING;

-- End of migration
