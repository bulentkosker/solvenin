-- ============================================================
-- M094: Employee contact currency follows company.base_currency
-- ============================================================
-- M089'un auto_create_employee_contact trigger'ı yeni contact INSERT
-- ederken currency_code'u set etmiyordu. contacts.currency_code'un
-- veritabanı default'u 'USD' (kolon default değeri tarihsel olarak
-- böyle), bu yüzden Park Group (base_currency=KZT) için yaratılan
-- 6 çalışan contact'ı USD olarak girdi. UI'da dropdown KZT default'u
-- gösteriyordu — DB ile çelişiyordu.
--
-- Bu migration BEFORE INSERT trigger'a şirketin base_currency'sini
-- okutarak yeni çalışan contact'larının currency'sini şirket para
-- birimine ayarlar. Mevcut hatalı satırlar (7 row, 2 şirket) tek
-- seferlik script ile düzeltildi (Park 6 + ANKA 1).
--
-- Çalışan formal yapısında her zaman şirket para birimi kullanılır
-- (maaş base_salary aynı para biriminde). Bu yüzden sync trigger'da
-- da currency_code güncel base_currency'yi izlesin — şirket
-- base_currency'sini değiştirirse çalışan contact'ları otomatik
-- yansır.
-- ============================================================

CREATE OR REPLACE FUNCTION public.auto_create_employee_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_contact_id  uuid;
  v_full_name   text;
  v_currency    text;
BEGIN
  IF NEW.contact_id IS NOT NULL THEN RETURN NEW; END IF;

  v_full_name := TRIM(BOTH ' ' FROM
    COALESCE(NEW.first_name, '') || ' ' || COALESCE(NEW.last_name, ''));
  IF v_full_name = '' THEN
    v_full_name := 'Çalışan ' || SUBSTRING(NEW.id::text, 1, 8);
  END IF;

  -- M094: align with company base currency (was leaving currency_code to
  -- DB default 'USD' which contradicts companies running in non-USD bases).
  SELECT COALESCE(base_currency, 'USD') INTO v_currency
    FROM companies WHERE id = NEW.company_id;

  INSERT INTO public.contacts (
    company_id, name, type,
    is_customer, is_supplier, is_employee,
    phone, email, tax_number,
    currency_code,
    is_active
  ) VALUES (
    NEW.company_id, v_full_name, 'employee',
    false, false, true,
    NEW.phone, NEW.email, NEW.tax_number,
    v_currency,
    true
  ) RETURNING id INTO v_contact_id;

  NEW.contact_id := v_contact_id;
  RETURN NEW;
END;
$$;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('094_employee_contact_currency.sql',
  'auto_create_employee_contact trigger contacts.currency_code''u companies.base_currency''den okuyacak şekilde güncellendi. Mevcut 7 hatalı satır tek seferlik script ile şirket para birimine çekildi (Park 6, ANKA 1). Sync trigger değiştirilmedi — kullanıcı UI''dan elle currency değiştirirse o değer korunur.')
ON CONFLICT (file_name) DO NOTHING;
