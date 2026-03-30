-- ============================================================
-- Fix: Normalize company plan values
-- Run in Supabase SQL Editor
-- ============================================================

-- 1. Fix legacy 'pro' values → 'professional'
UPDATE companies SET plan = 'professional' WHERE plan = 'pro';

-- 2. Ensure all companies have a valid plan value
UPDATE companies SET plan = 'free' WHERE plan IS NULL OR plan NOT IN ('free', 'standard', 'professional');

-- 3. Verify: show all companies with their plans and owners
SELECT c.id, c.name, c.plan, c.created_at, cu.user_id, cu.role
FROM companies c
LEFT JOIN company_users cu ON c.id = cu.company_id AND cu.role = 'owner'
ORDER BY c.created_at;

-- 4. Clean up orphan companies (no users attached)
DELETE FROM companies
WHERE id NOT IN (SELECT DISTINCT company_id FROM company_users);
