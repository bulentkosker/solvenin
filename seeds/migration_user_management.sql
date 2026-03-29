-- ============================================================
-- User Management — Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Add must_change_password to profiles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='must_change_password') THEN
    ALTER TABLE profiles ADD COLUMN must_change_password boolean DEFAULT false;
  END IF;
END $$;

-- 2. Drop user_invitations table (no longer needed)
DROP TABLE IF EXISTS user_invitations CASCADE;

-- 3. Clean up orphan data
DELETE FROM companies WHERE name = '__invite__';
DELETE FROM companies WHERE name ILIKE '%bulentkosker%' AND id != '064fa4c7-1dc7-40a1-b5e3-4aa22ddc1a82';
