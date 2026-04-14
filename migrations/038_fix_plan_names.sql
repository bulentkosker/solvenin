-- Migration 038: Normalize plan names to free / standard / pro
-- Note: 037 was already used by sp_user_plan migration

-- Drop old constraint first (M036 added a permissive one, may not exist with this name)
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS chk_profiles_plan;

-- Migrate values
UPDATE profiles SET plan = 'pro' WHERE plan IN ('professional', 'pro');
UPDATE profiles SET plan = 'standard' WHERE plan IN ('starter', 'standard');
UPDATE profiles SET plan = 'free' WHERE plan IS NULL OR plan NOT IN ('free', 'standard', 'pro');

-- Same for companies (legacy column kept for backward compat until cleanup)
UPDATE companies SET plan = 'pro' WHERE plan IN ('professional', 'pro');
UPDATE companies SET plan = 'standard' WHERE plan IN ('starter', 'standard');
UPDATE companies SET plan = 'free' WHERE plan IS NULL OR plan NOT IN ('free', 'standard', 'pro');

-- Apply strict constraint
ALTER TABLE profiles
  ADD CONSTRAINT chk_profiles_plan
    CHECK (plan IN ('free', 'standard', 'pro'));

INSERT INTO migrations_log (file_name, notes)
VALUES ('038_fix_plan_names.sql',
  'Normalize plan names: professional→pro, starter→standard. Strict CHECK on profiles.plan')
ON CONFLICT (file_name) DO NOTHING;
