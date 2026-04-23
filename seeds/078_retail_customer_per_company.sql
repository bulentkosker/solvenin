-- ============================================================
-- M078: 'Perakende Satışlar' system contact per company
-- ============================================================
-- POS / walk-in satışlar şu ana kadar cash/bank_transactions'a
-- contact_id=NULL olarak girdiği için cari ekstreleri ve cari
-- raporları bu hareketleri atlıyordu. Her şirket için tek bir
-- system contact ("Perakende Satışlar") açıp anonim satışları
-- ona toplarız.
--
-- system contacts:
--   - silinemez   (contacts.html delete guard)
--   - merge edilemez (merge_contacts RPC reject, 077 güncellendi)
--   - edit'te sadece name değiştirilebilir (UI katmanı, ayrı iş)
--
-- Backfill otoritesi: sales_orders.order_type='pos'. Eski POS
-- siparişlerinden linked tx (sales_order_id ile bağlı
-- cash/bank_transactions) retail contact'a bağlanır.
-- ============================================================

BEGIN;

-- ─── 1. is_system kolonu ────────────────────────────────
ALTER TABLE contacts
  ADD COLUMN IF NOT EXISTS is_system boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_contacts_company_system
  ON contacts(company_id, is_system) WHERE is_system = true;

-- ─── 2. Her mevcut şirket için retail contact ──────────
INSERT INTO contacts (
  company_id, name, type,
  is_customer, is_supplier, is_active, is_system,
  notes
)
SELECT
  c.id, 'Perakende Satışlar', 'customer',
  true, false, true, true,
  'POS ve anonim perakende satışlar için sistem carisi. Silinemez, birleştirilemez.'
FROM companies c
WHERE NOT EXISTS (
  SELECT 1 FROM contacts ct
   WHERE ct.company_id = c.id
     AND ct.is_system = true
     AND ct.name = 'Perakende Satışlar'
);

-- ─── 3. Backfill ───────────────────────────────────────
-- 3a. sales_orders.customer_id (POS siparişlerinde walk-in → retail)
UPDATE sales_orders so
   SET customer_id = c.id
  FROM contacts c
 WHERE so.order_type = 'pos'
   AND so.customer_id IS NULL
   AND c.company_id = so.company_id
   AND c.is_system = true
   AND c.name = 'Perakende Satışlar';

-- 3b. bank_transactions (linked POS orders üzerinden)
UPDATE bank_transactions bt
   SET contact_id = c.id
  FROM sales_orders so, contacts c
 WHERE bt.sales_order_id = so.id
   AND so.order_type = 'pos'
   AND bt.contact_id IS NULL
   AND c.company_id = so.company_id
   AND c.is_system = true
   AND c.name = 'Perakende Satışlar';

-- 3c. cash_transactions (linked POS orders)
UPDATE cash_transactions ct
   SET contact_id = c.id
  FROM sales_orders so, contacts c
 WHERE ct.sales_order_id = so.id
   AND so.order_type = 'pos'
   AND ct.contact_id IS NULL
   AND c.company_id = so.company_id
   AND c.is_system = true
   AND c.name = 'Perakende Satışlar';

-- 3d. Orphan POS-tagged tx (sales_order_id yok ama description 'POS' ile başlar — import / legacy)
UPDATE bank_transactions bt
   SET contact_id = c.id
  FROM contacts c
 WHERE bt.contact_id IS NULL
   AND bt.company_id = c.company_id
   AND c.is_system = true AND c.name = 'Perakende Satışlar'
   AND bt.description ILIKE 'POS%'
   AND bt.deleted_at IS NULL;

UPDATE cash_transactions ct
   SET contact_id = c.id
  FROM contacts c
 WHERE ct.contact_id IS NULL
   AND ct.company_id = c.company_id
   AND c.is_system = true AND c.name = 'Perakende Satışlar'
   AND ct.description ILIKE 'POS%'
   AND ct.deleted_at IS NULL;

-- ─── 4. Yeni şirket açılınca otomatik retail contact ───
CREATE OR REPLACE FUNCTION public.create_system_contacts_for_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO contacts (
    company_id, name, type,
    is_customer, is_supplier, is_active, is_system,
    notes
  ) VALUES (
    NEW.id, 'Perakende Satışlar', 'customer',
    true, false, true, true,
    'POS ve anonim perakende satışlar için sistem carisi. Silinemez, birleştirilemez.'
  )
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_system_contacts ON companies;
CREATE TRIGGER trg_company_system_contacts
AFTER INSERT ON companies
FOR EACH ROW
EXECUTE FUNCTION public.create_system_contacts_for_company();

-- ─── 5. merge_contacts RPC: is_system reject ────────────
-- M077'deki fonksiyonu is_system kontrolü ile güncelle. Signature
-- aynı kaldığı için CREATE OR REPLACE yeterli; arayan UI değişmiyor.
CREATE OR REPLACE FUNCTION public.merge_contacts(
  p_source_id uuid,
  p_target_id uuid,
  p_delete_source boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source   contacts%ROWTYPE;
  v_target   contacts%ROWTYPE;

  v_bank_count        int := 0;
  v_cash_count        int := 0;
  v_ct_count          int := 0;
  v_crm_opp_count     int := 0;
  v_crm_quote_count   int := 0;
  v_dil_matched_count int := 0;
  v_dil_sugg_count    int := 0;
  v_emp_count         int := 0;
  v_label_count       int := 0;
  v_project_count     int := 0;
  v_po_count          int := 0;
  v_so_count          int := 0;
  v_total             int;
BEGIN
  IF p_source_id IS NULL OR p_target_id IS NULL THEN
    RAISE EXCEPTION 'source_id and target_id required';
  END IF;
  IF p_source_id = p_target_id THEN
    RAISE EXCEPTION 'Source and target cannot be the same contact';
  END IF;

  SELECT * INTO v_source FROM contacts WHERE id = p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source contact not found'; END IF;
  IF v_source.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Source contact is deleted'; END IF;

  SELECT * INTO v_target FROM contacts
  WHERE id = p_target_id AND company_id = v_source.company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target contact not found or different company'; END IF;
  IF v_target.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Target contact is deleted'; END IF;

  -- System-managed contacts (Perakende Satışlar etc.) are off-limits:
  -- merging away retail breaks every POS row; merging into retail
  -- absorbs non-retail data. Both directions rejected.
  IF v_source.is_system OR v_target.is_system THEN
    RAISE EXCEPTION 'System contacts cannot be merged' USING ERRCODE = 'check_violation';
  END IF;

  IF auth.uid() IS NOT NULL AND NOT (v_source.company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE contacts
     SET is_customer = COALESCE(is_customer, false) OR COALESCE(v_source.is_customer, false),
         is_supplier = COALESCE(is_supplier, false) OR COALESCE(v_source.is_supplier, false)
   WHERE id = p_target_id
     AND ((COALESCE(v_source.is_customer, false) AND NOT COALESCE(v_target.is_customer, false))
       OR (COALESCE(v_source.is_supplier, false) AND NOT COALESCE(v_target.is_supplier, false)));

  UPDATE bank_transactions SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_bank_count = ROW_COUNT;

  UPDATE cash_transactions SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_cash_count = ROW_COUNT;

  UPDATE contact_transactions SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_ct_count = ROW_COUNT;

  UPDATE crm_opportunities SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_crm_opp_count = ROW_COUNT;

  UPDATE crm_quotes SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_crm_quote_count = ROW_COUNT;

  UPDATE data_import_lines SET matched_contact_id = p_target_id WHERE matched_contact_id = p_source_id;
  GET DIAGNOSTICS v_dil_matched_count = ROW_COUNT;

  UPDATE data_import_lines SET suggested_contact_id = p_target_id WHERE suggested_contact_id = p_source_id;
  GET DIAGNOSTICS v_dil_sugg_count = ROW_COUNT;

  UPDATE employees SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_emp_count = ROW_COUNT;

  UPDATE label_templates SET contact_id = p_target_id WHERE contact_id = p_source_id;
  GET DIAGNOSTICS v_label_count = ROW_COUNT;

  UPDATE projects SET client_id = p_target_id WHERE client_id = p_source_id;
  GET DIAGNOSTICS v_project_count = ROW_COUNT;

  UPDATE purchase_orders SET supplier_id = p_target_id WHERE supplier_id = p_source_id;
  GET DIAGNOSTICS v_po_count = ROW_COUNT;

  UPDATE sales_orders SET customer_id = p_target_id WHERE customer_id = p_source_id;
  GET DIAGNOSTICS v_so_count = ROW_COUNT;

  IF p_delete_source THEN
    UPDATE contacts SET
      is_active = false,
      deleted_at = NOW(),
      deleted_by = auth.uid()
    WHERE id = p_source_id;
  END IF;

  v_total := v_bank_count + v_cash_count + v_ct_count
           + v_crm_opp_count + v_crm_quote_count
           + v_dil_matched_count + v_dil_sugg_count
           + v_emp_count + v_label_count + v_project_count
           + v_po_count + v_so_count;

  INSERT INTO merge_history (
    company_id, entity_type, source_id, target_id,
    source_label, target_label, records_moved, source_deleted,
    performed_by
  ) VALUES (
    v_source.company_id, 'contact', p_source_id, p_target_id,
    v_source.name || ' ('
      || CASE
           WHEN COALESCE(v_source.is_customer,false) AND COALESCE(v_source.is_supplier,false) THEN 'both'
           WHEN COALESCE(v_source.is_customer,false) THEN 'customer'
           WHEN COALESCE(v_source.is_supplier,false) THEN 'supplier'
           ELSE 'none'
         END || ')',
    v_target.name || ' ('
      || CASE
           WHEN COALESCE(v_target.is_customer,false) AND COALESCE(v_target.is_supplier,false) THEN 'both'
           WHEN COALESCE(v_target.is_customer,false) THEN 'customer'
           WHEN COALESCE(v_target.is_supplier,false) THEN 'supplier'
           ELSE 'none'
         END || ')',
    v_total, p_delete_source,
    auth.uid()
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_moved', v_total,
    'source_deleted', p_delete_source,
    'counts', jsonb_build_object(
      'bank_transactions',       v_bank_count,
      'cash_transactions',       v_cash_count,
      'contact_transactions',    v_ct_count,
      'crm_opportunities',       v_crm_opp_count,
      'crm_quotes',              v_crm_quote_count,
      'data_import_matched',     v_dil_matched_count,
      'data_import_suggested',   v_dil_sugg_count,
      'employees',               v_emp_count,
      'label_templates',         v_label_count,
      'projects',                v_project_count,
      'purchase_orders',         v_po_count,
      'sales_orders',            v_so_count
    )
  );
END;
$$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('078_retail_customer_per_company.sql',
  'contacts.is_system kolonu + her şirkete "Perakende Satışlar" system contact + POS sales_orders/cash/bank_transactions backfill + companies INSERT trigger + merge_contacts is_system reject.');

COMMIT;
