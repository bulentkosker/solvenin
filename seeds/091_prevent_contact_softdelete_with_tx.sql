-- ============================================================
-- M091: Prevent contact soft-delete when linked active tx exists
-- ============================================================
-- M090 cleanup'ında bağlı tx kontrolü yapılmadan retail contact'lar
-- soft-deleted edildi (Park'taki 'Perakende Satışlar' contact'ı 2
-- aktif cash_transactions row'una bağlıydı). Application katmanı
-- (contacts.html) bu kuralı zorluyor ama migration veya direct UPDATE
-- bypass edebiliyor.
--
-- Bu trigger DB seviyesinde garanti veriyor: contacts.deleted_at
-- NULL → NOT NULL geçişi (yani soft-delete eylemi) engelliyor eğer
-- contact'a bağlı aktif tx varsa.
--
-- Kapsam:
--   bank_transactions / cash_transactions / contact_transactions: contact_id
--   sales_orders: customer_id
--   purchase_orders: supplier_id
--   employees: contact_id
--   payments: ? (contact_id kolonu yok — yoldan giderse eklenebilir)
--
-- Hard delete (DELETE) bu trigger'a takılmaz; FK RESTRICT/CASCADE ayrı
-- katman. Burada sadece soft-delete invariant'ı zorlanıyor.
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_contact_softdelete_with_tx()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- Only block on the deleted_at NULL → NOT NULL transition (the act of
  -- soft-deleting). Updates that don't touch deleted_at, or that restore
  -- (NOT NULL → NULL), pass through.
  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Tally linked active rows. Each table queried separately so the failure
  -- message can pinpoint which table holds the references.
  SELECT COUNT(*) INTO v_count FROM bank_transactions
    WHERE contact_id = NEW.id AND deleted_at IS NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % has % active bank transaction(s) — cannot soft-delete', NEW.id, v_count
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT COUNT(*) INTO v_count FROM cash_transactions
    WHERE contact_id = NEW.id AND deleted_at IS NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % has % active cash transaction(s) — cannot soft-delete', NEW.id, v_count
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT COUNT(*) INTO v_count FROM contact_transactions
    WHERE contact_id = NEW.id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % has % contact_transactions row(s) — cannot soft-delete', NEW.id, v_count
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT COUNT(*) INTO v_count FROM sales_orders
    WHERE customer_id = NEW.id AND deleted_at IS NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % has % active sales order(s) — cannot soft-delete', NEW.id, v_count
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  SELECT COUNT(*) INTO v_count FROM purchase_orders
    WHERE supplier_id = NEW.id AND deleted_at IS NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % has % active purchase order(s) — cannot soft-delete', NEW.id, v_count
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- employees.contact_id check intentionally light: an employee with the
  -- contact pointing to it, but no other tx, can be soft-deleted via
  -- employee.deleted_at (M089 sync trigger pushes that down). We DO NOT
  -- check employees here — otherwise sync trigger would deadlock.

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_contact_softdelete_with_tx ON public.contacts;
CREATE TRIGGER trg_prevent_contact_softdelete_with_tx
  BEFORE UPDATE ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_contact_softdelete_with_tx();

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('091_prevent_contact_softdelete_with_tx.sql',
  'BEFORE UPDATE trigger contacts.deleted_at NULL→NOT NULL geçişi engeller eğer bank_transactions / cash_transactions / contact_transactions / sales_orders.customer_id / purchase_orders.supplier_id''de aktif satır varsa. employees.contact_id check edilmez (M089 sync trigger döngüsünü engellemek için). Restore (NOT NULL→NULL) ve normal field update''leri etkilenmez.')
ON CONFLICT (file_name) DO NOTHING;
