-- ============================================================
-- Migration: Move plan to profiles (user-level)
-- Run in Supabase SQL Editor
-- ============================================================

-- Step 1: Add plan columns to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan varchar(50) DEFAULT 'free';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_interval varchar(20) DEFAULT 'monthly';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_started_at timestamptz DEFAULT now();
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_expires_at timestamptz;

-- Step 2: Migrate existing data — take highest plan from owned companies
UPDATE profiles p
SET plan = (
  SELECT COALESCE(MAX(
    CASE c.plan
      WHEN 'professional' THEN 'professional'
      WHEN 'pro' THEN 'professional'
      WHEN 'standard' THEN 'standard'
      ELSE 'free'
    END
  ), 'free')
  FROM companies c
  JOIN company_users cu ON cu.company_id = c.id
  WHERE cu.user_id = p.id
  AND cu.role = 'owner'
);

-- Step 3: Function to count active unique users across owner's companies
CREATE OR REPLACE FUNCTION get_active_user_count(owner_uid uuid)
RETURNS int
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT COUNT(DISTINCT cu2.user_id)::int
  FROM company_users cu1
  JOIN company_users cu2 ON cu2.company_id = cu1.company_id
  WHERE cu1.user_id = owner_uid
  AND cu1.role IN ('owner', 'admin')
  AND cu2.status = 'active';
$$;

-- Step 4: Verify
SELECT id, full_name, plan, plan_interval, plan_started_at FROM profiles ORDER BY created_at;
SELECT get_active_user_count(auth.uid());
