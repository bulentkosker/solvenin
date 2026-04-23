-- ============================================================
-- M077: merge_contacts RPC (cari birleştirme)
-- ============================================================
-- Pattern: M074 (merge_accounts) + M076 (merge_products). Kaynak
-- carinin TÜM FK hareketlerini hedef cariye atomik taşır.
--
-- Kapsanan 12 FK (ccu=contacts.id üzerinden doğrulandı):
--   bank_transactions.contact_id
--   cash_transactions.contact_id
--   contact_transactions.contact_id
--   crm_opportunities.contact_id
--   crm_quotes.contact_id
--   data_import_lines.matched_contact_id
--   data_import_lines.suggested_contact_id
--   employees.contact_id
--   label_templates.contact_id
--   projects.client_id
--   purchase_orders.supplier_id
--   sales_orders.customer_id
--
-- Merge sırasında "type mismatch" (müşteri vs tedarikçi) UI
-- uyarısıdır, RPC reddetmez — yanlış yere girilmiş cariyi
-- düzeltmek merge'in meşru kullanımı.
--
-- Çalışan bağlı source için de guard YOK. UPDATE employees ile
-- bağlantı otomatik target'a taşınır; p_delete_source=true ise
-- source güvenle soft-delete edilir.
-- ============================================================

BEGIN;

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
  -- ─── Validations ────────────────────────────────────────
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

  -- Authorization: service role (auth.uid IS NULL) bypasses; authenticated
  -- callers must belong to the company.
  IF auth.uid() IS NOT NULL AND NOT (v_source.company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Type mismatch (customer vs supplier) is NOT rejected. Merge is
  -- often used to fix wrong-type entries. Target keeps its flags; if
  -- the merged source brings a new capability (e.g. was a supplier,
  -- target is only a customer), the flags are OR'd so nothing is
  -- silently dropped. Audit trail preserves both labels via merge_history.
  UPDATE contacts
     SET is_customer = COALESCE(is_customer, false) OR COALESCE(v_source.is_customer, false),
         is_supplier = COALESCE(is_supplier, false) OR COALESCE(v_source.is_supplier, false)
   WHERE id = p_target_id
     AND ((COALESCE(v_source.is_customer, false) AND NOT COALESCE(v_target.is_customer, false))
       OR (COALESCE(v_source.is_supplier, false) AND NOT COALESCE(v_target.is_supplier, false)));

  -- ─── FK taşımaları (12 adet) ─────────────────────────
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

  -- Employees: a contact linked to an employee stays linked — the
  -- target simply inherits the relationship. No guard; if the user
  -- deletes the source afterward, the employee's contact_id already
  -- points at target.
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

  -- ─── Optional soft-delete of source ────────────────────
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

  -- ─── Audit trail ───────────────────────────────────────
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

REVOKE ALL ON FUNCTION public.merge_contacts(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merge_contacts(uuid, uuid, boolean) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('077_merge_contacts_rpc.sql',
  'merge_contacts RPC — atomic 12-FK transfer (bank/cash/contact_transactions, crm_opportunities/quotes, data_import_lines matched+suggested, employees, label_templates, projects.client_id, purchase_orders.supplier_id, sales_orders.customer_id). Type flags OR-merged into target so customer↔supplier fixes don''t silently drop capabilities. No employee-guard (employees.contact_id rolls forward with merge). Audits to merge_history with entity_type=contact.');

COMMIT;
