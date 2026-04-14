-- Migration 043: User suspension support
-- Allows owner to suspend users without deleting them (frees up plan slot)

ALTER TABLE company_users ADD COLUMN IF NOT EXISTS is_suspended boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_company_users_suspended
  ON company_users(user_id, company_id) WHERE is_suspended = true;

-- Update user limit trigger to exclude suspended users from count
CREATE OR REPLACE FUNCTION check_user_limit()
RETURNS TRIGGER AS $$
DECLARE
  owner_plan varchar;
  owner_user_count integer;
  current_user_count integer;
  company_owner_id uuid;
BEGIN
  IF NEW.role = 'owner' THEN RETURN NEW; END IF;

  SELECT owner_id INTO company_owner_id FROM companies WHERE id = NEW.company_id;
  IF company_owner_id IS NULL THEN RETURN NEW; END IF;

  SELECT plan, plan_user_count INTO owner_plan, owner_user_count
  FROM profiles WHERE id = company_owner_id;

  IF COALESCE(owner_plan, 'free') = 'free' THEN
    RAISE EXCEPTION 'free_plan_no_users' USING HINT = 'Ücretsiz planda ek kullanıcı ekleyemezsiniz';
  END IF;

  -- Count DISTINCT active (non-suspended) users across all companies owned by this owner
  SELECT COUNT(DISTINCT cu.user_id) INTO current_user_count
  FROM company_users cu
  JOIN companies c ON c.id = cu.company_id
  WHERE c.owner_id = company_owner_id
    AND cu.is_suspended = false;

  IF current_user_count >= COALESCE(owner_user_count, 1) THEN
    RAISE EXCEPTION 'plan_user_limit_reached' USING HINT = 'Kullanıcı limitine ulaştınız';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update sp_users to include is_suspended for service panel display
DROP FUNCTION IF EXISTS sp_users();
CREATE OR REPLACE FUNCTION sp_users()
RETURNS TABLE(
  id uuid, full_name text, email text, company_name text, company_role text,
  plan text, plan_status text, plan_end timestamptz,
  trial_used boolean, is_suspended boolean, created_at timestamptz
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT p.id, p.full_name::text, u.email::text,
    (SELECT c.name FROM companies c JOIN company_users cu ON cu.company_id = c.id AND cu.user_id = p.id
     ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text,
    (SELECT cu.role FROM company_users cu WHERE cu.user_id = p.id ORDER BY cu.role = 'owner' DESC, cu.joined_at LIMIT 1)::text,
    COALESCE(p.plan, 'free')::text, COALESCE(p.plan_status, 'active')::text,
    p.plan_expires_at, COALESCE(p.trial_used, false),
    COALESCE((SELECT cu.is_suspended FROM company_users cu WHERE cu.user_id = p.id ORDER BY cu.joined_at LIMIT 1), false),
    p.created_at
  FROM profiles p
  JOIN auth.users u ON u.id = p.id
  ORDER BY p.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION sp_users() TO authenticated;
NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('043_user_suspend.sql', 'is_suspended on company_users + trigger excludes suspended from count + sp_users returns is_suspended')
ON CONFLICT (file_name) DO NOTHING;
