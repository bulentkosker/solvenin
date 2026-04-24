-- ============================================================
-- M081: import_purchase_invoice RPC (Excel import için)
-- ============================================================
-- Tedarikçi Excel'ini parse edip yeni alış faturası açar.
-- Atomic: tüm işlem tek transaction'da — herhangi bir adım
-- fail olursa full rollback. Yeni ürünler products tablosuna
-- eklenir (is_new=true olanlar). Stok hareketi warehouse_id'ye
-- bağlı olarak stock_movements'a düşer (is_service=false için).
--
-- Fatura status = 'invoiced' olarak açılır (purchase_orders_status_check
-- constraint'i: draft/confirmed/invoiced/paid/cancelled). Ödeme kaydı
-- YOK — kullanıcı sonradan ödeme girer. Stok hareketi RPC içinde
-- manuel insert edilir (warehouse verilmişse + non-service).
-- currency_code NULL ise yerel
-- para birimi, yoksa foreign kolonlar doldurulur (mevcut
-- saveOrder pattern'i).
--
-- p_items JSONB şeması (her satır):
--   {
--     name: text (required),
--     sku: text | null,
--     barcode: text | null,
--     unit: text | null,
--     quantity: numeric (>0),
--     unit_price: numeric (source currency, tax_included flag'e göre),
--     description: text | null,
--     existing_product_id: uuid | null,  -- null ise yeni ürün oluşturulur
--     is_new: boolean                    -- true ise products INSERT yap
--   }
--
-- Vergi mantığı (mevcut saveOrder ile hizalı):
--   tax_included = true  → net = raw / (1 + rate/100)
--   tax_included = false → net = raw
--   tax_amount_per_unit = net * rate / 100
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.import_purchase_invoice(
  p_company_id      uuid,
  p_supplier_id     uuid,
  p_order_number    text,
  p_issue_date      date,
  p_currency_code   text,     -- NULL veya base_currency ise domestic
  p_exchange_rate   numeric,  -- domestic ise 1
  p_tax_rate        numeric,  -- % (örn 16)
  p_tax_included    boolean,
  p_warehouse_id    uuid,
  p_items           jsonb,
  p_notes           text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base_currency   text;
  v_is_foreign      boolean;
  v_fx              numeric;
  v_order_id        uuid;
  v_order_number    text;
  v_auth_uid        uuid := auth.uid();
  v_item            jsonb;
  v_idx             int := 0;
  v_products_created int := 0;
  v_items_inserted  int := 0;
  v_stock_moved     int := 0;

  v_product_id      uuid;
  v_is_new          boolean;
  v_is_service      boolean;
  v_name            text;
  v_sku             text;
  v_barcode         text;
  v_unit            text;
  v_description     text;
  v_qty             numeric;
  v_raw_up          numeric;  -- Excel'den gelen fiyat (source cur)
  v_net_up_src      numeric;  -- tax hariç (source cur)
  v_tax_up_src      numeric;
  v_net_up_base     numeric;
  v_line_total_src  numeric;
  v_line_tax_src    numeric;
  v_line_total_base numeric;
  v_line_tax_base   numeric;

  v_subtotal_base   numeric := 0;
  v_tax_base        numeric := 0;
  v_total_base      numeric := 0;
  v_subtotal_src    numeric := 0;
  v_tax_src         numeric := 0;
  v_total_src       numeric := 0;
BEGIN
  -- ─── Validations ─────────────────────────────────────────
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id required'; END IF;
  IF p_supplier_id IS NULL THEN RAISE EXCEPTION 'supplier_id required'; END IF;
  IF p_issue_date IS NULL THEN RAISE EXCEPTION 'issue_date required'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items array required';
  END IF;

  -- Authorization: service role (auth.uid IS NULL) geçer; aksi halde şirket üyeliği kontrol et
  IF v_auth_uid IS NOT NULL AND NOT (p_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Supplier aynı şirketten olmalı
  IF NOT EXISTS (
    SELECT 1 FROM contacts
    WHERE id = p_supplier_id AND company_id = p_company_id
      AND is_supplier = true AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Supplier not found or invalid for this company';
  END IF;

  -- Warehouse (opsiyonel ama verilirse aynı şirketten olmalı)
  IF p_warehouse_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = p_warehouse_id AND company_id = p_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Warehouse not found for this company';
  END IF;

  -- ─── Currency ────────────────────────────────────────────
  SELECT COALESCE(base_currency, 'KZT') INTO v_base_currency
  FROM companies WHERE id = p_company_id;

  v_fx := COALESCE(p_exchange_rate, 1);
  v_is_foreign := (p_currency_code IS NOT NULL AND p_currency_code <> v_base_currency AND v_fx <> 1);

  -- ─── Order number (otomatik fallback) ───────────────────
  v_order_number := COALESCE(NULLIF(TRIM(p_order_number), ''),
                             'PO-IMP-' || to_char(now(), 'YYYYMMDDHH24MISS'));

  -- ─── Purchase order insert (totals sonra update edilecek) ───
  INSERT INTO purchase_orders (
    company_id, supplier_id, order_number, status,
    issue_date, subtotal, tax_rate, tax_amount, discount, total,
    currency_code, exchange_rate, total_foreign,
    notes, created_by, is_active
  ) VALUES (
    p_company_id, p_supplier_id, v_order_number, 'invoiced',
    p_issue_date, 0, COALESCE(p_tax_rate, 0), 0, 0, 0,
    CASE WHEN v_is_foreign THEN p_currency_code ELSE NULL END,
    v_fx,
    NULL,
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_auth_uid, true
  ) RETURNING id INTO v_order_id;

  -- ─── Her item için process ──────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_idx := v_idx + 1;

    v_name        := NULLIF(TRIM(v_item->>'name'), '');
    v_sku         := NULLIF(TRIM(v_item->>'sku'), '');
    v_barcode     := NULLIF(TRIM(v_item->>'barcode'), '');
    v_unit        := NULLIF(TRIM(v_item->>'unit'), '');
    v_description := NULLIF(TRIM(v_item->>'description'), '');
    v_qty         := COALESCE((v_item->>'quantity')::numeric, 0);
    v_raw_up      := COALESCE((v_item->>'unit_price')::numeric, 0);
    v_is_new      := COALESCE((v_item->>'is_new')::boolean, false);
    v_product_id  := NULLIF(v_item->>'existing_product_id', '')::uuid;

    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Row %: product name required', v_idx;
    END IF;
    IF v_qty <= 0 THEN
      RAISE EXCEPTION 'Row % (%): quantity must be > 0', v_idx, v_name;
    END IF;
    IF v_raw_up <= 0 THEN
      RAISE EXCEPTION 'Row % (%): unit_price must be > 0', v_idx, v_name;
    END IF;

    -- Tax-inclusive → net'e normalize
    IF p_tax_included AND COALESCE(p_tax_rate, 0) > 0 THEN
      v_net_up_src := v_raw_up / (1 + p_tax_rate / 100);
    ELSE
      v_net_up_src := v_raw_up;
    END IF;
    v_tax_up_src := v_net_up_src * COALESCE(p_tax_rate, 0) / 100;

    -- FX conversion
    IF v_is_foreign THEN
      v_net_up_base := v_net_up_src * v_fx;
    ELSE
      v_net_up_base := v_net_up_src;
    END IF;

    v_line_total_src := v_qty * v_net_up_src;
    v_line_tax_src   := v_qty * v_tax_up_src;
    v_line_total_base := v_qty * v_net_up_base;
    v_line_tax_base   := v_line_tax_src * CASE WHEN v_is_foreign THEN v_fx ELSE 1 END;

    -- Yeni ürün oluştur
    IF v_is_new OR v_product_id IS NULL THEN
      INSERT INTO products (
        company_id, name, sku, barcode, unit,
        cost_price, sale_price, quantity,
        product_type, is_service, is_active
      ) VALUES (
        p_company_id, v_name, v_sku, v_barcode, COALESCE(v_unit, 'adet'),
        v_net_up_base, 0, 0,
        'raw_material', false, true
      ) RETURNING id INTO v_product_id;
      v_products_created := v_products_created + 1;
      v_is_service := false;
    ELSE
      -- Var olan ürünü doğrula (aynı şirket, aktif)
      SELECT COALESCE(is_service, false) INTO v_is_service
      FROM products
      WHERE id = v_product_id AND company_id = p_company_id AND is_active = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Row % (%): existing_product_id invalid for this company', v_idx, v_name;
      END IF;
    END IF;

    -- Line item insert
    INSERT INTO purchase_order_items (
      order_id, product_id, description, quantity,
      unit_price, unit_price_foreign,
      total, total_foreign,
      tax_rate_value, tax_amount,
      warehouse_id, received_qty
    ) VALUES (
      v_order_id, v_product_id, v_description, v_qty,
      v_net_up_base,
      CASE WHEN v_is_foreign THEN v_net_up_src ELSE NULL END,
      v_line_total_base,
      CASE WHEN v_is_foreign THEN v_line_total_src ELSE NULL END,
      COALESCE(p_tax_rate, 0), v_line_tax_base,
      p_warehouse_id, v_qty
    );
    v_items_inserted := v_items_inserted + 1;

    -- Stock movement (sadece fiziksel ürün + warehouse verilmişse)
    IF NOT v_is_service AND p_warehouse_id IS NOT NULL THEN
      INSERT INTO stock_movements (
        company_id, product_id, warehouse_id, type, quantity,
        purchase_order_id, reference_type, reference,
        notes, created_by
      ) VALUES (
        p_company_id, v_product_id, p_warehouse_id, 'in', v_qty,
        v_order_id, 'purchase_order', v_order_number,
        NULLIF(TRIM(COALESCE(p_notes, '')), ''), v_auth_uid
      );
      v_stock_moved := v_stock_moved + 1;
    END IF;

    v_subtotal_base := v_subtotal_base + v_line_total_base;
    v_tax_base      := v_tax_base      + v_line_tax_base;
    v_subtotal_src  := v_subtotal_src  + v_line_total_src;
    v_tax_src       := v_tax_src       + v_line_tax_src;
  END LOOP;

  v_total_base := v_subtotal_base + v_tax_base;
  v_total_src  := v_subtotal_src  + v_tax_src;

  -- Totals update
  UPDATE purchase_orders SET
    subtotal     = v_subtotal_base,
    tax_amount   = v_tax_base,
    total        = v_total_base,
    total_foreign = CASE WHEN v_is_foreign THEN v_total_src ELSE NULL END
  WHERE id = v_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'order_number', v_order_number,
    'items_count', v_items_inserted,
    'products_created', v_products_created,
    'stock_movements_created', v_stock_moved,
    'subtotal', v_subtotal_base,
    'tax_amount', v_tax_base,
    'total', v_total_base,
    'currency_code', CASE WHEN v_is_foreign THEN p_currency_code ELSE v_base_currency END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.import_purchase_invoice(uuid, uuid, text, date, text, numeric, numeric, boolean, uuid, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_purchase_invoice(uuid, uuid, text, date, text, numeric, numeric, boolean, uuid, jsonb, text) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('081_import_purchase_invoice_rpc.sql',
  'import_purchase_invoice RPC — Excel import akışı için atomic: yeni ürünler (is_new=true olanlar) + purchase_orders (status=received) + purchase_order_items + stock_movements (non-service + warehouse varsa). Vergi hariç/dahil normalizasyonu ve foreign currency handling mevcut saveOrder pattern''i ile hizalı.')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
