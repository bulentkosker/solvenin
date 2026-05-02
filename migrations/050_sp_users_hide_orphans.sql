-- 050_sp_users_hide_orphans.sql
-- Service panel was listing profiles whose company_users rows had been
-- deleted ("orphan" auth users that still have a profiles row). The
-- old sp_users selected from profiles JOIN auth.users with no
-- company_users predicate; orphans came back with NULL company_name
-- and bucketed under '—' on the client (or, when filtered, surfaced
-- adjacent to other tenants).
--
-- Fix: add WHERE EXISTS on company_users so an empty membership hides
-- the profile from the panel. Owner-first ORDER BY in the per-row
-- subqueries is preserved.

CREATE OR REPLACE FUNCTION public.sp_users()
RETURNS json
LANGUAGE sql
SECURITY DEFINER
AS $function$
SELECT COALESCE(json_agg(row_to_json(u)), '[]'::json) FROM (
  SELECT
    p.id, p.full_name::text, u.email::text,
    (SELECT c.name FROM companies c JOIN company_users cu ON cu.company_id = c.id AND cu.user_id = p.id
     ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text AS company_name,
    (SELECT cu.role FROM company_users cu WHERE cu.user_id = p.id ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text AS company_role,
    COALESCE(p.plan, 'free')::text AS plan,
    COALESCE(p.plan_status, 'active')::text AS plan_status,
    p.plan_expires_at AS plan_end,
    COALESCE(p.plan_user_count, 1) AS plan_user_count,
    COALESCE(p.trial_used, false) AS trial_used,
    COALESCE((SELECT cu.is_suspended FROM company_users cu WHERE cu.user_id = p.id ORDER BY cu.joined_at LIMIT 1), false) AS is_suspended,
    p.created_at
  FROM profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE EXISTS (SELECT 1 FROM company_users cu WHERE cu.user_id = p.id)
  ORDER BY p.created_at DESC
) u;
$function$;
