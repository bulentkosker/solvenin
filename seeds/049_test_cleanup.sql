-- 049_test_cleanup.sql
-- Add cleanup_at/cleanup_by columns to transactional tables for soft-delete
-- cleanup flow, and RPC functions for the service panel test data cleanup feature.

BEGIN;

-- cleanup_at/cleanup_by columns
DO $$ DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'sales_orders','purchase_orders','stock_movements',
    'cash_transactions','bank_transactions','contact_transactions',
    'journal_entries','payments','sales_order_items','purchase_order_items'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS cleanup_at timestamptz DEFAULT NULL', tbl);
    EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS cleanup_by uuid DEFAULT NULL', tbl);
  END LOOP;
END $$;

-- Get company info + record counts for cleanup preview
CREATE OR REPLACE FUNCTION sp_cleanup_preview(p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  r json;
BEGIN
  SELECT json_build_object(
    'company_name', c.name,
    'country_code', c.country_code,
    'plan', c.plan,
    'created_at', c.created_at,
    'owner_name', p.full_name,
    'owner_email', au.email,
    'sales', (SELECT COUNT(*) FROM sales_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL),
    'sales_total', (SELECT COALESCE(SUM(total),0) FROM sales_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL),
    'purchases', (SELECT COUNT(*) FROM purchase_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL),
    'purchases_total', (SELECT COALESCE(SUM(total),0) FROM purchase_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL),
    'movements', (SELECT COUNT(*) FROM stock_movements WHERE company_id=p_company_id AND cleanup_at IS NULL),
    'cash_txns', (SELECT COUNT(*) FROM cash_transactions WHERE company_id=p_company_id AND cleanup_at IS NULL),
    'bank_txns', (SELECT COUNT(*) FROM bank_transactions WHERE company_id=p_company_id AND cleanup_at IS NULL),
    'contact_txns', (SELECT COUNT(*) FROM contact_transactions WHERE company_id=p_company_id AND cleanup_at IS NULL),
    'journal_entries', (SELECT COUNT(*) FROM journal_entries WHERE company_id=p_company_id AND cleanup_at IS NULL),
    'payments', (SELECT COUNT(*) FROM payments WHERE company_id=p_company_id AND cleanup_at IS NULL)
  ) INTO r
  FROM companies c
  LEFT JOIN company_users cu ON cu.company_id = c.id AND cu.role = 'owner'
  LEFT JOIN profiles p ON p.id = cu.user_id
  LEFT JOIN auth.users au ON au.id = cu.user_id
  WHERE c.id = p_company_id;
  RETURN r;
END;
$BODY$;

-- Execute cleanup: soft-delete all transactional data for a company
CREATE OR REPLACE FUNCTION sp_cleanup_execute(
  p_company_id uuid,
  p_sp_user_id uuid,
  p_scope text DEFAULT 'all'
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  counts jsonb := '{}'::jsonb;
  cnt int;
BEGIN
  IF p_scope IN ('all','sales') THEN
    UPDATE sales_order_items SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE sales_order_id IN (SELECT id FROM sales_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL);
    UPDATE sales_orders SET cleanup_at=now(), cleanup_by=p_sp_user_id, deleted_at=now()
    WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('sales', cnt);
  END IF;

  IF p_scope IN ('all','purchases') THEN
    UPDATE purchase_order_items SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL);
    UPDATE purchase_orders SET cleanup_at=now(), cleanup_by=p_sp_user_id, deleted_at=now()
    WHERE company_id=p_company_id AND deleted_at IS NULL AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('purchases', cnt);
  END IF;

  IF p_scope IN ('all','movements') THEN
    UPDATE stock_movements SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('movements', cnt);
  END IF;

  IF p_scope IN ('all','cash_bank') THEN
    UPDATE cash_transactions SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('cash_txns', cnt);
    UPDATE bank_transactions SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('bank_txns', cnt);
  END IF;

  IF p_scope IN ('all','contacts') THEN
    UPDATE contact_transactions SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('contact_txns', cnt);
  END IF;

  IF p_scope IN ('all','finance') THEN
    UPDATE payments SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('payments', cnt);
    UPDATE journal_entries SET cleanup_at=now(), cleanup_by=p_sp_user_id
    WHERE company_id=p_company_id AND cleanup_at IS NULL;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    counts := counts || jsonb_build_object('journal_entries', cnt);
  END IF;

  INSERT INTO service_panel_logs (user_id, action, target_company_id, details)
  VALUES (p_sp_user_id, 'test_data_cleanup', p_company_id,
    jsonb_build_object('scope', p_scope, 'counts', counts, 'auto_delete_at', (now() + interval '7 days')::text));

  RETURN json_build_object('ok', true, 'counts', counts);
END;
$BODY$;

-- Restore cleaned-up data
CREATE OR REPLACE FUNCTION sp_cleanup_restore(p_company_id uuid, p_sp_user_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE cnt int; total int := 0;
BEGIN
  UPDATE sales_orders SET deleted_at=NULL, cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE sales_order_items SET cleanup_at=NULL, cleanup_by=NULL
  WHERE cleanup_at IS NOT NULL AND sales_order_id IN (SELECT id FROM sales_orders WHERE company_id=p_company_id);

  UPDATE purchase_orders SET deleted_at=NULL, cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE purchase_order_items SET cleanup_at=NULL, cleanup_by=NULL
  WHERE cleanup_at IS NOT NULL AND purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id=p_company_id);

  UPDATE stock_movements SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE cash_transactions SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE bank_transactions SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE contact_transactions SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE payments SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE journal_entries SET cleanup_at=NULL, cleanup_by=NULL
  WHERE company_id=p_company_id AND cleanup_at IS NOT NULL;
  GET DIAGNOSTICS cnt = ROW_COUNT; total := total + cnt;

  UPDATE service_panel_logs SET details = details || jsonb_build_object('restored_at', now()::text, 'restored_by', p_sp_user_id::text)
  WHERE target_company_id=p_company_id AND action='test_data_cleanup'
    AND (details->>'restored_at') IS NULL
  ORDER BY created_at DESC LIMIT 1;

  INSERT INTO service_panel_logs (user_id, action, target_company_id, details)
  VALUES (p_sp_user_id, 'test_data_restore', p_company_id, jsonb_build_object('restored', total));

  RETURN json_build_object('ok', true, 'restored', total);
END;
$BODY$;

-- List recent cleanups (for restore UI)
CREATE OR REPLACE FUNCTION sp_cleanup_list()
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::json) FROM (
  SELECT sl.id, sl.created_at, sl.details, c.name as company_name, c.id as company_id,
    spu.name as performed_by_name
  FROM service_panel_logs sl
  LEFT JOIN companies c ON c.id = sl.target_company_id
  LEFT JOIN service_panel_users spu ON spu.id = sl.user_id
  WHERE sl.action = 'test_data_cleanup'
    AND (sl.details->>'restored_at') IS NULL
  ORDER BY sl.created_at DESC LIMIT 20
) r;
$BODY$;

-- Hard delete expired cleanups (called on panel load)
CREATE OR REPLACE FUNCTION sp_cleanup_purge_expired()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  r RECORD; purged int := 0;
BEGIN
  FOR r IN
    SELECT target_company_id, id
    FROM service_panel_logs
    WHERE action='test_data_cleanup'
      AND (details->>'restored_at') IS NULL
      AND (details->>'auto_delete_at')::timestamptz < now()
  LOOP
    DELETE FROM sales_order_items WHERE cleanup_at IS NOT NULL
      AND sales_order_id IN (SELECT id FROM sales_orders WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL);
    DELETE FROM sales_orders WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM purchase_order_items WHERE cleanup_at IS NOT NULL
      AND purchase_order_id IN (SELECT id FROM purchase_orders WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL);
    DELETE FROM purchase_orders WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM stock_movements WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM cash_transactions WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM bank_transactions WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM contact_transactions WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM payments WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    DELETE FROM journal_entries WHERE company_id=r.target_company_id AND cleanup_at IS NOT NULL;
    UPDATE service_panel_logs SET details = details || '{"purged": true}'::jsonb WHERE id = r.id;
    purged := purged + 1;
  END LOOP;
  RETURN json_build_object('purged', purged);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('049_test_cleanup.sql',
  'cleanup_at/cleanup_by cols on transactional tables + sp_cleanup_* RPCs for service panel test data cleanup')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
