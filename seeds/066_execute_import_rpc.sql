-- ============================================================
-- M066: execute_import(p_import_id uuid) — atomic Step 4 write
-- ============================================================
-- Writes confirmed data_import_lines into bank_transactions (+
-- contact_transactions, own_transfer counterparts, expense category,
-- auto-BIN updates). All within a single PL/pgSQL transaction — any
-- RAISE triggers automatic rollback of every preceding INSERT/UPDATE.
--
-- Inputs:
--   p_import_id — the data_imports.id to finalize
--
-- Returns jsonb:
--   { success, imported_count, skipped_count, bank_transaction_ids[],
--     updated_contacts[], new_contact_ids[], account_id, final_balance }
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.execute_import(p_import_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_import              data_imports%ROWTYPE;
  v_line                data_import_lines%ROWTYPE;
  v_company_id          uuid;
  v_account_id          uuid;
  v_currency            varchar;
  v_bank_tx_id          uuid;
  v_target_bank_tx_id   uuid;
  v_target_currency     varchar;
  v_target_accounts     uuid[] := ARRAY[]::uuid[];
  v_new_contact_ids     jsonb := '[]'::jsonb;
  v_updated_contact_ids jsonb := '[]'::jsonb;
  v_bank_tx_ids         jsonb := '[]'::jsonb;
  v_inserted            int   := 0;
  v_skipped             int   := 0;
  v_duplicate           int   := 0;
  v_type                varchar;
  v_target_type         varchar;
  v_amount              numeric;
  v_final_balance       numeric;
BEGIN
  -- Atomic status transition: only 'parsed' can become 'imported'.
  -- If another session beat us here, FOUND is false → raise.
  UPDATE data_imports
  SET status = 'imported',
      imported_at = NOW(),
      imported_by = auth.uid()
  WHERE id = p_import_id
    AND status = 'parsed'
    AND deleted_at IS NULL
  RETURNING * INTO v_import;

  IF NOT FOUND THEN
    -- Figure out why for a better message.
    SELECT * INTO v_import FROM data_imports WHERE id = p_import_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Import not found: %', p_import_id USING ERRCODE = 'no_data_found';
    ELSIF v_import.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Import deleted';
    ELSIF v_import.status = 'imported' THEN
      RAISE EXCEPTION 'Import already processed (status=imported)' USING ERRCODE = 'unique_violation';
    ELSE
      RAISE EXCEPTION 'Import not in parsed state (status=%)', v_import.status;
    END IF;
  END IF;

  -- Authorization: authenticated callers must be members of the import's
  -- company. Service-role callers (auth.uid() IS NULL) bypass — they already
  -- have full DB access and this RPC is the audited write path.
  IF auth.uid() IS NOT NULL AND NOT (v_import.company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized to execute this import' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_company_id := v_import.company_id;
  v_account_id := v_import.bank_account_id;
  IF v_account_id IS NULL THEN
    RAISE EXCEPTION 'Import missing bank_account_id';
  END IF;

  SELECT currency_code INTO v_currency FROM bank_accounts
  WHERE id = v_account_id AND company_id = v_company_id;
  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'Bank account not found or wrong company';
  END IF;

  -- Iterate lines deterministically; cursor-style FOR inside one transaction.
  FOR v_line IN
    SELECT * FROM data_import_lines
    WHERE import_id = p_import_id
      AND is_skipped = FALSE
    ORDER BY line_number
  LOOP
    -- Auto-BIN backfill: if the matched contact has no tax_number and the
    -- line carries one, fill it (only for NULL → non-NULL transitions).
    IF v_line.auto_bin_update IS NOT NULL AND v_line.matched_contact_id IS NOT NULL THEN
      UPDATE contacts
      SET tax_number = v_line.auto_bin_update, updated_at = NOW()
      WHERE id = v_line.matched_contact_id
        AND company_id = v_company_id
        AND tax_number IS NULL;
      IF FOUND THEN
        v_updated_contact_ids := v_updated_contact_ids || to_jsonb(v_line.matched_contact_id);
      END IF;
    END IF;

    -- Duplicate: don't insert into bank_transactions, just mark confirmed.
    IF v_line.match_type = 'duplicate' THEN
      v_duplicate := v_duplicate + 1;
      CONTINUE;
    END IF;

    -- Skipped rows already filtered by WHERE; defensive.
    IF v_line.is_skipped THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Direction + amount. If both debit and credit are >0 (shouldn't happen,
    -- but be defensive), credit wins.
    v_type := CASE WHEN COALESCE(v_line.credit, 0) > 0 THEN 'in' ELSE 'out' END;
    v_amount := CASE
      WHEN COALESCE(v_line.credit, 0) > 0 THEN v_line.credit
      WHEN COALESCE(v_line.debit,  0) > 0 THEN v_line.debit
      ELSE 0
    END;
    IF v_amount = 0 THEN
      -- Zero-amount rows are meaningless for a bank transaction; skip.
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- ─── bank_transactions INSERT (the main row) ───
    -- Defensive truncation: PDF extractions can produce descriptions/
    -- counterparty strings longer than the column limits (description
    -- VARCHAR(255), counterparty VARCHAR(100), external_reference VARCHAR(100)).
    -- description is NOT NULL so we coalesce through counterparty → a
    -- dated fallback label as a last resort.
    INSERT INTO bank_transactions (
      company_id, account_id, type, amount, currency_code,
      description, category, source_type, reference, external_reference,
      counterparty, counterparty_bin, knp_code, document_number,
      transaction_date, value_date, import_id,
      reconciliation_status, contact_id, created_by
    ) VALUES (
      v_company_id, v_account_id, v_type, v_amount, v_currency,
      LEFT(COALESCE(NULLIF(v_line.payment_details, ''),
                    NULLIF(v_line.counterparty_name, ''),
                    'Banka hareketi ' || v_line.transaction_date::text), 255),
      CASE
        WHEN v_line.match_type = 'employee'        THEN 'salary'
        WHEN v_line.match_type = 'expense_account' THEN LEFT((SELECT code FROM chart_of_accounts WHERE id = v_line.matched_account_id), 50)
        ELSE NULL
      END,
      CASE WHEN v_line.match_type = 'own_transfer' THEN 'own_transfer' ELSE 'bank_import' END,
      NULL,
      LEFT(v_line.external_reference, 100),
      LEFT(v_line.counterparty_name, 100), v_line.counterparty_bin,
      v_line.knp_code, v_line.document_number,
      v_line.transaction_date, v_line.transaction_date,
      p_import_id,
      'confirmed',
      CASE WHEN v_line.match_type IN ('contact','suggestion') THEN v_line.matched_contact_id ELSE NULL END,
      auth.uid()
    )
    RETURNING id INTO v_bank_tx_id;

    v_bank_tx_ids := v_bank_tx_ids || to_jsonb(v_bank_tx_id);

    -- ─── contact_transactions (cari hareketi) ───
    IF v_line.match_type IN ('contact','suggestion') AND v_line.matched_contact_id IS NOT NULL THEN
      INSERT INTO contact_transactions (
        company_id, contact_id, type, amount, date,
        description, reference, bank_transaction_id, created_by
      ) VALUES (
        v_company_id, v_line.matched_contact_id,
        -- From the contact's perspective: money OUT of us → credit the contact
        -- (receivable reduced / payable increased), money IN → debit them.
        CASE WHEN v_type = 'in' THEN 'credit' ELSE 'debit' END,
        v_amount, v_line.transaction_date,
        LEFT(v_line.payment_details, 255), LEFT(v_line.external_reference, 100), v_bank_tx_id, auth.uid()
      );
    END IF;

    -- ─── Own transfer: counterpart row on target account ───
    IF v_line.match_type = 'own_transfer' AND v_line.target_bank_account_id IS NOT NULL THEN
      SELECT currency_code INTO v_target_currency FROM bank_accounts WHERE id = v_line.target_bank_account_id AND company_id = v_company_id;
      IF v_target_currency IS NULL THEN
        RAISE EXCEPTION 'Target bank account % not found or wrong company', v_line.target_bank_account_id;
      END IF;
      v_target_type := CASE WHEN v_type = 'in' THEN 'out' ELSE 'in' END;
      INSERT INTO bank_transactions (
        company_id, account_id, type, amount, currency_code,
        description, source_type, reference, external_reference,
        counterparty, counterparty_bin, transaction_date, value_date, import_id,
        reconciliation_status, created_by
      ) VALUES (
        v_company_id, v_line.target_bank_account_id, v_target_type, v_amount,
        v_target_currency,
        LEFT(COALESCE(NULLIF(v_line.payment_details, ''),
                      NULLIF(v_line.counterparty_name, ''),
                      'Kendi hesap transfer ' || v_line.transaction_date::text), 255), 'own_transfer',
        LEFT(v_bank_tx_id::text, 100),
        LEFT(v_line.external_reference, 100),
        LEFT(v_line.counterparty_name, 100), v_line.counterparty_bin,
        v_line.transaction_date, v_line.transaction_date,
        p_import_id, 'confirmed', auth.uid()
      )
      RETURNING id INTO v_target_bank_tx_id;
      -- Back-reference on the source row.
      UPDATE bank_transactions SET reference = v_target_bank_tx_id::text WHERE id = v_bank_tx_id;
      v_bank_tx_ids := v_bank_tx_ids || to_jsonb(v_target_bank_tx_id);

      IF NOT (v_line.target_bank_account_id = ANY(v_target_accounts)) THEN
        v_target_accounts := v_target_accounts || v_line.target_bank_account_id;
      END IF;
    END IF;

    v_inserted := v_inserted + 1;
  END LOOP;

  -- ─── Recompute bank_account balances from the ledger ───
  -- Source of truth: opening_balance + sum of non-deleted bank_transactions.
  UPDATE bank_accounts ba
  SET current_balance = COALESCE(ba.opening_balance, 0) + COALESCE((
    SELECT SUM(CASE WHEN bt.type = 'in' THEN bt.amount ELSE -bt.amount END)
    FROM bank_transactions bt
    WHERE bt.account_id = ba.id AND bt.deleted_at IS NULL
  ), 0)
  WHERE ba.id = v_account_id
     OR ba.id = ANY(v_target_accounts);

  SELECT current_balance INTO v_final_balance FROM bank_accounts WHERE id = v_account_id;

  -- ─── Template stats ───
  IF v_import.template_id IS NOT NULL THEN
    UPDATE import_templates
    SET usage_count  = COALESCE(usage_count, 0) + 1,
        success_count= COALESCE(success_count, 0) + 1,
        last_used_at = NOW()
    WHERE id = v_import.template_id;
  END IF;

  -- ─── Finalize data_imports counts ───
  UPDATE data_imports
  SET success_rows = v_inserted,
      error_rows   = 0,
      total_rows   = v_inserted + v_duplicate + v_skipped
  WHERE id = p_import_id;

  -- New contacts: any contact whose id appears in this import's lines AND was
  -- created at or after the import's created_at. Reports UI-created contacts.
  SELECT COALESCE(jsonb_agg(id), '[]'::jsonb) INTO v_new_contact_ids
  FROM (
    SELECT DISTINCT c.id
    FROM contacts c
    WHERE c.company_id = v_company_id
      AND c.created_at >= v_import.created_at
      AND c.id IN (
        SELECT matched_contact_id FROM data_import_lines
        WHERE import_id = p_import_id AND matched_contact_id IS NOT NULL
      )
  ) q;

  RETURN jsonb_build_object(
    'success',             true,
    'imported_count',      v_inserted,
    'duplicate_count',     v_duplicate,
    'skipped_count',       v_skipped,
    'bank_transaction_ids',v_bank_tx_ids,
    'updated_contact_ids', v_updated_contact_ids,
    'new_contact_ids',     v_new_contact_ids,
    'account_id',          v_account_id,
    'final_balance',       v_final_balance,
    'target_accounts',     to_jsonb(v_target_accounts)
  );
END;
$$;

-- Callable by authenticated users (RLS + ownership check inside function).
REVOKE ALL ON FUNCTION public.execute_import(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.execute_import(uuid) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('066_execute_import_rpc.sql',
  'execute_import(p_import_id) — atomic Step 4 RPC: bank_transactions + contact_transactions + own_transfer + category + balance recompute + template stats.')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
