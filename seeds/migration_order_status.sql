-- ============================================================
-- Migration: Extended order status + invoice flow
-- Run in Supabase SQL Editor
-- ============================================================

ALTER TABLE sales_orders DROP CONSTRAINT IF EXISTS sales_orders_status_check;
ALTER TABLE sales_orders ADD CONSTRAINT sales_orders_status_check
  CHECK (status IN ('draft','confirmed','invoiced','paid','overdue','cancelled'));

ALTER TABLE purchase_orders DROP CONSTRAINT IF EXISTS purchase_orders_status_check;
ALTER TABLE purchase_orders ADD CONSTRAINT purchase_orders_status_check
  CHECK (status IN ('draft','confirmed','invoiced','paid','cancelled'));

-- Update invoice count function: only count invoiced/paid/overdue (not drafts/confirmed)
CREATE OR REPLACE FUNCTION get_monthly_invoice_count(p_company_id uuid)
RETURNS int
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT COUNT(*)::int
  FROM (
    SELECT id FROM sales_orders
    WHERE company_id = p_company_id
    AND created_at >= date_trunc('month', now())
    AND is_active = true
    AND status IN ('invoiced','paid','overdue')

    UNION ALL

    SELECT id FROM purchase_orders
    WHERE company_id = p_company_id
    AND created_at >= date_trunc('month', now())
    AND is_active = true
    AND status IN ('invoiced','paid')
  ) combined;
$$;

-- Verify
SELECT status, count(*) FROM sales_orders GROUP BY status;
SELECT status, count(*) FROM purchase_orders GROUP BY status;
