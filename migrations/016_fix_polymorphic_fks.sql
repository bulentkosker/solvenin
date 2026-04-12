-- ============================================================
-- Migration 016: Fix polymorphic foreign keys
-- Actual columns: stock_movements.invoice_id, journal_entries.source_id,
--   cash_transactions.source_id, bank_transactions.source_id
-- ============================================================

-- ============================================================
-- 1. STOCK_MOVEMENTS  (invoice_id uuid → typed FKs)
-- ============================================================

ALTER TABLE stock_movements
  ADD COLUMN IF NOT EXISTS sales_order_id uuid,
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid,
  ADD COLUMN IF NOT EXISTS reference_type varchar(30);

-- Migrate: PO-prefixed → purchase_order
UPDATE stock_movements SET
  purchase_order_id = invoice_id,
  reference_type = 'purchase_order'
WHERE invoice_id IS NOT NULL
  AND reference_type IS NULL
  AND reference ILIKE 'PO-%';

-- Remaining invoice_id → sales_order (includes INV-, SO-, POS-)
UPDATE stock_movements SET
  sales_order_id = invoice_id,
  reference_type = 'sales_order'
WHERE invoice_id IS NOT NULL
  AND reference_type IS NULL;

-- Null invoice_id rows
UPDATE stock_movements SET
  reference_type = CASE
    WHEN type = 'adjustment' THEN 'adjustment'
    WHEN type = 'transfer' THEN 'transfer'
    ELSE 'manual'
  END
WHERE reference_type IS NULL;

-- Clean orphans
UPDATE stock_movements SET sales_order_id = NULL
WHERE sales_order_id IS NOT NULL
  AND sales_order_id NOT IN (SELECT id FROM sales_orders);

UPDATE stock_movements SET purchase_order_id = NULL
WHERE purchase_order_id IS NOT NULL
  AND purchase_order_id NOT IN (SELECT id FROM purchase_orders);

-- Drop old column
ALTER TABLE stock_movements DROP COLUMN IF EXISTS invoice_id;

-- FK constraints
ALTER TABLE stock_movements
  ADD CONSTRAINT fk_stock_mv_sales_order
    FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
  ADD CONSTRAINT fk_stock_mv_purchase_order
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
  ADD CONSTRAINT chk_stock_mv_ref_type
    CHECK (reference_type IN (
      'sales_order','purchase_order','production_order',
      'manual','adjustment','opening','transfer'
    ));

ALTER TABLE stock_movements
  ADD CONSTRAINT chk_stock_mv_single_ref
    CHECK (
      (CASE WHEN sales_order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN purchase_order_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    );

CREATE INDEX IF NOT EXISTS idx_stock_mv_sales_order ON stock_movements(sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_stock_mv_purchase_order ON stock_movements(purchase_order_id) WHERE purchase_order_id IS NOT NULL;
DROP INDEX IF EXISTS idx_stock_movements_invoice;

-- ============================================================
-- 2. JOURNAL_ENTRIES  (source_id uuid + type varchar → typed FKs)
--    type values: 'invoice_sale','invoice_purchase','cash','bank'
-- ============================================================

ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS sales_order_id uuid,
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid,
  ADD COLUMN IF NOT EXISTS payment_id uuid;

-- All JE source_id currently point to orders (both invoice and payment JEs)
UPDATE journal_entries SET sales_order_id = source_id
WHERE source_id IS NOT NULL
  AND type IN ('invoice_sale', 'cash', 'bank');

UPDATE journal_entries SET purchase_order_id = source_id
WHERE source_id IS NOT NULL
  AND type IN ('invoice_purchase');

-- Clean orphans
UPDATE journal_entries SET sales_order_id = NULL
WHERE sales_order_id IS NOT NULL
  AND sales_order_id NOT IN (SELECT id FROM sales_orders);

UPDATE journal_entries SET purchase_order_id = NULL
WHERE purchase_order_id IS NOT NULL
  AND purchase_order_id NOT IN (SELECT id FROM purchase_orders);

-- Drop old column
ALTER TABLE journal_entries DROP COLUMN IF EXISTS source_id;

-- FK constraints
ALTER TABLE journal_entries
  ADD CONSTRAINT fk_journal_sales_order
    FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

ALTER TABLE journal_entries
  ADD CONSTRAINT fk_journal_purchase_order
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE journal_entries
  ADD CONSTRAINT fk_journal_payment
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_journal_sales_order ON journal_entries(sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_purchase_order ON journal_entries(purchase_order_id) WHERE purchase_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_journal_payment ON journal_entries(payment_id) WHERE payment_id IS NOT NULL;

-- ============================================================
-- 3. CASH_TRANSACTIONS  (source_id uuid + source_type → typed FKs)
--    source_type values: 'invoice_sale','invoice_purchase','manual'
-- ============================================================

ALTER TABLE cash_transactions
  ADD COLUMN IF NOT EXISTS sales_order_id uuid,
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid,
  ADD COLUMN IF NOT EXISTS payment_id uuid;

UPDATE cash_transactions SET sales_order_id = source_id
WHERE source_id IS NOT NULL AND source_type IN ('invoice_sale', 'sales_order');

UPDATE cash_transactions SET purchase_order_id = source_id
WHERE source_id IS NOT NULL AND source_type IN ('invoice_purchase', 'purchase_order');

-- Normalize source_type
UPDATE cash_transactions SET source_type = 'sales_order' WHERE source_type = 'invoice_sale';
UPDATE cash_transactions SET source_type = 'purchase_order' WHERE source_type = 'invoice_purchase';
UPDATE cash_transactions SET source_type = 'manual' WHERE source_type IS NULL;

-- Clean orphans
UPDATE cash_transactions SET sales_order_id = NULL
WHERE sales_order_id IS NOT NULL
  AND sales_order_id NOT IN (SELECT id FROM sales_orders);

UPDATE cash_transactions SET purchase_order_id = NULL
WHERE purchase_order_id IS NOT NULL
  AND purchase_order_id NOT IN (SELECT id FROM purchase_orders);

-- Drop old column
ALTER TABLE cash_transactions DROP COLUMN IF EXISTS source_id;

-- FK constraints
ALTER TABLE cash_transactions
  ADD CONSTRAINT fk_cash_tx_sales_order
    FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

ALTER TABLE cash_transactions
  ADD CONSTRAINT fk_cash_tx_purchase_order
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE cash_transactions
  ADD CONSTRAINT fk_cash_tx_payment
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_cash_source_type') THEN
    ALTER TABLE cash_transactions
      ADD CONSTRAINT chk_cash_source_type
        CHECK (source_type IN (
          'sales_order','purchase_order','payment',
          'manual','opening','transfer'
        ));
  END IF;
END $$;

ALTER TABLE cash_transactions
  ADD CONSTRAINT chk_cash_single_ref
    CHECK (
      (CASE WHEN sales_order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN purchase_order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN payment_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    );

CREATE INDEX IF NOT EXISTS idx_cash_tx_sales_order ON cash_transactions(sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cash_tx_purchase_order ON cash_transactions(purchase_order_id) WHERE purchase_order_id IS NOT NULL;

-- ============================================================
-- 4. BANK_TRANSACTIONS  (source_id uuid + source_type → typed FKs)
-- ============================================================

ALTER TABLE bank_transactions
  ADD COLUMN IF NOT EXISTS sales_order_id uuid,
  ADD COLUMN IF NOT EXISTS purchase_order_id uuid,
  ADD COLUMN IF NOT EXISTS payment_id uuid;

UPDATE bank_transactions SET sales_order_id = source_id
WHERE source_id IS NOT NULL AND source_type IN ('invoice_sale', 'sales_order');

UPDATE bank_transactions SET purchase_order_id = source_id
WHERE source_id IS NOT NULL AND source_type IN ('invoice_purchase', 'purchase_order');

UPDATE bank_transactions SET source_type = 'sales_order' WHERE source_type = 'invoice_sale';
UPDATE bank_transactions SET source_type = 'purchase_order' WHERE source_type = 'invoice_purchase';
UPDATE bank_transactions SET source_type = 'manual' WHERE source_type IS NULL;

-- Clean orphans
UPDATE bank_transactions SET sales_order_id = NULL
WHERE sales_order_id IS NOT NULL
  AND sales_order_id NOT IN (SELECT id FROM sales_orders);

UPDATE bank_transactions SET purchase_order_id = NULL
WHERE purchase_order_id IS NOT NULL
  AND purchase_order_id NOT IN (SELECT id FROM purchase_orders);

-- Drop old column
ALTER TABLE bank_transactions DROP COLUMN IF EXISTS source_id;

-- FK constraints
ALTER TABLE bank_transactions
  ADD CONSTRAINT fk_bank_tx_sales_order
    FOREIGN KEY (sales_order_id) REFERENCES sales_orders(id) ON DELETE RESTRICT;

ALTER TABLE bank_transactions
  ADD CONSTRAINT fk_bank_tx_purchase_order
    FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE RESTRICT;

ALTER TABLE bank_transactions
  ADD CONSTRAINT fk_bank_tx_payment
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bank_source_type') THEN
    ALTER TABLE bank_transactions
      ADD CONSTRAINT chk_bank_source_type
        CHECK (source_type IN (
          'sales_order','purchase_order','payment',
          'manual','opening','transfer'
        ));
  END IF;
END $$;

ALTER TABLE bank_transactions
  ADD CONSTRAINT chk_bank_single_ref
    CHECK (
      (CASE WHEN sales_order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN purchase_order_id IS NOT NULL THEN 1 ELSE 0 END +
       CASE WHEN payment_id IS NOT NULL THEN 1 ELSE 0 END) <= 1
    );

CREATE INDEX IF NOT EXISTS idx_bank_tx_sales_order ON bank_transactions(sales_order_id) WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bank_tx_purchase_order ON bank_transactions(purchase_order_id) WHERE purchase_order_id IS NOT NULL;

-- ============================================================
-- 5. MIGRATIONS LOG
-- ============================================================

INSERT INTO migrations_log (file_name, notes)
VALUES ('016_fix_polymorphic_fks.sql',
  'Replace polymorphic FKs: stock_movements.invoice_id → sales_order_id/purchase_order_id, journal_entries.source_id → sales_order_id/purchase_order_id/payment_id, cash/bank_transactions.source_id → typed FKs. Added CHECK + partial indexes.')
ON CONFLICT (file_name) DO NOTHING;
