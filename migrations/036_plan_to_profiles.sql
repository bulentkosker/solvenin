-- ============================================================
-- Migration 036: Move subscription plan from companies → profiles (owner-based billing)
-- ADDITIVE — does NOT drop company columns yet (deferred to cleanup migration
-- after code verification to avoid breaking 28 references)
-- ============================================================

-- Note: profiles already has plan, plan_interval, plan_started_at, plan_expires_at
-- from migration_user_plan.sql — just add the missing fields

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS plan_status varchar(20) DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS trial_used boolean DEFAULT false;

-- CHECK constraint: keep permissive to avoid breaking existing data
-- ('free', 'professional', 'standard', 'starter', 'pro' all currently in use)
DO $$ BEGIN
  ALTER TABLE profiles ADD CONSTRAINT chk_profiles_plan_status
    CHECK (plan_status IN ('active', 'expired', 'trial', 'cancelled', 'paused'));
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN check_violation THEN NULL;
END $$;

-- Migrate: copy company subscription data → owner's profile
-- Only update if profile doesn't already have plan_end set
UPDATE profiles p
SET plan_status = CASE c.subscription_status
    WHEN 'active' THEN 'active'
    WHEN 'trial' THEN 'trial'
    ELSE 'expired'
  END,
  plan_started_at = COALESCE(p.plan_started_at, c.subscription_start),
  plan_expires_at = COALESCE(p.plan_expires_at, c.subscription_end)
FROM companies c
WHERE c.owner_id = p.id
  AND c.subscription_status IS NOT NULL;

-- Backfill: ensure every company has owner_id (M011 added it but may have nulls)
UPDATE companies c
SET owner_id = cu.user_id
FROM company_users cu
WHERE cu.company_id = c.id
  AND cu.role = 'owner'
  AND c.owner_id IS NULL;

-- Index on companies.owner_id for fast company-count queries
CREATE INDEX IF NOT EXISTS idx_companies_owner_id ON companies(owner_id) WHERE owner_id IS NOT NULL;

-- ============================================================
-- Updated RPC: get_company_subscription reads from owner's profile
-- ============================================================
DROP FUNCTION IF EXISTS get_company_subscription(uuid);

CREATE OR REPLACE FUNCTION get_company_subscription(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'plan', COALESCE(p.plan, 'free'),
    'plan_status', COALESCE(p.plan_status, 'active'),
    'plan_start', p.plan_started_at,
    'plan_end', p.plan_expires_at,
    'trial_used', COALESCE(p.trial_used, false),
    'owner_id', c.owner_id,
    'subscription_status', COALESCE(p.plan_status, 'active'),
    'subscription_start', p.plan_started_at,
    'subscription_end', p.plan_expires_at,
    'days_left', CASE WHEN p.plan_expires_at IS NULL THEN NULL
      ELSE (p.plan_expires_at::date - CURRENT_DATE)::int END,
    'max_users', COALESCE(c.max_users, 3),
    'is_frozen', COALESCE(c.is_frozen, false),
    'user_count', (SELECT COUNT(*) FROM company_users WHERE company_id = p_company_id)
  ) INTO result
  FROM companies c
  LEFT JOIN profiles p ON p.id = c.owner_id
  WHERE c.id = p_company_id;
  RETURN result;
END;
$$;

-- ============================================================
-- Updated RPC: create_company_for_user — free plan check
-- ============================================================
CREATE OR REPLACE FUNCTION create_company_for_user(
  p_user_id       uuid,
  p_name          text,
  p_country_code  text,
  p_base_currency text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_slug       text;
  v_plan       text;
  v_count      int;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid user');
  END IF;

  -- Free plan: max 1 company
  SELECT plan INTO v_plan FROM profiles WHERE id = p_user_id;
  IF COALESCE(v_plan, 'free') = 'free' THEN
    SELECT COUNT(*) INTO v_count FROM companies WHERE owner_id = p_user_id AND deleted_at IS NULL;
    IF v_count >= 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'free_plan_one_company');
    END IF;
  END IF;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'))
            || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);

  INSERT INTO companies (
    name, slug, country_code, base_currency, plan, status,
    owner_id, max_users, subscription_status, trial_ends_at
  ) VALUES (
    p_name, v_slug, p_country_code, p_base_currency, COALESCE(v_plan,'free'), 'active',
    p_user_id, 3, 'trial', now() + interval '14 days'
  )
  RETURNING id INTO v_company_id;

  INSERT INTO company_users (company_id, user_id, role, status, joined_at)
  VALUES (v_company_id, p_user_id, 'owner', 'active', now());

  INSERT INTO company_modules (company_id, module, is_active) VALUES
    (v_company_id, 'inventory', true), (v_company_id, 'sales', true),
    (v_company_id, 'purchasing', true), (v_company_id, 'contacts', true),
    (v_company_id, 'finance', true), (v_company_id, 'accounting', true),
    (v_company_id, 'hr', true), (v_company_id, 'production', true),
    (v_company_id, 'projects', true), (v_company_id, 'shipping', true),
    (v_company_id, 'maintenance', true), (v_company_id, 'crm', true),
    (v_company_id, 'pos', false), (v_company_id, 'restaurant', false),
    (v_company_id, 'hotel', false), (v_company_id, 'clinic', false),
    (v_company_id, 'elevator', false), (v_company_id, 'ecommerce', false)
  ON CONFLICT (company_id, module) DO NOTHING;

  BEGIN
    INSERT INTO warehouses (company_id, name, is_default)
    VALUES (v_company_id, 'Main Warehouse', true);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('success', true, 'company_id', v_company_id, 'slug', v_slug);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION create_company_for_user(uuid, text, text, text) TO authenticated;

-- ============================================================
-- New RPC: check_can_add_user — used by frontend before invite
-- ============================================================
CREATE OR REPLACE FUNCTION check_can_add_user(p_company_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_owner_plan text;
BEGIN
  SELECT p.plan INTO v_owner_plan
  FROM companies c
  JOIN profiles p ON p.id = c.owner_id
  WHERE c.id = p_company_id;

  IF COALESCE(v_owner_plan, 'free') = 'free' THEN
    RETURN jsonb_build_object('allowed', false, 'error', 'free_plan_no_users');
  END IF;
  RETURN jsonb_build_object('allowed', true);
END;
$$;

GRANT EXECUTE ON FUNCTION check_can_add_user(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('036_plan_to_profiles.sql',
  'Add plan_status/trial_used to profiles, migrate from companies, update RPCs. Column drops deferred.')
ON CONFLICT (file_name) DO NOTHING;
