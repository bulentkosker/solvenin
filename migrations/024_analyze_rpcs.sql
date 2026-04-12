-- ============================================================
-- Migration 024: Analyze RPCs for 2-step repair tools
-- ============================================================

-- 1. Analyze stock discrepancies
CREATE OR REPLACE FUNCTION sp_analyze_stock_discrepancies(p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  items json;
  cnt int;
BEGIN
  WITH calc AS (
    SELECT p.id, p.name, p.quantity AS current_qty,
      COALESCE(SUM(CASE WHEN sm.type IN ('in','return') THEN sm.quantity ELSE -sm.quantity END), 0) AS calc_qty
    FROM products p
    LEFT JOIN stock_movements sm ON sm.product_id = p.id AND sm.is_active = true AND sm.company_id = p_company_id
    WHERE p.company_id = p_company_id AND p.is_active = true AND p.is_service = false
    GROUP BY p.id, p.name, p.quantity
  )
  SELECT json_agg(json_build_object(
    'id', id, 'name', name,
    'current', current_qty, 'calculated', calc_qty,
    'diff', calc_qty - current_qty
  )), count(*)
  INTO items, cnt
  FROM calc WHERE calc_qty != current_qty;

  RETURN json_build_object('count', COALESCE(cnt, 0), 'items', COALESCE(items, '[]'::json));
END;
$$;

-- 2. Analyze cash register discrepancies
CREATE OR REPLACE FUNCTION sp_analyze_cash_discrepancies(p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  items json;
  cnt int;
BEGIN
  WITH calc AS (
    SELECT cr.id, cr.name, cr.current_balance AS current_bal,
      COALESCE(cr.opening_balance, 0) + COALESCE(SUM(CASE WHEN ct.type = 'in' THEN ct.amount ELSE -ct.amount END), 0) AS calc_bal
    FROM cash_registers cr
    LEFT JOIN cash_transactions ct ON ct.register_id = cr.id AND ct.company_id = p_company_id
    WHERE cr.company_id = p_company_id AND cr.is_active = true
    GROUP BY cr.id, cr.name, cr.current_balance, cr.opening_balance
  )
  SELECT json_agg(json_build_object(
    'id', id, 'name', name,
    'current', current_bal, 'calculated', calc_bal,
    'diff', calc_bal - current_bal
  )), count(*)
  INTO items, cnt
  FROM calc WHERE calc_bal != current_bal;

  RETURN json_build_object('count', COALESCE(cnt, 0), 'items', COALESCE(items, '[]'::json));
END;
$$;

-- 3. Analyze bank account discrepancies
CREATE OR REPLACE FUNCTION sp_analyze_bank_discrepancies(p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  items json;
  cnt int;
BEGIN
  WITH calc AS (
    SELECT ba.id, ba.account_name AS name, ba.current_balance AS current_bal,
      COALESCE(ba.opening_balance, 0) + COALESCE(SUM(CASE WHEN bt.type = 'in' THEN bt.amount ELSE -bt.amount END), 0) AS calc_bal
    FROM bank_accounts ba
    LEFT JOIN bank_transactions bt ON bt.account_id = ba.id AND bt.company_id = p_company_id
    WHERE ba.company_id = p_company_id AND ba.is_active = true
    GROUP BY ba.id, ba.account_name, ba.current_balance, ba.opening_balance
  )
  SELECT json_agg(json_build_object(
    'id', id, 'name', name,
    'current', current_bal, 'calculated', calc_bal,
    'diff', calc_bal - current_bal
  )), count(*)
  INTO items, cnt
  FROM calc WHERE calc_bal != current_bal;

  RETURN json_build_object('count', COALESCE(cnt, 0), 'items', COALESCE(items, '[]'::json));
END;
$$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('024_analyze_rpcs.sql', 'Add sp_analyze_stock/cash/bank_discrepancies RPCs for 2-step repair')
ON CONFLICT (file_name) DO NOTHING;
