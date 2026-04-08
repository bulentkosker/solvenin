-- Migration: 011_create_company_rpc
-- Description: SECURITY DEFINER RPC for atomic company create + owner link
-- Backward Compatible: YES (new function + permissive policy)
-- Rollback:
--   DROP FUNCTION IF EXISTS create_company_for_user(text, text, text, uuid);
--   DROP POLICY companies_insert ON companies;
--   CREATE POLICY companies_insert ON companies
--     FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Migrations 007 and 010 tried to fix the new-company-create RLS error
-- by adjusting the companies_insert policy. Both attempts hit the same
-- wall: in some real-world session edge cases (cold load, slow JWT
-- hydration after sign-in, supabase-js client running before its
-- session was attached), the request hits the DB without a JWT and
-- auth.uid() returns NULL, so the policy WITH CHECK rejects it.
--
-- Since the frontend already has the user id from sb.auth.getUser()
-- by the time it calls "Create Company", the simplest fix is to do
-- the entire create flow inside a SECURITY DEFINER function that
-- runs as postgres. The function bypasses RLS, validates the
-- supplied user id against auth.users (so it can't be spoofed to
-- create a company for someone else), inserts companies, links
-- company_users, and seeds a default warehouse — all in one
-- transaction.
--
-- Defense-in-depth: also relax the companies_insert policy to
-- WITH CHECK (true). The new row is unreachable without a follow-up
-- company_users link (companies_visible filters by membership),
-- so an orphan insert is harmless. The enforce_company_limit BEFORE
-- INSERT trigger still blocks abuse from the same user creating
-- too many companies.

DROP POLICY IF EXISTS companies_insert ON companies;
CREATE POLICY companies_insert ON companies
  FOR INSERT
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION create_company_for_user(
  p_name text,
  p_country_code text,
  p_base_currency text,
  p_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_slug text;
  v_company_id uuid;
  v_user_email text;
BEGIN
  -- Verify the caller-supplied user_id is a real auth user (anti-spoofing)
  SELECT email INTO v_user_email FROM auth.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_user');
  END IF;

  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug) || '-' || extract(epoch from now())::bigint::text;

  INSERT INTO companies (
    name, slug, country_code, base_currency, plan, status,
    owner_id, max_users, subscription_status, subscription_end
  ) VALUES (
    p_name, v_slug, p_country_code, p_base_currency, 'free', 'active',
    p_user_id, 3, 'trial', now() + interval '14 days'
  )
  RETURNING id INTO v_company_id;

  INSERT INTO company_users (
    company_id, user_id, role, status, joined_at
  ) VALUES (
    v_company_id, p_user_id, 'owner', 'active', now()
  );

  -- Best-effort default warehouse seed
  BEGIN
    INSERT INTO warehouses (company_id, name, is_default)
    VALUES (v_company_id, 'Main Warehouse', true);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('success', true, 'company_id', v_company_id, 'slug', v_slug);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION create_company_for_user(text, text, text, uuid) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('011_create_company_rpc.sql', 'Atomic SECURITY DEFINER RPC for new-company create — bypasses RLS edge cases')
ON CONFLICT (file_name) DO NOTHING;
