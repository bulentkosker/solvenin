-- ============================================================
-- Migration 022: get_contact_balance RPC + get_all_contact_balances
-- Matches loadStatement() logic in contacts.html exactly
-- ============================================================

CREATE OR REPLACE FUNCTION get_contact_balance(
  p_contact_id uuid,
  p_company_id uuid
)
RETURNS TABLE(total_debit numeric, total_credit numeric, balance numeric)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_debit numeric := 0;
  v_credit numeric := 0;
  v_is_customer boolean;
  v_is_supplier boolean;
BEGIN
  SELECT is_customer, is_supplier INTO v_is_customer, v_is_supplier
  FROM contacts WHERE id = p_contact_id AND company_id = p_company_id;

  -- 1. Sales invoices → debit (customer owes us)
  IF v_is_customer THEN
    SELECT COALESCE(SUM(total), 0) INTO v_debit
    FROM sales_orders
    WHERE company_id = p_company_id
      AND customer_id = p_contact_id
      AND is_active = true
      AND status IN ('invoiced', 'paid', 'overdue');
  END IF;

  -- 2. Purchase invoices → credit (we owe supplier)
  IF v_is_supplier THEN
    SELECT COALESCE(SUM(total), 0) INTO v_credit
    FROM purchase_orders
    WHERE company_id = p_company_id
      AND supplier_id = p_contact_id
      AND is_active = true
      AND status IN ('invoiced', 'paid', 'overdue');
  END IF;

  -- 3. Sale payments (tahsilat) → credit
  IF v_is_customer THEN
    v_credit := v_credit + COALESCE((
      SELECT SUM(p.amount)
      FROM payments p
      JOIN sales_orders so ON so.id = p.order_id
      WHERE p.company_id = p_company_id
        AND so.customer_id = p_contact_id
    ), 0);
  END IF;

  -- 4. Purchase payments (ödeme) → debit
  IF v_is_supplier THEN
    v_debit := v_debit + COALESCE((
      SELECT SUM(p.amount)
      FROM payments p
      JOIN purchase_orders po ON po.id = p.purchase_order_id
      WHERE p.company_id = p_company_id
        AND po.supplier_id = p_contact_id
    ), 0);
  END IF;

  -- 5. Manual contact_transactions
  v_debit := v_debit + COALESCE((
    SELECT SUM(amount) FROM contact_transactions
    WHERE company_id = p_company_id AND contact_id = p_contact_id
      AND is_active = true AND type = 'debit'
  ), 0);

  v_credit := v_credit + COALESCE((
    SELECT SUM(amount) FROM contact_transactions
    WHERE company_id = p_company_id AND contact_id = p_contact_id
      AND is_active = true AND type = 'credit'
  ), 0);

  RETURN QUERY SELECT v_debit, v_credit, v_debit - v_credit;
END;
$$;

-- Batch version for service panel / contact list
CREATE OR REPLACE FUNCTION get_all_contact_balances(p_company_id uuid)
RETURNS TABLE(
  contact_id uuid,
  contact_name text,
  is_customer boolean,
  is_supplier boolean,
  total_debit numeric,
  total_credit numeric,
  balance numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id,
    c.name::text,
    c.is_customer,
    c.is_supplier,
    b.total_debit,
    b.total_credit,
    b.balance
  FROM contacts c
  CROSS JOIN LATERAL get_contact_balance(c.id, p_company_id) b
  WHERE c.company_id = p_company_id
    AND c.is_active = true
    AND c.deleted_at IS NULL
    AND b.balance != 0;
END;
$$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('022_contact_balance_rpc.sql',
  'Add get_contact_balance and get_all_contact_balances RPC functions matching loadStatement logic')
ON CONFLICT (file_name) DO NOTHING;
