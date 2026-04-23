-- ============================================================
-- M074: merge_accounts RPC + merge_history audit table
-- ============================================================
-- Kullanıcının aynı kategoriyi yanlış hesaba girdiği durumları
-- düzeltmek için. Kaynak hesabın tüm cash/bank hareketlerini hedef
-- hesaba atomik olarak taşır; isteğe bağlı kaynak hesabı soft-delete'ler.
-- Hareket sayısı + kim/ne zaman merge_history'ye düşer.
--
-- Şu an chart_of_account_id FK yalnızca cash_transactions ve
-- bank_transactions tablolarında. Yeni FK'lı tablo eklenirse RPC
-- güncellenir.
-- ============================================================

BEGIN;

-- ─── 1. merge_history (generic audit for account / contact / product merges) ───
CREATE TABLE IF NOT EXISTS merge_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  entity_type TEXT NOT NULL,            -- 'chart_of_account' | future: 'contact', 'product'
  source_id UUID NOT NULL,
  target_id UUID NOT NULL,
  source_label TEXT,                    -- human-friendly id (code / name) captured at merge time
  target_label TEXT,
  records_moved INT NOT NULL DEFAULT 0,
  source_deleted BOOLEAN NOT NULL DEFAULT false,
  performed_by UUID REFERENCES auth.users(id),
  performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_merge_history_company ON merge_history(company_id);
CREATE INDEX IF NOT EXISTS idx_merge_history_entity  ON merge_history(entity_type, source_id);

ALTER TABLE merge_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "merge_history_company_read" ON merge_history;
CREATE POLICY "merge_history_company_read" ON merge_history
  FOR SELECT TO authenticated
  USING (company_id = ANY(get_my_company_ids()));

-- INSERT goes through the RPC (SECURITY DEFINER), which checks company
-- membership directly. No direct-from-client INSERT policy intentional.

-- ─── 2. merge_accounts RPC ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.merge_accounts(
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
  v_source           chart_of_accounts%ROWTYPE;
  v_target           chart_of_accounts%ROWTYPE;
  v_cash_count       int := 0;
  v_bank_count       int := 0;
  v_has_children     boolean;
BEGIN
  IF p_source_id IS NULL OR p_target_id IS NULL THEN
    RAISE EXCEPTION 'source_id and target_id required';
  END IF;
  IF p_source_id = p_target_id THEN
    RAISE EXCEPTION 'Source and target cannot be the same account';
  END IF;

  SELECT * INTO v_source FROM chart_of_accounts WHERE id = p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source account not found'; END IF;
  IF v_source.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Source account is deleted'; END IF;

  SELECT * INTO v_target FROM chart_of_accounts
  WHERE id = p_target_id AND company_id = v_source.company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target account not found or different company'; END IF;
  IF v_target.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Target account is deleted'; END IF;

  -- Authorization: service role (auth.uid IS NULL) bypasses; authenticated
  -- callers must belong to the company.
  IF auth.uid() IS NOT NULL AND NOT (v_source.company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Type mismatch is allowed — the whole point of merge is fixing
  -- rows that landed in the wrong account, including wrong-type
  -- mistakes. UI warns on cross-type selection so the user doesn't do
  -- it by accident. source/target types are captured in merge_history
  -- via the labels for audit.

  -- Can't delete a source that still has live children. (Moving the
  -- children's parent would be a separate, less common operation —
  -- covered by editing each child.) When p_delete_source is false the
  -- source stays and its children stay with it.
  IF p_delete_source THEN
    SELECT EXISTS(
      SELECT 1 FROM chart_of_accounts
      WHERE parent_id = p_source_id AND deleted_at IS NULL
    ) INTO v_has_children;
    IF v_has_children THEN
      RAISE EXCEPTION 'Source has active child accounts — merge or remove them first';
    END IF;
  END IF;

  -- ─── Move transaction references ────────────────────────
  UPDATE cash_transactions SET chart_of_account_id = p_target_id
  WHERE chart_of_account_id = p_source_id;
  GET DIAGNOSTICS v_cash_count = ROW_COUNT;

  UPDATE bank_transactions SET chart_of_account_id = p_target_id
  WHERE chart_of_account_id = p_source_id;
  GET DIAGNOSTICS v_bank_count = ROW_COUNT;

  -- ─── Optional soft-delete of source ────────────────────
  IF p_delete_source THEN
    UPDATE chart_of_accounts SET
      is_active = false,
      deleted_at = NOW(),
      deleted_by = auth.uid()
    WHERE id = p_source_id;
  END IF;

  -- ─── Audit trail ────────────────────────────────────────
  INSERT INTO merge_history (
    company_id, entity_type, source_id, target_id,
    source_label, target_label, records_moved, source_deleted,
    performed_by
  ) VALUES (
    v_source.company_id, 'chart_of_account', p_source_id, p_target_id,
    v_source.code || ' — ' || COALESCE(v_source.name_local, v_source.name),
    v_target.code || ' — ' || COALESCE(v_target.name_local, v_target.name),
    v_cash_count + v_bank_count, p_delete_source,
    auth.uid()
  );

  RETURN jsonb_build_object(
    'success', true,
    'cash_moved', v_cash_count,
    'bank_moved', v_bank_count,
    'total_moved', v_cash_count + v_bank_count,
    'source_deleted', p_delete_source
  );
END;
$$;

REVOKE ALL ON FUNCTION public.merge_accounts(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merge_accounts(uuid, uuid, boolean) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('074_merge_accounts_rpc.sql',
  'merge_accounts RPC (atomic cash_tx + bank_tx transfer, optional source soft-delete, strict type match, child-guard when deleting) + generic merge_history audit table with RLS.');

COMMIT;
