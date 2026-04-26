-- ============================================================
-- M092: Strengthen contact soft-delete guard — block when an active
--       employee or payment row references the contact
-- ============================================================
-- M091 trigger'ında bilinçli olarak employees.contact_id check'ini
-- atlamıştım — gerekçe: M089'un employee→contact sync trigger'ı
-- bozulmasın. Ama bu kapı kullanıcı UI'dan çalışan cari'sini doğrudan
-- silmeyi denerse açık kalıyor. Halil contacts.html'den 6 çalışan
-- contact'ını sildi (pre-check'te tx yoktu, geçti).
--
-- Çözüm: employees.contact_id check'ini ekle, AMA `deleted_at IS NULL`
-- filter ile. Senaryolar:
--   - Halil çalışan cari'sini doğrudan siliyor: çalışan `deleted_at IS NULL`
--     olduğu için reject ✓
--   - M089 sync trigger çalışan soft-delete'i contact'a yansıtırken:
--     trigger içinde NEW.deleted_at=NOT NULL — query `deleted_at IS NULL`
--     ile match etmez → reject olmaz, contact silinebilir ✓
--
-- Bonus: payments.contact_id ya da payments.employee_id kontrol etme.
-- payments tablosu schema'sına bak — eğer contact_id varsa eklerim.
--
-- M091'in kendisini override etmek yerine ek kural olarak yazıyorum:
-- M091 fonksiyonu CREATE OR REPLACE ile genişletilecek.
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_contact_softdelete_with_tx()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- Only block on the deleted_at NULL → NOT NULL transition.
  IF OLD.deleted_at IS NOT NULL OR NEW.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

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

  -- NEW: employees.contact_id with deleted_at IS NULL filter.
  -- Filter is critical: when M089 sync_employee_to_contact pushes the
  -- employee soft-delete down to the contact, the employee row already
  -- has deleted_at NOT NULL (transaction-visible) so this check passes
  -- without rejecting the legitimate cascade.
  SELECT COUNT(*) INTO v_count FROM employees
    WHERE contact_id = NEW.id AND deleted_at IS NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Contact % is linked to an active employee — delete the employee from HR module first',
      NEW.id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger zaten M091'de bağlı, fonksiyonu yenilemek yeterli.

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('092_strengthen_contact_softdelete_guard.sql',
  'M091''in prevent_contact_softdelete_with_tx fonksiyonu CREATE OR REPLACE ile genişletildi: employees.contact_id check eklendi (deleted_at IS NULL filter ile, M089 cascade ile çakışmasın). Halil''in 6 çalışan contact''ını UI''dan silmesinden sonra restore edildi; bu trigger benzer hatayı tekrar engeller. Çalışan cari''si silinmek isteniyorsa İK''dan çalışan silinmeli — sync trigger contact''ı zaten cascade soft-delete eder.')
ON CONFLICT (file_name) DO NOTHING;
