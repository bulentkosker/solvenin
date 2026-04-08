-- Migration: 008_account_state_rpc
-- Description: Single-call account state helper for the dashboard onboarding gate
-- Backward Compatible: YES (new function, no schema changes)
-- Rollback:
--   DROP FUNCTION IF EXISTS get_my_account_state();

-- UP
CREATE OR REPLACE FUNCTION get_my_account_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total int;
  v_active int;
  v_deleted jsonb;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM company_users
  WHERE user_id = auth.uid();

  IF v_total = 0 THEN
    RETURN jsonb_build_object('state', 'first_time');
  END IF;

  SELECT COUNT(*) INTO v_active
  FROM company_users cu
  JOIN companies c ON c.id = cu.company_id
  WHERE cu.user_id = auth.uid()
    AND c.deleted_at IS NULL;

  IF v_active > 0 THEN
    RETURN jsonb_build_object('state', 'has_active');
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', c.id,
    'name', c.name,
    'deleted_at', c.deleted_at,
    'days_left', GREATEST(0, EXTRACT(DAY FROM (c.deleted_at + interval '30 days' - now()))::int)
  ) ORDER BY c.deleted_at DESC)
  INTO v_deleted
  FROM company_users cu
  JOIN companies c ON c.id = cu.company_id
  WHERE cu.user_id = auth.uid()
    AND c.deleted_at IS NOT NULL;

  RETURN jsonb_build_object('state', 'all_deleted', 'companies', COALESCE(v_deleted, '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_account_state() TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('008_account_state_rpc.sql', 'Single-call account state helper (first_time / all_deleted / has_active)')
ON CONFLICT (file_name) DO NOTHING;
