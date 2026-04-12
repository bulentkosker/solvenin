-- ============================================================
-- Migration 025: Fix repair RPCs — invoice_id → typed FKs
-- These RPCs still reference dropped invoice_id column
-- ============================================================

-- 1. Analyze missing sales stock
CREATE OR REPLACE FUNCTION sp_analyze_missing_sales_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT so.id), 0),
  'items', COALESCE(COUNT(soi.id), 0),
  'sample', COALESCE(json_agg(json_build_object('order_number', so.order_number, 'product_id', soi.product_id, 'quantity', soi.quantity)) FILTER (WHERE soi.id IS NOT NULL), '[]'::json)
) FROM sales_orders so
JOIN sales_order_items soi ON soi.order_id = so.id
LEFT JOIN products p ON p.id = soi.product_id
WHERE so.company_id = p_company_id
AND so.status IN ('invoiced','paid','overdue')
AND so.is_active = true
AND so.issue_date BETWEEN p_start AND p_end
AND soi.product_id IS NOT NULL
AND (p.is_service IS NOT TRUE)
AND NOT EXISTS (
  SELECT 1 FROM stock_movements sm
  WHERE sm.sales_order_id = so.id
  AND sm.product_id = soi.product_id
  AND sm.type IN ('out','sale')
  AND sm.is_active = true
);
$BODY$;

-- 2. Apply missing sales stock
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
    LEFT JOIN products p ON p.id = soi.product_id
    WHERE so.company_id = p_company_id
    AND so.status IN ('invoiced','paid','overdue')
    AND so.is_active = true
    AND so.issue_date BETWEEN p_start AND p_end
    AND soi.product_id IS NOT NULL
    AND (p.is_service IS NOT TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type IN ('out','sale') AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, sales_order_id, reference_type, notes, is_active, created_by)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, rec.order_id, 'sales_order', 'Auto-repair: missing sales movement', true, p_user_id);
    created_count := created_count + 1;
  END LOOP;

  orders_affected := (SELECT COUNT(DISTINCT sm.sales_order_id) FROM stock_movements sm
    WHERE sm.company_id = p_company_id AND sm.notes = 'Auto-repair: missing sales movement' AND sm.created_at > now() - interval '10 seconds');

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, affected_records, created_records, details)
  VALUES (p_company_id, 'missing_sales_stock', p_user_id, p_start, p_end, orders_affected, created_count, json_build_object('note', 'Sales stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'orders', orders_affected, 'created', created_count);
END;
$BODY$;

-- 3. Analyze missing purchase stock
CREATE OR REPLACE FUNCTION sp_analyze_missing_purchase_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT po.id), 0),
  'items', COALESCE(COUNT(poi.id), 0)
) FROM purchase_orders po
JOIN purchase_order_items poi ON poi.order_id = po.id
LEFT JOIN products p ON p.id = poi.product_id
WHERE po.company_id = p_company_id
AND po.status IN ('invoiced','paid','overdue','received')
AND po.is_active = true
AND po.issue_date BETWEEN p_start AND p_end
AND poi.product_id IS NOT NULL
AND (p.is_service IS NOT TRUE)
AND NOT EXISTS (
  SELECT 1 FROM stock_movements sm
  WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
);
$BODY$;

-- 4. Apply missing purchase stock
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
    LEFT JOIN products p ON p.id = poi.product_id
    WHERE po.company_id = p_company_id
    AND po.status IN ('invoiced','paid','overdue','received')
    AND po.is_active = true
    AND po.issue_date BETWEEN p_start AND p_end
    AND poi.product_id IS NOT NULL
    AND (p.is_service IS NOT TRUE)
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, purchase_order_id, reference_type, notes, is_active, created_by)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, rec.order_id, 'purchase_order', 'Auto-repair: missing purchase movement', true, p_user_id);
    created_count := created_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, created_records, details)
  VALUES (p_company_id, 'missing_purchase_stock', p_user_id, p_start, p_end, created_count, json_build_object('note', 'Purchase stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

-- 5. Link orphaned stock movements by matching reference = order_number
UPDATE stock_movements sm
SET sales_order_id = so.id, reference_type = 'sales_order'
FROM sales_orders so
WHERE sm.sales_order_id IS NULL
  AND sm.reference IS NOT NULL
  AND sm.reference = so.order_number
  AND so.company_id = sm.company_id
  AND so.is_active = true
  AND sm.is_active = true
  AND sm.type IN ('out', 'sale');

UPDATE stock_movements sm
SET purchase_order_id = po.id, reference_type = 'purchase_order'
FROM purchase_orders po
WHERE sm.purchase_order_id IS NULL
  AND sm.reference IS NOT NULL
  AND sm.reference = po.order_number
  AND po.company_id = sm.company_id
  AND po.is_active = true
  AND sm.is_active = true
  AND sm.type = 'in';

INSERT INTO migrations_log (file_name, notes)
VALUES ('025_fix_repair_rpcs.sql', 'Fix repair RPCs: invoice_id → sales_order_id/purchase_order_id, skip services, use reference_type, link orphaned movements')
ON CONFLICT (file_name) DO NOTHING;
