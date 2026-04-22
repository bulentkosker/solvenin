-- ============================================================
-- M071: contact_transactions sync triggers for cash/bank tx
-- ============================================================
-- Cash and bank tx modals populate contact_id, but nothing writes to
-- contact_transactions — so the cari ekstresi never shows the payment.
-- This migration closes the gap with triggers (same design as the
-- cash/bank balance triggers in M067):
--
--   INSERT cash/bank tx with contact_id      → insert contact_transaction
--   UPDATE contact_id / amount / date / etc. → sync the linked row
--   UPDATE deleted_at (soft-delete / restore) → soft-delete / restore the link
--   Hard DELETE                              → cascade via FK ON DELETE SET NULL
--                                              (we also nuke the link row)
--
-- Schema change: contact_transactions.cash_transaction_id (was missing;
-- only bank_transaction_id existed).
--
-- Sign convention — matches execute_import RPC (M066) and the ledger in
-- contacts.html: money IN to us → credit the contact (their receivable
-- decreases / our payable increases); money OUT → debit the contact.
--
-- Backfill: existing cash/bank rows with contact_id and no linked
-- contact_transaction get one.
-- ============================================================

BEGIN;

-- ─── 1. Schema ──────────────────────────────────────────────
ALTER TABLE contact_transactions
  ADD COLUMN IF NOT EXISTS cash_transaction_id UUID
    REFERENCES cash_transactions(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_ct_cash_tx_id
  ON contact_transactions(cash_transaction_id) WHERE cash_transaction_id IS NOT NULL;

-- bank_transaction_id already exists (M058); add CASCADE if not already.
-- Replace the FK only if it isn't ON DELETE CASCADE yet.
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint
  WHERE conrelid = 'public.contact_transactions'::regclass
    AND conname IN ('contact_transactions_bank_transaction_id_fkey');
  IF v_def IS NOT NULL AND v_def NOT ILIKE '%ON DELETE CASCADE%' THEN
    ALTER TABLE contact_transactions
      DROP CONSTRAINT contact_transactions_bank_transaction_id_fkey;
    ALTER TABLE contact_transactions
      ADD CONSTRAINT contact_transactions_bank_transaction_id_fkey
      FOREIGN KEY (bank_transaction_id) REFERENCES bank_transactions(id) ON DELETE CASCADE;
  END IF;
END $$;

-- ─── 2. Trigger function for cash_transactions ──────────────
CREATE OR REPLACE FUNCTION public.sync_contact_tx_from_cash()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ct_type text;
  v_existing_ct_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM contact_transactions WHERE cash_transaction_id = OLD.id;
    RETURN OLD;
  END IF;

  -- Resolve direction: money into register = contact paid us → credit them.
  v_ct_type := CASE WHEN NEW.type = 'in' THEN 'credit' ELSE 'debit' END;

  -- Is there already a linked contact_tx for this cash_tx?
  SELECT id INTO v_existing_ct_id FROM contact_transactions
  WHERE cash_transaction_id = NEW.id LIMIT 1;

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL) THEN
    -- Fresh row or restore from soft-delete
    IF NEW.contact_id IS NOT NULL AND NEW.deleted_at IS NULL AND v_existing_ct_id IS NULL THEN
      INSERT INTO contact_transactions (
        company_id, contact_id, type, amount, date,
        description, reference, cash_transaction_id, created_by
      ) VALUES (
        NEW.company_id, NEW.contact_id, v_ct_type, NEW.amount, NEW.transaction_date,
        NEW.description, NEW.reference, NEW.id, NEW.created_by
      );
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE path
  -- Soft-delete: NULL → NOT NULL → remove the link row.
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    DELETE FROM contact_transactions WHERE cash_transaction_id = NEW.id;
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;  -- stays deleted; nothing to sync
  END IF;

  -- Active row edited.
  IF NEW.contact_id IS NULL THEN
    -- Contact was cleared: drop the link.
    IF v_existing_ct_id IS NOT NULL THEN
      DELETE FROM contact_transactions WHERE id = v_existing_ct_id;
    END IF;
  ELSE
    IF v_existing_ct_id IS NULL THEN
      -- First time we got a contact on this tx.
      INSERT INTO contact_transactions (
        company_id, contact_id, type, amount, date,
        description, reference, cash_transaction_id, created_by
      ) VALUES (
        NEW.company_id, NEW.contact_id, v_ct_type, NEW.amount, NEW.transaction_date,
        NEW.description, NEW.reference, NEW.id, NEW.created_by
      );
    ELSE
      -- Update in place (contact may have changed — this moves the row
      -- to the new contact's ledger automatically).
      UPDATE contact_transactions SET
        contact_id = NEW.contact_id,
        type = v_ct_type,
        amount = NEW.amount,
        date = NEW.transaction_date,
        description = NEW.description,
        reference = NEW.reference
      WHERE id = v_existing_ct_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ─── 3. Trigger function for bank_transactions ──────────────
CREATE OR REPLACE FUNCTION public.sync_contact_tx_from_bank()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ct_type text;
  v_existing_ct_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM contact_transactions WHERE bank_transaction_id = OLD.id;
    RETURN OLD;
  END IF;

  v_ct_type := CASE WHEN NEW.type = 'in' THEN 'credit' ELSE 'debit' END;

  SELECT id INTO v_existing_ct_id FROM contact_transactions
  WHERE bank_transaction_id = NEW.id LIMIT 1;

  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL) THEN
    IF NEW.contact_id IS NOT NULL AND NEW.deleted_at IS NULL AND v_existing_ct_id IS NULL THEN
      INSERT INTO contact_transactions (
        company_id, contact_id, type, amount, date,
        description, reference, bank_transaction_id, created_by
      ) VALUES (
        NEW.company_id, NEW.contact_id, v_ct_type, NEW.amount, NEW.transaction_date,
        NEW.description, NEW.reference, NEW.id, NEW.created_by
      );
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    DELETE FROM contact_transactions WHERE bank_transaction_id = NEW.id;
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;

  IF NEW.contact_id IS NULL THEN
    IF v_existing_ct_id IS NOT NULL THEN
      DELETE FROM contact_transactions WHERE id = v_existing_ct_id;
    END IF;
  ELSE
    IF v_existing_ct_id IS NULL THEN
      INSERT INTO contact_transactions (
        company_id, contact_id, type, amount, date,
        description, reference, bank_transaction_id, created_by
      ) VALUES (
        NEW.company_id, NEW.contact_id, v_ct_type, NEW.amount, NEW.transaction_date,
        NEW.description, NEW.reference, NEW.id, NEW.created_by
      );
    ELSE
      UPDATE contact_transactions SET
        contact_id = NEW.contact_id,
        type = v_ct_type,
        amount = NEW.amount,
        date = NEW.transaction_date,
        description = NEW.description,
        reference = NEW.reference
      WHERE id = v_existing_ct_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ─── 4. Attach triggers ─────────────────────────────────────
DROP TRIGGER IF EXISTS trg_cash_contact_sync ON public.cash_transactions;
CREATE TRIGGER trg_cash_contact_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.cash_transactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_contact_tx_from_cash();

DROP TRIGGER IF EXISTS trg_bank_contact_sync ON public.bank_transactions;
CREATE TRIGGER trg_bank_contact_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.bank_transactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_contact_tx_from_bank();

-- ─── 5. Backfill existing rows ──────────────────────────────
-- For every non-deleted cash/bank tx with contact_id and no matching
-- contact_transactions row yet, create the link row now.

INSERT INTO contact_transactions (
  company_id, contact_id, type, amount, date,
  description, reference, cash_transaction_id, created_by
)
SELECT
  ct.company_id, ct.contact_id,
  CASE WHEN ct.type = 'in' THEN 'credit' ELSE 'debit' END,
  ct.amount, ct.transaction_date, ct.description, ct.reference, ct.id, ct.created_by
FROM cash_transactions ct
WHERE ct.contact_id IS NOT NULL
  AND ct.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM contact_transactions x WHERE x.cash_transaction_id = ct.id
  );

INSERT INTO contact_transactions (
  company_id, contact_id, type, amount, date,
  description, reference, bank_transaction_id, created_by
)
SELECT
  bt.company_id, bt.contact_id,
  CASE WHEN bt.type = 'in' THEN 'credit' ELSE 'debit' END,
  bt.amount, bt.transaction_date, bt.description, bt.reference, bt.id, bt.created_by
FROM bank_transactions bt
WHERE bt.contact_id IS NOT NULL
  AND bt.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM contact_transactions x WHERE x.bank_transaction_id = bt.id
  );

INSERT INTO migrations_log (file_name, notes)
VALUES ('071_contact_tx_sync_triggers.sql',
  'cash/bank → contact_transactions otomatik sync (trigger) + contact_transactions.cash_transaction_id kolonu + backfill.');

COMMIT;
