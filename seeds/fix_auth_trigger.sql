-- ============================================================
-- Fix: Auth trigger creating unwanted companies
-- Run this in Supabase SQL Editor
-- ============================================================

-- Step 1: Find the trigger
-- Run this first to see what triggers exist:
SELECT tg.tgname, p.proname, p.prosrc
FROM pg_trigger tg
JOIN pg_proc p ON tg.tgfoid = p.oid
JOIN pg_class c ON tg.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' AND c.relname = 'users';

-- Step 2: If you find a trigger function that creates companies,
-- modify it to skip when skip_company_creation is set.
-- Example fix (adjust function name as needed):

-- Option A: Modify the trigger function to check the flag
/*
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Skip company creation if user was added via admin API
  IF (NEW.raw_user_meta_data->>'skip_company_creation')::boolean = true THEN
    -- Only create profile, no company
    INSERT INTO public.profiles (id, full_name)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name')
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
  END IF;

  -- Normal registration — create company (existing logic)
  -- ... keep existing company creation code here ...

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
*/

-- Option B: If you want to completely disable auto company creation
-- (since all pages already handle it in JS):
/*
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
*/

-- Step 3: Clean up duplicate companies created by the trigger
-- Find and delete companies that were auto-created for admin-added users:
DELETE FROM company_users
WHERE company_id IN (
  SELECT c.id FROM companies c
  WHERE c.created_at > now() - interval '1 hour'
  AND c.id NOT IN (SELECT company_id FROM company_users WHERE role = 'owner')
);
DELETE FROM companies
WHERE id NOT IN (SELECT company_id FROM company_users)
AND created_at > now() - interval '1 hour';
