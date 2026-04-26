-- ============================================================
-- M089: employee ↔ contact integration
-- ============================================================
-- employees.contact_id NULL — bordro ödeme bank/cash_transactions'a
-- yazsa bile cari ekstresi alınamıyor. contacts'ta type='employee'
-- destekleniyor (CHECK yok), is_customer/is_supplier flag pattern
-- mevcut ama is_employee flag'i yok.
--
-- Bu migration:
--   1) ALTER contacts: is_employee BOOLEAN flag ekler (customer/supplier ile
--      simetrik).
--   2) BACKFILL: contact_id NULL olan tüm aktif çalışanlar için contacts
--      kaydı oluşturur (per company), employees.contact_id'yi set eder.
--   3) BEFORE INSERT TRIGGER auto_create_employee_contact: yeni çalışan
--      eklenirken contact_id NULL ise otomatik contact oluştur ve set et.
--   4) AFTER UPDATE TRIGGER sync_employee_to_contact: çalışan name/phone/
--      email/tax_number değiştiğinde bağlı contact'ı güncelle (employees →
--      contacts tek yön; reverse loop yok).
--
-- Pattern: customer/supplier zaten contacts'ta. employee de aynı yere
-- iniyor; cari ekstre, merge, RLS, soft-delete gibi tüm contacts altyapısı
-- otomatik destek.
-- ============================================================

-- ─── 1. is_employee flag ─────────────────────────────────
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS is_employee boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_contacts_is_employee
  ON public.contacts (company_id)
  WHERE is_employee = true AND deleted_at IS NULL;

-- ─── 2. Backfill: existing employees → contacts ──────────
DO $$
DECLARE
  emp RECORD;
  v_contact_id uuid;
  v_full_name  text;
BEGIN
  FOR emp IN
    SELECT id, company_id, first_name, last_name, phone, email, tax_number
    FROM public.employees
    WHERE contact_id IS NULL
      AND deleted_at IS NULL
      AND is_active = true
  LOOP
    v_full_name := TRIM(BOTH ' ' FROM
      COALESCE(emp.first_name, '') || ' ' || COALESCE(emp.last_name, ''));
    IF v_full_name = '' THEN
      v_full_name := 'Çalışan ' || SUBSTRING(emp.id::text, 1, 8);
    END IF;

    INSERT INTO public.contacts (
      company_id, name, type,
      is_customer, is_supplier, is_employee,
      phone, email, tax_number,
      is_active
    ) VALUES (
      emp.company_id, v_full_name, 'employee',
      false, false, true,
      emp.phone, emp.email, emp.tax_number,
      true
    ) RETURNING id INTO v_contact_id;

    UPDATE public.employees SET contact_id = v_contact_id WHERE id = emp.id;
  END LOOP;
END $$;

-- ─── 3. BEFORE INSERT trigger — auto-create contact for new employees ──
CREATE OR REPLACE FUNCTION public.auto_create_employee_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_contact_id uuid;
  v_full_name  text;
BEGIN
  -- Already linked? Leave alone (caller chose the contact explicitly).
  IF NEW.contact_id IS NOT NULL THEN RETURN NEW; END IF;

  v_full_name := TRIM(BOTH ' ' FROM
    COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, ''));
  IF v_full_name = '' THEN
    v_full_name := 'Çalışan ' || SUBSTRING(NEW.id::text, 1, 8);
  END IF;

  INSERT INTO public.contacts (
    company_id, name, type,
    is_customer, is_supplier, is_employee,
    phone, email, tax_number,
    is_active
  ) VALUES (
    NEW.company_id, v_full_name, 'employee',
    false, false, true,
    NEW.phone, NEW.email, NEW.tax_number,
    true
  ) RETURNING id INTO v_contact_id;

  NEW.contact_id := v_contact_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_employee_contact ON public.employees;
CREATE TRIGGER trg_auto_employee_contact
  BEFORE INSERT ON public.employees
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_create_employee_contact();

-- ─── 4. AFTER UPDATE trigger — sync employee changes to contact ──
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
    -- Soft-delete the contact when the employee is soft-deleted.
    is_active   = COALESCE(NEW.is_active, is_active),
    deleted_at  = CASE
                    WHEN NEW.deleted_at IS NOT NULL AND deleted_at IS NULL
                    THEN NEW.deleted_at
                    ELSE deleted_at
                  END,
    deleted_by  = CASE
                    WHEN NEW.deleted_at IS NOT NULL AND deleted_by IS NULL
                    THEN NEW.deleted_by
                    ELSE deleted_by
                  END,
    updated_at  = now()
  WHERE id = NEW.contact_id;

  RETURN NEW;
END;
$$;

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
    OLD.is_active   IS DISTINCT FROM NEW.is_active   OR
    OLD.deleted_at  IS DISTINCT FROM NEW.deleted_at
  )
  EXECUTE FUNCTION public.sync_employee_to_contact();

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('089_employee_contact_integration.sql',
  'employees ↔ contacts: is_employee flag (contacts), backfill mevcut çalışanlar, BEFORE INSERT trigger auto-create contact, AFTER UPDATE trigger sync (name/phone/email/tax_number/is_active/deleted_at). Cari ekstre + merge altyapısı employee için de çalışır.')
ON CONFLICT (file_name) DO NOTHING;
