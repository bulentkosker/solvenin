-- ============================================================
-- Migration 027: Fix get_company_subscription days_left calculation
--
-- Bug: EXTRACT(DAY FROM interval) returns only the day component,
-- not total days. E.g. '1 year 5 days' → 5, not 370.
-- Also: subscription_end::timestamp strips timezone causing mismatch.
--
-- Fix: Use (subscription_end::date - CURRENT_DATE)::int for correct
-- total days difference.
-- ============================================================

CREATE OR REPLACE FUNCTION get_company_subscription(p_company_id uuid)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'plan', plan, 'max_users', max_users,
  'subscription_status', subscription_status,
  'subscription_start', subscription_start,
  'subscription_end', subscription_end,
  'is_frozen', is_frozen,
  'user_count', (SELECT COUNT(*) FROM company_users WHERE company_id = p_company_id),
  'days_left', CASE WHEN subscription_end IS NULL THEN NULL
    ELSE (subscription_end::date - CURRENT_DATE)::int END
) FROM companies WHERE id = p_company_id;
$BODY$;

-- Fix BBB Company: wrong end date (2026-04-09 → 2027-04-10) and status (trial → active)
UPDATE companies SET
  subscription_end = '2027-04-10',
  subscription_start = '2026-03-03',
  subscription_status = 'active'
WHERE name = 'BBB Company'
  AND subscription_end = '2026-04-09';

INSERT INTO migrations_log (file_name, notes)
VALUES ('027_fix_subscription_days_left.sql',
  'Fix days_left: EXTRACT(DAY FROM interval) → date subtraction. Fix BBB Company subscription dates.')
ON CONFLICT (file_name) DO NOTHING;
