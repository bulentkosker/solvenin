-- ============================================================
-- User Permissions & Invitation System — Migration
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Standardize company_users roles
ALTER TABLE company_users DROP CONSTRAINT IF EXISTS company_users_role_check;
ALTER TABLE company_users
  ADD CONSTRAINT company_users_role_check
  CHECK (role IN ('owner', 'admin', 'manager', 'employee', 'accountant'));

-- Update any non-standard roles to 'employee'
UPDATE company_users SET role = 'employee'
WHERE role NOT IN ('owner', 'admin', 'manager', 'employee', 'accountant');

-- 2. User invitations table
CREATE TABLE IF NOT EXISTS user_invitations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  email varchar(255) NOT NULL,
  role varchar(50) NOT NULL DEFAULT 'employee',
  token varchar(255) NOT NULL UNIQUE,
  invited_by uuid REFERENCES auth.users(id),
  invited_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT now() + interval '7 days',
  accepted_at timestamptz,
  status varchar(20) DEFAULT 'pending',
  UNIQUE(company_id, email)
);

ALTER TABLE user_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Company admins can manage invitations"
  ON user_invitations FOR ALL
  USING (company_id IN (
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  ));

CREATE POLICY "Anyone can read invitation by token"
  ON user_invitations FOR SELECT
  USING (true);

-- 3. User permissions table
CREATE TABLE IF NOT EXISTS user_permissions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  module varchar(50) NOT NULL,
  can_view boolean DEFAULT true,
  can_create boolean DEFAULT false,
  can_edit boolean DEFAULT false,
  can_delete boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, user_id, module)
);

ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own permissions"
  ON user_permissions FOR SELECT
  USING (user_id = auth.uid() OR company_id IN (
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  ));

CREATE POLICY "Admins can manage permissions"
  ON user_permissions FOR INSERT
  WITH CHECK (company_id IN (
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  ));

CREATE POLICY "Admins can update permissions"
  ON user_permissions FOR UPDATE
  USING (company_id IN (
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  ));

CREATE POLICY "Admins can delete permissions"
  ON user_permissions FOR DELETE
  USING (company_id IN (
    SELECT company_id FROM company_users
    WHERE user_id = auth.uid()
    AND role IN ('owner', 'admin')
  ));

-- 4. Default permissions function
CREATE OR REPLACE FUNCTION get_default_permissions(p_role text)
RETURNS TABLE(module text, can_view bool, can_create bool, can_edit bool, can_delete bool)
LANGUAGE sql AS $$
  SELECT * FROM (VALUES
    ('inventory',true,true,true,true),('sales',true,true,true,true),('purchasing',true,true,true,true),
    ('production',true,true,true,true),('accounting',true,true,true,true),('hr',true,true,true,true),
    ('shipping',true,true,true,true),('projects',true,true,true,true),('maintenance',true,true,true,true),
    ('cash_bank',true,true,true,true)
  ) AS t(module,can_view,can_create,can_edit,can_delete) WHERE p_role IN ('owner','admin')
  UNION ALL
  SELECT * FROM (VALUES
    ('inventory',true,true,true,false),('sales',true,true,true,false),('purchasing',true,true,true,false),
    ('production',true,true,true,false),('accounting',true,true,false,false),('hr',true,true,true,false),
    ('shipping',true,true,true,false),('projects',true,true,true,false),('maintenance',true,true,true,false),
    ('cash_bank',true,true,false,false)
  ) AS t(module,can_view,can_create,can_edit,can_delete) WHERE p_role = 'manager'
  UNION ALL
  SELECT * FROM (VALUES
    ('inventory',true,true,false,false),('sales',true,true,false,false),('purchasing',true,true,false,false),
    ('production',true,true,false,false),('accounting',false,false,false,false),('hr',false,false,false,false),
    ('shipping',true,true,false,false),('projects',true,true,false,false),('maintenance',true,true,false,false),
    ('cash_bank',false,false,false,false)
  ) AS t(module,can_view,can_create,can_edit,can_delete) WHERE p_role = 'employee'
  UNION ALL
  SELECT * FROM (VALUES
    ('inventory',true,false,false,false),('sales',true,false,false,false),('purchasing',true,false,false,false),
    ('production',false,false,false,false),('accounting',true,true,true,false),('hr',false,false,false,false),
    ('shipping',false,false,false,false),('projects',false,false,false,false),('maintenance',false,false,false,false),
    ('cash_bank',true,true,false,false)
  ) AS t(module,can_view,can_create,can_edit,can_delete) WHERE p_role = 'accountant';
$$;

-- 5. Insert default permissions for existing company_users
INSERT INTO user_permissions (company_id, user_id, module, can_view, can_create, can_edit, can_delete)
SELECT cu.company_id, cu.user_id, dp.module, dp.can_view, dp.can_create, dp.can_edit, dp.can_delete
FROM company_users cu
CROSS JOIN LATERAL get_default_permissions(cu.role) dp
ON CONFLICT (company_id, user_id, module) DO NOTHING;
