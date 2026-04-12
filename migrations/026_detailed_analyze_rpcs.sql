-- ============================================================
-- Migration 026: Detailed analyze RPCs — return full row info
-- ============================================================

-- 1. Analyze missing sales stock — full details
CREATE OR REPLACE FUNCTION sp_analyze_missing_sales_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT so.id), 0),
  'items', COALESCE(COUNT(soi.id), 0),
  'details', COALESCE(json_agg(json_build_object(
    'order_number', so.order_number,
    'issue_date', so.issue_date,
    'contact_name', COALESCE(c.name, '—'),
    'product_name', COALESCE(p.name, '—'),
    'quantity', soi.quantity
  ) ORDER BY so.issue_date, so.order_number) FILTER (WHERE soi.id IS NOT NULL), '[]'::json)
) FROM sales_orders so
JOIN sales_order_items soi ON soi.order_id = so.id
LEFT JOIN products p ON p.id = soi.product_id
LEFT JOIN contacts c ON c.id = so.customer_id
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

-- 2. Analyze missing purchase stock — full details
CREATE OR REPLACE FUNCTION sp_analyze_missing_purchase_stock(p_company_id uuid, p_start date, p_end date)
RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT json_build_object(
  'orders', COALESCE(COUNT(DISTINCT po.id), 0),
  'items', COALESCE(COUNT(poi.id), 0),
  'details', COALESCE(json_agg(json_build_object(
    'order_number', po.order_number,
    'issue_date', po.issue_date,
    'contact_name', COALESCE(c.name, '—'),
    'product_name', COALESCE(p.name, '—'),
    'quantity', poi.quantity
  ) ORDER BY po.issue_date, po.order_number) FILTER (WHERE poi.id IS NOT NULL), '[]'::json)
) FROM purchase_orders po
JOIN purchase_order_items poi ON poi.order_id = po.id
LEFT JOIN products p ON p.id = poi.product_id
LEFT JOIN contacts c ON c.id = po.supplier_id
WHERE po.company_id = p_company_id
AND po.status IN ('invoiced','paid','overdue','received')
AND po.is_active = true
AND po.issue_date BETWEEN p_start AND p_end
AND poi.product_id IS NOT NULL
AND (p.is_service IS NOT TRUE)
AND NOT EXISTS (
  SELECT 1 FROM stock_movements sm
  WHERE sm.purchase_order_id = po.id
  AND sm.product_id = poi.product_id
  AND sm.type = 'in'
  AND sm.is_active = true
);
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('026_detailed_analyze_rpcs.sql', 'Analyze RPCs now return full details: order_number, date, contact_name, product_name, quantity')
ON CONFLICT (file_name) DO NOTHING;
