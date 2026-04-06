-- ===== STOK ONARIMI =====

-- 1. Eksik stok hareketleri analizi (satış)
CREATE OR REPLACE FUNCTION sp_analyze_missing_sales_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT so.id), 0),
  'items', COALESCE(COUNT(soi.id), 0),
  'sample', COALESCE(json_agg(json_build_object('order_number', so.order_number, 'product_id', soi.product_id, 'quantity', soi.quantity)) FILTER (WHERE soi.id IS NOT NULL), '[]'::json)
) FROM sales_orders so
JOIN sales_order_items soi ON soi.order_id = so.id
WHERE so.company_id = p_company_id
AND so.status IN ('invoiced','paid','overdue')
AND so.is_active = true
AND so.issue_date BETWEEN p_start AND p_end
AND soi.product_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM stock_movements sm
  WHERE sm.invoice_id = so.id
  AND sm.product_id = soi.product_id
  AND sm.type = 'out'
  AND sm.is_active = true
);
$BODY$;

-- 2. Eksik stok hareketleri uygulama (satış)
CREATE OR REPLACE FUNCTION sp_apply_missing_sales_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  orders_affected int := 0;
  rec RECORD;
  default_wh uuid;
BEGIN
  SELECT id INTO default_wh FROM warehouses WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT DISTINCT so.id as order_id, so.order_number, soi.product_id, soi.quantity, soi.warehouse_id
    FROM sales_orders so
    JOIN sales_order_items soi ON soi.order_id = so.id
    WHERE so.company_id = p_company_id
    AND so.status IN ('invoiced','paid','overdue')
    AND so.is_active = true
    AND so.issue_date BETWEEN p_start AND p_end
    AND soi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.invoice_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, invoice_id, notes, is_active)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, rec.order_id, 'Auto-repair: missing sales movement', true);
    created_count := created_count + 1;
  END LOOP;

  SELECT COUNT(DISTINCT so.id) INTO orders_affected FROM sales_orders so
  JOIN stock_movements sm ON sm.invoice_id = so.id
  WHERE so.company_id = p_company_id
  AND sm.notes = 'Auto-repair: missing sales movement'
  AND sm.created_at > now() - interval '10 seconds';

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, affected_records, created_records, details)
  VALUES (p_company_id, 'missing_sales_stock', p_user_id, p_start, p_end, orders_affected, created_count, json_build_object('note', 'Sales stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'orders', orders_affected, 'created', created_count);
END;
$BODY$;

-- 3. Eksik stok hareketleri analizi (alış)
CREATE OR REPLACE FUNCTION sp_analyze_missing_purchase_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT po.id), 0),
  'items', COALESCE(COUNT(poi.id), 0)
) FROM purchase_orders po
JOIN purchase_order_items poi ON poi.order_id = po.id
WHERE po.company_id = p_company_id
AND po.status IN ('invoiced','paid','overdue','received')
AND po.is_active = true
AND po.issue_date BETWEEN p_start AND p_end
AND poi.product_id IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM stock_movements sm
  WHERE sm.invoice_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
);
$BODY$;

-- 4. Eksik stok hareketleri uygulama (alış)
CREATE OR REPLACE FUNCTION sp_apply_missing_purchase_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  rec RECORD;
  default_wh uuid;
BEGIN
  SELECT id INTO default_wh FROM warehouses WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT po.id as order_id, po.order_number, poi.product_id, poi.quantity
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.order_id = po.id
    WHERE po.company_id = p_company_id
    AND po.status IN ('invoiced','paid','overdue','received')
    AND po.is_active = true
    AND po.issue_date BETWEEN p_start AND p_end
    AND poi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.invoice_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, invoice_id, notes, is_active)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, rec.order_id, 'Auto-repair: missing purchase movement', true);
    created_count := created_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, created_records, details)
  VALUES (p_company_id, 'missing_purchase_stock', p_user_id, p_start, p_end, created_count, json_build_object('note', 'Purchase stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

-- 5. Stok bakiyelerini yeniden hesapla
CREATE OR REPLACE FUNCTION sp_recalc_product_stock(p_user_id uuid, p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  updated_count int := 0;
  rec RECORD;
  new_qty numeric;
BEGIN
  FOR rec IN SELECT id FROM products WHERE company_id = p_company_id AND is_active = true LOOP
    SELECT COALESCE(SUM(CASE WHEN type = 'in' OR type = 'return' THEN quantity ELSE -quantity END), 0)
    INTO new_qty
    FROM stock_movements
    WHERE product_id = rec.id AND is_active = true AND company_id = p_company_id;

    UPDATE products SET quantity = new_qty WHERE id = rec.id;
    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, affected_records, details)
  VALUES (p_company_id, 'recalc_product_stock', p_user_id, updated_count, json_build_object('note', 'Product quantities recalculated')::jsonb);

  RETURN json_build_object('ok', true, 'updated', updated_count);
END;
$BODY$;

-- 6. Mizan kontrolü
CREATE OR REPLACE FUNCTION sp_check_trial_balance(p_company_id uuid, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'total_debit', COALESCE(SUM(jl.debit), 0),
  'total_credit', COALESCE(SUM(jl.credit), 0),
  'difference', COALESCE(SUM(jl.debit) - SUM(jl.credit), 0),
  'balanced', (COALESCE(SUM(jl.debit), 0) = COALESCE(SUM(jl.credit), 0))
) FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.company_id = p_company_id
AND je.entry_date <= p_end;
$BODY$;

-- 7. Kasa bakiyelerini yeniden hesapla
CREATE OR REPLACE FUNCTION sp_recalc_cash_balances(p_user_id uuid, p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  updated_count int := 0;
  rec RECORD;
  new_bal numeric;
BEGIN
  FOR rec IN SELECT id, opening_balance FROM cash_registers WHERE company_id = p_company_id AND is_active = true LOOP
    SELECT COALESCE(rec.opening_balance, 0) + COALESCE(SUM(CASE WHEN type = 'in' THEN amount ELSE -amount END), 0)
    INTO new_bal
    FROM cash_transactions
    WHERE register_id = rec.id AND company_id = p_company_id;

    UPDATE cash_registers SET current_balance = new_bal WHERE id = rec.id;
    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, affected_records, details)
  VALUES (p_company_id, 'recalc_cash_balances', p_user_id, updated_count, json_build_object('note', 'Cash register balances recalculated')::jsonb);

  RETURN json_build_object('ok', true, 'updated', updated_count);
END;
$BODY$;

-- 8. Banka bakiyelerini yeniden hesapla
CREATE OR REPLACE FUNCTION sp_recalc_bank_balances(p_user_id uuid, p_company_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  updated_count int := 0;
  rec RECORD;
  new_bal numeric;
BEGIN
  FOR rec IN SELECT id, opening_balance FROM bank_accounts WHERE company_id = p_company_id AND is_active = true LOOP
    SELECT COALESCE(rec.opening_balance, 0) + COALESCE(SUM(CASE WHEN type = 'in' THEN amount ELSE -amount END), 0)
    INTO new_bal
    FROM bank_transactions
    WHERE account_id = rec.id AND company_id = p_company_id;

    UPDATE bank_accounts SET current_balance = new_bal WHERE id = rec.id;
    updated_count := updated_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, affected_records, details)
  VALUES (p_company_id, 'recalc_bank_balances', p_user_id, updated_count, json_build_object('note', 'Bank account balances recalculated')::jsonb);

  RETURN json_build_object('ok', true, 'updated', updated_count);
END;
$BODY$;

-- 9. Cari bakiye kontrolü
CREATE OR REPLACE FUNCTION sp_check_contact_balances(p_company_id uuid)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
WITH contact_calc AS (
  SELECT
    c.id, c.name, c.is_customer, c.is_supplier,
    COALESCE((SELECT SUM(so.total) FROM sales_orders so WHERE so.customer_id = c.id AND so.is_active=true AND so.status IN ('invoiced','paid','overdue')), 0) as sales_total,
    COALESCE((SELECT SUM(po.total) FROM purchase_orders po WHERE po.supplier_id = c.id AND po.is_active=true AND po.status IN ('invoiced','paid','overdue')), 0) as purchase_total,
    COALESCE((SELECT SUM(p.amount) FROM payments p JOIN sales_orders so ON so.id = p.order_id WHERE so.customer_id = c.id), 0) as received,
    COALESCE((SELECT SUM(p.amount) FROM payments p JOIN purchase_orders po ON po.id = p.order_id WHERE po.supplier_id = c.id), 0) as paid
  FROM contacts c
  WHERE c.company_id = p_company_id AND c.is_active = true
)
SELECT COALESCE(json_agg(json_build_object(
  'id', id, 'name', name,
  'is_customer', is_customer, 'is_supplier', is_supplier,
  'sales', sales_total, 'received', received,
  'purchase', purchase_total, 'paid', paid,
  'customer_balance', sales_total - received,
  'supplier_balance', purchase_total - paid
)), '[]'::json)
FROM contact_calc
WHERE (sales_total - received) != 0 OR (purchase_total - paid) != 0;
$BODY$;

-- 10. Repair logs listesi
CREATE OR REPLACE FUNCTION sp_repair_history(p_company_id uuid)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::json) FROM (
  SELECT rl.id, rl.repair_type, rl.date_range_start, rl.date_range_end,
    rl.analyzed_records, rl.affected_records, rl.created_records, rl.created_at,
    spu.name as performed_by_name
  FROM repair_logs rl
  LEFT JOIN service_panel_users spu ON spu.id = rl.performed_by
  WHERE rl.company_id = p_company_id
  ORDER BY rl.created_at DESC
  LIMIT 50
) r;
$BODY$;
