-- 052_fix_repair_column_names.sql
-- Fix: stock_movements has sales_order_id/purchase_order_id, not invoice_id.

BEGIN;

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
  WHERE sm.sales_order_id = so.id
  AND sm.product_id = soi.product_id
  AND sm.type = 'out'
  AND sm.is_active = true
);
$BODY$;

CREATE OR REPLACE FUNCTION sp_apply_missing_sales_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  orders_affected int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu
    WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true
  ORDER BY is_default DESC NULLS LAST LIMIT 1;

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
      WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, sales_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  SELECT COUNT(DISTINCT sm.sales_order_id) INTO orders_affected
  FROM stock_movements sm
  WHERE sm.company_id = p_company_id
  AND sm.reference_type = 'repair'
  AND sm.created_at > now() - interval '10 seconds';

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, affected_records, created_records, details)
  VALUES (p_company_id, 'missing_sales_stock', p_user_id, p_start, p_end, orders_affected, created_count, json_build_object('note', 'Sales stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'orders', orders_affected, 'created', created_count);
END;
$BODY$;

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
  WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
);
$BODY$;

CREATE OR REPLACE FUNCTION sp_apply_missing_purchase_stock(p_user_id uuid, p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu
    WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true
  ORDER BY is_default DESC NULLS LAST LIMIT 1;

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
      WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, purchase_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, rec.order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  INSERT INTO repair_logs (company_id, repair_type, performed_by, date_range_start, date_range_end, created_records, details)
  VALUES (p_company_id, 'missing_purchase_stock', p_user_id, p_start, p_end, created_count, json_build_object('note', 'Purchase stock movements created')::jsonb);

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('052_fix_repair_column_names.sql',
  'Fix: invoice_id → sales_order_id/purchase_order_id in all repair functions')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
