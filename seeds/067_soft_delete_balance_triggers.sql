-- ============================================================
-- M067: cash/bank balance triggers — soft-delete aware
-- ============================================================
-- Before this fix, trg_cash_balance / trg_bank_balance fired only on
-- INSERT and DELETE. Since cashbank.html soft-deletes (UPDATE … SET
-- deleted_at = NOW()), balances never decremented when a user "deleted"
-- a transaction. The row was also still visible because loadCash/BankTx()
-- didn't filter deleted_at (fixed in the same commit as this migration).
--
-- New semantics for the UPDATE path:
--   • NULL → NOT NULL (soft-delete)    → reverse the row's effect
--   • NOT NULL → NULL (restore)        → re-apply the row's effect
--   • amount / type / account changes while not-deleted → re-apply the
--     difference (reverse OLD, apply NEW)
--   • both sides deleted                → no effect
--
-- The migration also reconciles current_balance for every register /
-- account once, so pre-existing soft-deleted rows stop contaminating
-- the balance.
-- ============================================================

BEGIN;

-- ─── cash trigger function ───
CREATE OR REPLACE FUNCTION public.update_cash_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.deleted_at IS NULL THEN
      UPDATE cash_registers SET current_balance = current_balance
        + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
      WHERE id = NEW.register_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.deleted_at IS NULL THEN
      UPDATE cash_registers SET current_balance = current_balance
        - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
      WHERE id = OLD.register_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Soft-delete (NULL → NOT NULL): reverse OLD effect.
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      UPDATE cash_registers SET current_balance = current_balance
        - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
      WHERE id = OLD.register_id;
    -- Restore (NOT NULL → NULL): re-apply NEW effect.
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      UPDATE cash_registers SET current_balance = current_balance
        + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
      WHERE id = NEW.register_id;
    -- Active row edited (amount / type / register moved): reverse OLD, apply NEW.
    ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NULL THEN
      IF OLD.register_id IS DISTINCT FROM NEW.register_id
         OR OLD.type      IS DISTINCT FROM NEW.type
         OR OLD.amount    IS DISTINCT FROM NEW.amount THEN
        UPDATE cash_registers SET current_balance = current_balance
          - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
        WHERE id = OLD.register_id;
        UPDATE cash_registers SET current_balance = current_balance
          + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
        WHERE id = NEW.register_id;
      END IF;
    END IF;
    -- Deleted → deleted edits: no balance effect.
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ─── bank trigger function ───
CREATE OR REPLACE FUNCTION public.update_bank_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.deleted_at IS NULL THEN
      UPDATE bank_accounts SET current_balance = current_balance
        + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
      WHERE id = NEW.account_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.deleted_at IS NULL THEN
      UPDATE bank_accounts SET current_balance = current_balance
        - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
      WHERE id = OLD.account_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      UPDATE bank_accounts SET current_balance = current_balance
        - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
      WHERE id = OLD.account_id;
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      UPDATE bank_accounts SET current_balance = current_balance
        + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
      WHERE id = NEW.account_id;
    ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NULL THEN
      IF OLD.account_id IS DISTINCT FROM NEW.account_id
         OR OLD.type    IS DISTINCT FROM NEW.type
         OR OLD.amount  IS DISTINCT FROM NEW.amount THEN
        UPDATE bank_accounts SET current_balance = current_balance
          - CASE WHEN OLD.type = 'in' THEN OLD.amount ELSE -OLD.amount END
        WHERE id = OLD.account_id;
        UPDATE bank_accounts SET current_balance = current_balance
          + CASE WHEN NEW.type = 'in' THEN NEW.amount ELSE -NEW.amount END
        WHERE id = NEW.account_id;
      END IF;
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ─── Re-create triggers to include UPDATE ───
DROP TRIGGER IF EXISTS trg_cash_balance ON public.cash_transactions;
CREATE TRIGGER trg_cash_balance
  AFTER INSERT OR UPDATE OR DELETE ON public.cash_transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_cash_balance();

DROP TRIGGER IF EXISTS trg_bank_balance ON public.bank_transactions;
CREATE TRIGGER trg_bank_balance
  AFTER INSERT OR UPDATE OR DELETE ON public.bank_transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_bank_balance();

-- ─── Reconcile historical balances from the live ledger ───
-- Any soft-deleted rows that were previously counted in current_balance
-- are now excluded. Run once per register / account.

UPDATE cash_registers cr
SET current_balance = COALESCE(cr.opening_balance, 0) + COALESCE((
  SELECT SUM(CASE WHEN ct.type = 'in' THEN ct.amount ELSE -ct.amount END)
  FROM cash_transactions ct
  WHERE ct.register_id = cr.id AND ct.deleted_at IS NULL
), 0)
WHERE cr.deleted_at IS NULL;

UPDATE bank_accounts ba
SET current_balance = COALESCE(ba.opening_balance, 0) + COALESCE((
  SELECT SUM(CASE WHEN bt.type = 'in' THEN bt.amount ELSE -bt.amount END)
  FROM bank_transactions bt
  WHERE bt.account_id = ba.id AND bt.deleted_at IS NULL
), 0)
WHERE ba.deleted_at IS NULL;

INSERT INTO migrations_log (file_name, notes)
VALUES ('067_soft_delete_balance_triggers.sql',
  'Trigger'' leri UPDATE''e de bağlı: soft-delete ve restore current_balance''i doğru şekilde günceller. Tüm kasa/banka bakiyeleri aktif hareketlerden yeniden hesaplandı.')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
