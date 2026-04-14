-- ============================================================
-- Migration 042: DB-level plan enforcement via triggers
-- (Note: 039 already used by preferred_language migration)
-- ============================================================

-- Step 1: plan_user_count column on profiles
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS plan_user_count integer DEFAULT 1;

-- Backfill defaults
UPDATE profiles SET plan_user_count = 999999 WHERE plan = 'pro';
UPDATE profiles SET plan_user_count = 1 WHERE plan = 'standard' AND plan_user_count IS NULL;
UPDATE profiles SET plan_user_count = 1 WHERE plan = 'free' AND plan_user_count IS NULL;

-- Step 2: Helper function to get owner's plan
CREATE OR REPLACE FUNCTION get_company_owner_plan(p_company_id uuid)
RETURNS TABLE(plan varchar, plan_user_count integer, owner_id uuid)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT p.plan::varchar, p.plan_user_count, c.owner_id
  FROM companies c
  JOIN profiles p ON p.id = c.owner_id
  WHERE c.id = p_company_id;
$$;

-- ============================================================
-- Step 3: Invoice limit trigger (free = 30/month total)
-- ============================================================
CREATE OR REPLACE FUNCTION check_invoice_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  monthly_count integer;
BEGIN
  SELECT plan INTO owner_plan FROM get_company_owner_plan(NEW.company_id);
  IF COALESCE(owner_plan, 'free') != 'free' THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO monthly_count FROM (
    SELECT id FROM sales_orders
    WHERE company_id = NEW.company_id
      AND created_at >= date_trunc('month', now())
      AND deleted_at IS NULL
    UNION ALL
    SELECT id FROM purchase_orders
    WHERE company_id = NEW.company_id
      AND created_at >= date_trunc('month', now())
      AND deleted_at IS NULL
  ) combined;

  IF monthly_count >= 30 THEN
    RAISE EXCEPTION 'free_plan_invoice_limit' USING HINT = 'Ücretsiz planda aylık 30 fatura limitine ulaştınız';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_invoice_limit ON sales_orders;
DROP TRIGGER IF EXISTS enforce_invoice_limit_purchase ON purchase_orders;
CREATE TRIGGER enforce_invoice_limit BEFORE INSERT ON sales_orders
  FOR EACH ROW EXECUTE FUNCTION check_invoice_limit();
CREATE TRIGGER enforce_invoice_limit_purchase BEFORE INSERT ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION check_invoice_limit();

-- ============================================================
-- Step 4: User limit trigger on company_users
-- (Owners always allowed — they're the creator)
-- ============================================================
CREATE OR REPLACE FUNCTION check_user_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  owner_user_count integer;
  current_user_count integer;
  company_owner_id uuid;
BEGIN
  -- Owner role always allowed (they're creating or transferring the company)
  IF NEW.role = 'owner' THEN RETURN NEW; END IF;

  SELECT owner_id INTO company_owner_id FROM companies WHERE id = NEW.company_id;
  IF company_owner_id IS NULL THEN RETURN NEW; END IF;

  SELECT plan, plan_user_count INTO owner_plan, owner_user_count
  FROM profiles WHERE id = company_owner_id;

  -- Free plan: no additional users
  IF COALESCE(owner_plan, 'free') = 'free' THEN
    RAISE EXCEPTION 'free_plan_no_users' USING HINT = 'Ücretsiz planda ek kullanıcı ekleyemezsiniz';
  END IF;

  -- Count DISTINCT users across all companies owned by this owner
  SELECT COUNT(DISTINCT cu.user_id) INTO current_user_count
  FROM company_users cu
  JOIN companies c ON c.id = cu.company_id
  WHERE c.owner_id = company_owner_id;

  IF current_user_count >= COALESCE(owner_user_count, 1) THEN
    RAISE EXCEPTION 'plan_user_limit_reached' USING HINT = 'Kullanıcı limitine ulaştınız. Planınızı yükseltin';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_user_limit ON company_users;
CREATE TRIGGER enforce_user_limit BEFORE INSERT ON company_users
  FOR EACH ROW EXECUTE FUNCTION check_user_limit();

-- ============================================================
-- Step 5: Company limit trigger
-- ============================================================
CREATE OR REPLACE FUNCTION check_company_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  company_count integer;
BEGIN
  IF NEW.owner_id IS NULL THEN RETURN NEW; END IF;

  SELECT plan INTO owner_plan FROM profiles WHERE id = NEW.owner_id;

  SELECT COUNT(*) INTO company_count
  FROM companies
  WHERE owner_id = NEW.owner_id AND deleted_at IS NULL;

  IF COALESCE(owner_plan, 'free') = 'free' AND company_count >= 1 THEN
    RAISE EXCEPTION 'free_plan_one_company' USING HINT = 'Ücretsiz planda yalnızca 1 şirket açabilirsiniz';
  END IF;
  IF owner_plan = 'standard' AND company_count >= 1 THEN
    RAISE EXCEPTION 'standard_plan_one_company' USING HINT = 'Standard planda yalnızca 1 şirket açabilirsiniz. Pro plana geçin';
  END IF;
  -- Pro: unlimited
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_company_limit ON companies;
CREATE TRIGGER enforce_company_limit BEFORE INSERT ON companies
  FOR EACH ROW EXECUTE FUNCTION check_company_limit();

-- ============================================================
-- Step 6: Warehouse limit trigger (free = 1)
-- ============================================================
CREATE OR REPLACE FUNCTION check_warehouse_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  warehouse_count integer;
BEGIN
  SELECT plan INTO owner_plan FROM get_company_owner_plan(NEW.company_id);
  IF COALESCE(owner_plan, 'free') != 'free' THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO warehouse_count
  FROM warehouses
  WHERE company_id = NEW.company_id AND deleted_at IS NULL;

  IF warehouse_count >= 1 THEN
    RAISE EXCEPTION 'free_plan_warehouse_limit' USING HINT = 'Ücretsiz planda yalnızca 1 depo kullanabilirsiniz';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_warehouse_limit ON warehouses;
CREATE TRIGGER enforce_warehouse_limit BEFORE INSERT ON warehouses
  FOR EACH ROW EXECUTE FUNCTION check_warehouse_limit();

-- ============================================================
-- Step 7: Cash register limit trigger (free = 1)
-- ============================================================
CREATE OR REPLACE FUNCTION check_cash_register_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  register_count integer;
BEGIN
  SELECT plan INTO owner_plan FROM get_company_owner_plan(NEW.company_id);
  IF COALESCE(owner_plan, 'free') != 'free' THEN RETURN NEW; END IF;

  SELECT COUNT(*) INTO register_count
  FROM cash_registers
  WHERE company_id = NEW.company_id AND is_active = true;

  IF register_count >= 1 THEN
    RAISE EXCEPTION 'free_plan_register_limit' USING HINT = 'Ücretsiz planda yalnızca 1 kasa kullanabilirsiniz';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS enforce_cash_register_limit ON cash_registers;
CREATE TRIGGER enforce_cash_register_limit BEFORE INSERT ON cash_registers
  FOR EACH ROW EXECUTE FUNCTION check_cash_register_limit();

-- Updated sp_update_user_plan accepts plan_user_count
CREATE OR REPLACE FUNCTION sp_update_user_plan(
  p_user_id uuid, p_plan varchar, p_plan_end timestamptz,
  p_plan_status varchar, p_plan_user_count integer DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_auto_count integer;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid user');
  END IF;
  v_auto_count := COALESCE(p_plan_user_count, CASE COALESCE(p_plan, 'free')
    WHEN 'free' THEN 1 WHEN 'standard' THEN 1 WHEN 'pro' THEN 999999 ELSE 1 END);
  UPDATE profiles SET
    plan = COALESCE(p_plan, plan),
    plan_expires_at = p_plan_end,
    plan_status = COALESCE(p_plan_status, plan_status),
    plan_user_count = v_auto_count
  WHERE id = p_user_id;
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END $$;

GRANT EXECUTE ON FUNCTION sp_update_user_plan(uuid, varchar, timestamptz, varchar, integer) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('042_plan_limits_triggers.sql',
  'DB-level plan enforcement via triggers: invoice/user/company/warehouse/cash register limits + plan_user_count')
ON CONFLICT (file_name) DO NOTHING;
