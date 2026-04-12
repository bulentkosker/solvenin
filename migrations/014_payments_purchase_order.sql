-- ============================================================
-- Migration 014: Add purchase_order support to payments table
-- ============================================================

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid
    REFERENCES purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS payment_type varchar(20) DEFAULT 'sales';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_payment_type') THEN
    ALTER TABLE payments
      ADD CONSTRAINT chk_payment_type
        CHECK (payment_type IN ('sales', 'purchase'));
  END IF;
END $$;

UPDATE payments SET payment_type = 'sales' WHERE payment_type IS NULL;

ALTER TABLE payments
  ADD CONSTRAINT chk_payment_single_order
    CHECK (
      (CASE WHEN order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN purchase_order_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    );

CREATE INDEX IF NOT EXISTS idx_payments_purchase_order_id
  ON payments(purchase_order_id) WHERE purchase_order_id IS NOT NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('014_payments_purchase_order.sql',
  'Add purchase_order_id FK to payments, add payment_type CHECK constraint')
ON CONFLICT (file_name) DO NOTHING;
