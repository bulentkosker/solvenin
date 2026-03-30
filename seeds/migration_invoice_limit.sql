-- ============================================================
-- Migration: Monthly invoice count function for plan limits
-- Tables: sales_orders + purchase_orders (not invoices/purchase_invoices)
-- Soft delete: is_active = false, deleted_at IS NOT NULL
-- Run in Supabase SQL Editor
-- ============================================================

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

    UNION ALL

    SELECT id FROM purchase_orders
    WHERE company_id = p_company_id
    AND created_at >= date_trunc('month', now())
    AND is_active = true
  ) combined;
$$;
