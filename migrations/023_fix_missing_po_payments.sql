-- ============================================================
-- Migration 023: Backfill missing payment records for paid POs
-- Purchase orders marked 'paid' before M014 have no payments row
-- ============================================================

INSERT INTO payments (company_id, purchase_order_id, payment_type, amount, method, paid_at, notes)
SELECT po.company_id, po.id, 'purchase', po.total, 'cash', po.created_at,
  'Migrated — missing payment record for paid PO'
FROM purchase_orders po
WHERE po.status = 'paid'
  AND po.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM payments p WHERE p.purchase_order_id = po.id
  );

INSERT INTO migrations_log (file_name, notes)
VALUES ('023_fix_missing_po_payments.sql',
  'Backfill payment records for purchase orders that were paid before M014 added purchase_order_id')
ON CONFLICT (file_name) DO NOTHING;
