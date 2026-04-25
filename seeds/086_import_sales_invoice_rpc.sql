-- ============================================================
-- M086: import_sales_invoice RPC (satış Excel import için)
-- ============================================================
-- 081'in (alış import) simetrik versiyonu. Bir Excel'i tek atomic
-- transaction'da satış faturasına çeviren RPC. Eksik ürünler
-- products tablosuna otomatik eklenir; mevcut ürünler için
-- stok kontrolü yapılır.
--
-- Önemli farklar (vs 081 alış):
--  • status = 'invoiced' (paid değil — ödeme akışı ayrı adım)
--  • stock_movements type = 'out' (satış çıkışı)
--  • Yeni ürün defaults: product_type='finished_good',
--    cost_price=0, sale_price=unit_price
--  • STOK KONTROLÜ: companies.allow_negative_stock=false ise
--    yetersiz stoğu olan satır varsa RAISE EXCEPTION (rollback)
--  • allow_negative_stock=true ise uyarı yok, satış geçer
--    ve quantity negatife düşebilir (recompute sonrası)
--  • Yetersiz stok mesajı array'i exception detail'e konur
--
-- p_items JSONB her satır:
--   { name, sku?, barcode?, unit?, quantity, unit_price,
--     description?, existing_product_id?, is_new }
-- ============================================================

CREATE OR REPLACE FUNCTION public.import_sales_invoice(
  p_company_id      uuid,
  p_customer_id     uuid,
  p_order_number    text,
  p_issue_date      date,
  p_currency_code   text,
  p_exchange_rate   numeric,
  p_tax_rate        numeric,
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
  v_base_currency        text;
  v_is_foreign           boolean;
  v_fx                   numeric;
  v_allow_negative       boolean;
  v_order_id             uuid;
  v_order_number         text;
  v_auth_uid             uuid := auth.uid();
  v_item                 jsonb;
  v_idx                  int := 0;
  v_products_created     int := 0;
  v_items_inserted       int := 0;
  v_stock_moved          int := 0;

  v_product_id           uuid;
  v_is_new               boolean;
  v_is_service           boolean;
  v_existing_qty         numeric;
  v_name                 text;
  v_sku                  text;
  v_barcode              text;
  v_unit                 text;
  v_description          text;
  v_qty                  numeric;
  v_raw_up               numeric;
  v_net_up_src           numeric;
  v_tax_up_src           numeric;
  v_net_up_base          numeric;
  v_line_total_src       numeric;
  v_line_tax_src         numeric;
  v_line_total_base      numeric;
  v_line_tax_base        numeric;

  v_subtotal_base        numeric := 0;
  v_tax_base             numeric := 0;
  v_total_base           numeric := 0;
  v_subtotal_src         numeric := 0;
  v_tax_src              numeric := 0;
  v_total_src            numeric := 0;

  v_insufficient         text[] := ARRAY[]::text[];
BEGIN
  -- ─── Validations ─────────────────────────────────────────
  IF p_company_id IS NULL THEN RAISE EXCEPTION 'company_id required'; END IF;
  IF p_customer_id IS NULL THEN RAISE EXCEPTION 'customer_id required'; END IF;
  IF p_issue_date IS NULL THEN RAISE EXCEPTION 'issue_date required'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'items array required';
  END IF;

  IF v_auth_uid IS NOT NULL AND NOT (p_company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Customer must belong to this company + be marked as customer
  IF NOT EXISTS (
    SELECT 1 FROM contacts
    WHERE id = p_customer_id AND company_id = p_company_id
      AND is_customer = true AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Customer not found or invalid for this company';
  END IF;

  IF p_warehouse_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = p_warehouse_id AND company_id = p_company_id AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Warehouse not found for this company';
  END IF;

  -- ─── Currency + negative-stock policy ───────────────────
  SELECT COALESCE(base_currency, 'KZT'), COALESCE(allow_negative_stock, false)
    INTO v_base_currency, v_allow_negative
    FROM companies WHERE id = p_company_id;

  v_fx := COALESCE(p_exchange_rate, 1);
  v_is_foreign := (p_currency_code IS NOT NULL AND p_currency_code <> v_base_currency AND v_fx <> 1);

  v_order_number := COALESCE(NULLIF(TRIM(p_order_number), ''),
                             'SO-IMP-' || to_char(now(), 'YYYYMMDDHH24MISS'));

  -- ─── Pre-validate stock for existing products (collect issues) ──
  -- Yeni ürünler stok 0 ile oluşturulacak; satış miktarı insufficient
  -- sayılır. allow_negative_stock = true ise hiçbir şey reddetmiyoruz.
  IF NOT v_allow_negative THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
      v_name        := NULLIF(TRIM(v_item->>'name'), '');
      v_qty         := COALESCE((v_item->>'quantity')::numeric, 0);
      v_is_new      := COALESCE((v_item->>'is_new')::boolean, false);
      v_product_id  := NULLIF(v_item->>'existing_product_id', '')::uuid;

      IF v_is_new OR v_product_id IS NULL THEN
        -- Yeni ürün → stok=0, satış miktarı kadar açık
        v_insufficient := v_insufficient
          || format('%s: 0 mevcut, %s satılıyor (yeni ürün)', COALESCE(v_name,'?'), v_qty);
      ELSE
        SELECT COALESCE(quantity, 0), COALESCE(is_service, false)
          INTO v_existing_qty, v_is_service
          FROM products WHERE id = v_product_id;
        -- Hizmet ürünlerinde stok takibi yok
        IF NOT v_is_service AND v_existing_qty < v_qty THEN
          v_insufficient := v_insufficient
            || format('%s: %s mevcut, %s satılıyor', COALESCE(v_name,'?'), v_existing_qty, v_qty);
        END IF;
      END IF;
    END LOOP;

    IF array_length(v_insufficient, 1) > 0 THEN
      RAISE EXCEPTION 'Insufficient stock for % item(s). Toggle "Allow negative stock" or restock first. Details: %',
        array_length(v_insufficient, 1),
        array_to_string(v_insufficient, ' | ')
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- ─── Sales order insert (totals updated after items) ────
  INSERT INTO sales_orders (
    company_id, customer_id, order_number, status,
    issue_date, subtotal, tax_rate, tax_amount, discount, total,
    currency_code, exchange_rate, total_foreign,
    notes, created_by, is_active, was_invoiced, order_type
  ) VALUES (
    p_company_id, p_customer_id, v_order_number, 'invoiced',
    p_issue_date, 0, COALESCE(p_tax_rate, 0), 0, 0, 0,
    CASE WHEN v_is_foreign THEN p_currency_code ELSE NULL END,
    v_fx,
    NULL,
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_auth_uid, true, true, 'sale'
  ) RETURNING id INTO v_order_id;

  -- ─── Each item: create-if-new + insert item + stock movement ──
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

    IF v_name IS NULL THEN RAISE EXCEPTION 'Row %: product name required', v_idx; END IF;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Row % (%): quantity must be > 0', v_idx, v_name; END IF;
    IF v_raw_up <= 0 THEN RAISE EXCEPTION 'Row % (%): unit_price must be > 0', v_idx, v_name; END IF;

    -- Tax-inclusive → net normalize
    IF p_tax_included AND COALESCE(p_tax_rate, 0) > 0 THEN
      v_net_up_src := v_raw_up / (1 + p_tax_rate / 100);
    ELSE
      v_net_up_src := v_raw_up;
    END IF;
    v_tax_up_src := v_net_up_src * COALESCE(p_tax_rate, 0) / 100;

    IF v_is_foreign THEN
      v_net_up_base := v_net_up_src * v_fx;
    ELSE
      v_net_up_base := v_net_up_src;
    END IF;

    v_line_total_src  := v_qty * v_net_up_src;
    v_line_tax_src    := v_qty * v_tax_up_src;
    v_line_total_base := v_qty * v_net_up_base;
    v_line_tax_base   := v_line_tax_src * CASE WHEN v_is_foreign THEN v_fx ELSE 1 END;

    -- Yeni ürün → INSERT
    IF v_is_new OR v_product_id IS NULL THEN
      INSERT INTO products (
        company_id, name, sku, barcode, unit,
        cost_price, sale_price, quantity,
        product_type, is_service, is_active
      ) VALUES (
        p_company_id, v_name, v_sku, v_barcode, COALESCE(v_unit, 'adet'),
        0, v_net_up_base, 0,
        'finished_good', false, true
      ) RETURNING id INTO v_product_id;
      v_products_created := v_products_created + 1;
      v_is_service := false;
    ELSE
      SELECT COALESCE(is_service, false) INTO v_is_service
      FROM products WHERE id = v_product_id AND company_id = p_company_id AND is_active = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Row % (%): existing_product_id invalid for this company', v_idx, v_name;
      END IF;
    END IF;

    -- Line item
    INSERT INTO sales_order_items (
      order_id, product_id, description, quantity,
      unit_price, unit_price_foreign,
      total, total_foreign,
      tax_rate_value, tax_amount,
      warehouse_id, discount
    ) VALUES (
      v_order_id, v_product_id, v_description, v_qty,
      v_net_up_base,
      CASE WHEN v_is_foreign THEN v_net_up_src ELSE NULL END,
      v_line_total_base,
      CASE WHEN v_is_foreign THEN v_line_total_src ELSE NULL END,
      COALESCE(p_tax_rate, 0), v_line_tax_base,
      p_warehouse_id, 0
    );
    v_items_inserted := v_items_inserted + 1;

    -- Stock movement (out) — fiziksel ürün + warehouse
    IF NOT v_is_service AND p_warehouse_id IS NOT NULL THEN
      INSERT INTO stock_movements (
        company_id, product_id, warehouse_id, type, quantity,
        sales_order_id, reference_type, reference,
        notes, created_by
      ) VALUES (
        p_company_id, v_product_id, p_warehouse_id, 'out', v_qty,
        v_order_id, 'sales_order', v_order_number,
        NULLIF(TRIM(COALESCE(p_notes, '')), ''), v_auth_uid
      );
      v_stock_moved := v_stock_moved + 1;

      -- products.quantity recompute (sm 'in' +, 'out' -)
      UPDATE products p SET
        quantity = COALESCE((
          SELECT SUM(CASE WHEN sm.type = 'in' THEN sm.quantity ELSE -sm.quantity END)
            FROM stock_movements sm
           WHERE sm.product_id = p.id
             AND sm.is_active = true
             AND sm.deleted_at IS NULL
        ), 0)
      WHERE p.id = v_product_id;
    END IF;

    v_subtotal_base := v_subtotal_base + v_line_total_base;
    v_tax_base      := v_tax_base      + v_line_tax_base;
    v_subtotal_src  := v_subtotal_src  + v_line_total_src;
    v_tax_src       := v_tax_src       + v_line_tax_src;
  END LOOP;

  v_total_base := v_subtotal_base + v_tax_base;
  v_total_src  := v_subtotal_src  + v_tax_src;

  UPDATE sales_orders SET
    subtotal      = v_subtotal_base,
    tax_amount    = v_tax_base,
    total         = v_total_base,
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
    'currency_code', CASE WHEN v_is_foreign THEN p_currency_code ELSE v_base_currency END,
    'allow_negative_stock', v_allow_negative
  );
END;
$$;

REVOKE ALL ON FUNCTION public.import_sales_invoice(uuid, uuid, text, date, text, numeric, numeric, boolean, uuid, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.import_sales_invoice(uuid, uuid, text, date, text, numeric, numeric, boolean, uuid, jsonb, text) TO authenticated;

INSERT INTO public.migrations_log (file_name, notes)
VALUES ('086_import_sales_invoice_rpc.sql',
  'import_sales_invoice RPC — satış Excel import için 081 simetrik. status=invoiced, stock_movements type=out, products.quantity recompute. Stok kontrolü: companies.allow_negative_stock=false ise yetersiz stok varsa RAISE EXCEPTION; true ise satış geçer, qty negatife düşebilir. Yeni ürünler product_type=finished_good.')
ON CONFLICT (file_name) DO NOTHING;
