-- 053_fix_repair_analysis_details.sql
-- Return detailed records (order_number, issue_date, contact_name, product_name, quantity)
-- from analyze functions so the service panel can show a proper table.

BEGIN;

CREATE OR REPLACE FUNCTION sp_analyze_missing_sales_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
WITH missing AS (
  SELECT so.id as order_id, so.order_number, so.issue_date,
    c.name as contact_name, p.name as product_name, soi.quantity, p.unit
  FROM sales_orders so
  JOIN sales_order_items soi ON soi.order_id = so.id
  LEFT JOIN contacts c ON c.id = so.customer_id
  LEFT JOIN products p ON p.id = soi.product_id
  WHERE so.company_id = p_company_id
  AND so.status IN ('invoiced','paid','overdue')
  AND so.is_active = true
  AND so.issue_date BETWEEN p_start AND p_end
  AND soi.product_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM stock_movements sm
    WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
  )
)
SELECT json_build_object(
  'orders', (SELECT COUNT(DISTINCT order_id) FROM missing),
  'items', (SELECT COUNT(*) FROM missing),
  'details', COALESCE((SELECT json_agg(row_to_json(m) ORDER BY m.issue_date, m.order_number) FROM missing m), '[]'::json)
);
$BODY$;

CREATE OR REPLACE FUNCTION sp_analyze_missing_purchase_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
WITH missing AS (
  SELECT po.id as order_id, po.order_number, po.issue_date,
    c.name as contact_name, p.name as product_name, poi.quantity, p.unit
  FROM purchase_orders po
  JOIN purchase_order_items poi ON poi.order_id = po.id
  LEFT JOIN contacts c ON c.id = po.supplier_id
  LEFT JOIN products p ON p.id = poi.product_id
  WHERE po.company_id = p_company_id
  AND po.status IN ('invoiced','paid','overdue','received')
  AND po.is_active = true
  AND po.issue_date BETWEEN p_start AND p_end
  AND poi.product_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM stock_movements sm
    WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
  )
)
SELECT json_build_object(
  'orders', (SELECT COUNT(DISTINCT order_id) FROM missing),
  'items', (SELECT COUNT(*) FROM missing),
  'details', COALESCE((SELECT json_agg(row_to_json(m) ORDER BY m.issue_date, m.order_number) FROM missing m), '[]'::json)
);
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('053_fix_repair_analysis_details.sql',
  'Analyze functions now return full details array with order_number, issue_date, contact_name, product_name, quantity, unit')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
