-- ============================================================
-- M093: Employee soft-delete should NOT cascade to contact
-- ============================================================
-- M089'un sync_employee_to_contact trigger'ı çalışan soft-delete'inde
-- contact'a da deleted_at yansıtıyordu. Bu yanlış — cari, çalışana
-- yapılmış bordro/avans hareketlerinin sahibidir; çalışan ayrıldıktan
-- sonra bile bu hareketlerin cari ekstresi erişilebilir kalmalı.
--
-- Doğru kural seti:
--   - Çalışan aktifken cari silinemez               (M092 ✓)
--   - Cari'de hareket varken silinemez              (M091 ✓)
--   - Çalışan silindiğinde cari KORUNUR             (bu migration)
--   - Çalışan silinmiş + cari'de hareket yok        → manuel silinebilir
--     (M091 + M092 birlikte zaten geçit veriyor)
--
-- Değişiklik: sync_employee_to_contact fonksiyonundan deleted_at /
-- deleted_by yansıtması kaldırıldı. WHEN clause'undan da deleted_at
-- çıkarıldı (artık o geçişe ihtiyacı yok). Sadece name / phone / email /
-- tax_number / is_active sync edilir.
--
-- is_active cascade BIRAKILDI: çalışan inaktif olunca cari de inaktif
-- görünür (yeni hareket akışları onu listede göstermez), ama deleted_at
-- NULL kaldığı için cari ekstre + audit erişilebilir. Soft-delete ile
-- is_active arasındaki kritik fark.
-- ============================================================

CREATE OR REPLACE FUNCTION public.sync_employee_to_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_full_name text;
BEGIN
  IF NEW.contact_id IS NULL THEN RETURN NEW; END IF;

  v_full_name := TRIM(BOTH ' ' FROM
    COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, ''));

  UPDATE public.contacts SET
    name        = COALESCE(NULLIF(v_full_name, ''), name),
    phone       = NEW.phone,
    email       = NEW.email,
    tax_number  = NEW.tax_number,
    is_active   = COALESCE(NEW.is_active, is_active),
    -- deleted_at / deleted_by intentionally NOT cascaded (M093):
    -- preserves contact for payroll/advance audit when employee leaves.
    updated_at  = now()
  WHERE id = NEW.contact_id;

  RETURN NEW;
END;
$$;

-- Re-create trigger with updated WHEN clause (deleted_at removed).
DROP TRIGGER IF EXISTS trg_sync_employee_contact ON public.employees;
CREATE TRIGGER trg_sync_employee_contact
  AFTER UPDATE ON public.employees
  FOR EACH ROW
  WHEN (
    OLD.first_name  IS DISTINCT FROM NEW.first_name  OR
    OLD.last_name   IS DISTINCT FROM NEW.last_name   OR
    OLD.phone       IS DISTINCT FROM NEW.phone       OR
    OLD.email       IS DISTINCT FROM NEW.email       OR
    OLD.tax_number  IS DISTINCT FROM NEW.tax_number  OR
    OLD.is_active   IS DISTINCT FROM NEW.is_active
  )
  EXECUTE FUNCTION public.sync_employee_to_contact();

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('093_employee_delete_preserves_contact.sql',
  'sync_employee_to_contact fonksiyonu deleted_at/deleted_by cascade''ini ARTIK YAPMAZ. WHEN clause''undan da deleted_at çıkarıldı. Çalışan silindiğinde cari korunur — bordro/avans audit erişilebilir kalır. is_active sync devam eder. M092 + M091 zaten cari''nin tx''li veya aktif employee''li silinmesini engelliyor; çalışan silindikten sonra cari''de hiç tx yoksa manuel olarak silinebilir.')
ON CONFLICT (file_name) DO NOTHING;
