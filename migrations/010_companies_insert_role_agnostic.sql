-- Migration: 010_companies_insert_role_agnostic
-- Description: Replace TO authenticated with auth.uid() IS NOT NULL gate
-- Backward Compatible: YES (loosens role restriction, tightens with check)
-- Rollback:
--   DROP POLICY companies_insert ON companies;
--   CREATE POLICY companies_insert ON companies
--     FOR INSERT TO authenticated WITH CHECK (true);

-- The previous migration 007 created companies_insert with TO authenticated
-- WITH CHECK true. That worked when PostgREST elevated the connection to
-- the authenticated role, but real-world reports show this isn't always
-- the case — in some session edge cases (cold load, slow JWT hydration,
-- etc.) the request hits the DB as anon, the policy doesn't fire, and
-- the default-deny kicks in with "new row violates RLS policy".
--
-- Fix: drop the TO restriction so the policy applies to ALL roles
-- (anon and authenticated). The actual gate becomes auth.uid() IS NOT NULL
-- — this returns NULL when no JWT claims are set, so anonymous attempts
-- still fail (verified). Authenticated users with a valid Supabase Auth
-- session always have auth.uid() = their user id, so they pass.
--
-- This is functionally equivalent to TO authenticated WITH CHECK true,
-- but more robust against edge cases in PostgREST role elevation.

DROP POLICY IF EXISTS companies_insert ON companies;
CREATE POLICY companies_insert ON companies
  FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

INSERT INTO migrations_log (file_name, notes)
VALUES ('010_companies_insert_role_agnostic.sql', 'Use auth.uid() IS NOT NULL instead of TO authenticated for new-company insert')
ON CONFLICT (file_name) DO NOTHING;
