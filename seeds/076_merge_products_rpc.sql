-- ============================================================
-- M076: merge_products RPC (ürün birleştirme)
-- ============================================================
-- Kaynak ürünün TÜM hareket/ilişkilerini hedef ürüne atomik
-- olarak taşır. Hesap merge pattern'i (M074) ile aynı yapı:
-- merge_history audit + opsiyonel soft-delete + child guard.
--
-- Kapsanan 17 FK tablosu (ccu=products.id üzerinden doğrulandı):
--   bom_inputs, bom_outputs, crm_quote_items,
--   inventory_results, inventory_sheet_items,
--   pos_quick_buttons, product_attribute_lines, product_lots,
--   product_variants.parent_product_id (!), production_entries,
--   purchase_order_items, sales_order_items,
--   serial_numbers, shipment_items,
--   stock_levels (özel: aynı depoda toplam), stock_movements,
--   work_order_parts
--
-- stock_levels özel mantığı: UNIQUE(product_id, warehouse_id)
-- kısıtı yüzünden generic UPDATE fail eder. Önce aynı depodaki
-- source+target rowlarını topla (source silinir), sonra kalan
-- source rowlarının product_id'sini target'a çevir.
--
-- Unit uyumsuzluğu (ör. adet vs kg) RPC seviyesinde reddedilmez
-- — yanlış ürün açılmış olabilir, merge'in amacı zaten bunu
-- düzeltmek. UI warning gösterir, kullanıcı karar verir.
-- ============================================================

BEGIN;

-- merge_history tablosu M074'te generic entity_type ile açılmış;
-- burada sadece entity_type='product' kayıtları düşer, tablo
-- değişikliği yok.

CREATE OR REPLACE FUNCTION public.merge_products(
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
  v_source          products%ROWTYPE;
  v_target          products%ROWTYPE;
  v_has_variants    boolean;

  -- Per-table move counts
  v_bom_in_count          int := 0;
  v_bom_out_count         int := 0;
  v_crm_quote_count       int := 0;
  v_inv_result_count      int := 0;
  v_inv_sheet_count       int := 0;
  v_pos_btn_count         int := 0;
  v_attr_line_count       int := 0;
  v_lot_count             int := 0;
  v_variant_count         int := 0;
  v_prod_entry_count      int := 0;
  v_po_item_count         int := 0;
  v_so_item_count         int := 0;
  v_serial_count          int := 0;
  v_shipment_count        int := 0;
  v_stock_level_reassign  int := 0;
  v_stock_level_summed    int := 0;
  v_stock_movement_count  int := 0;
  v_wo_parts_count        int := 0;
  v_total                 int;
BEGIN
  -- ─── Validations ───────────────────────────────────────
  IF p_source_id IS NULL OR p_target_id IS NULL THEN
    RAISE EXCEPTION 'source_id and target_id required';
  END IF;
  IF p_source_id = p_target_id THEN
    RAISE EXCEPTION 'Source and target cannot be the same product';
  END IF;

  SELECT * INTO v_source FROM products WHERE id = p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source product not found'; END IF;
  IF v_source.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Source product is deleted'; END IF;

  SELECT * INTO v_target FROM products
  WHERE id = p_target_id AND company_id = v_source.company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target product not found or different company'; END IF;
  IF v_target.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Target product is deleted'; END IF;

  -- Authorization: service role (auth.uid IS NULL) bypasses; authenticated
  -- callers must belong to the company.
  IF auth.uid() IS NOT NULL AND NOT (v_source.company_id = ANY(get_my_company_ids())) THEN
    RAISE EXCEPTION 'Not authorized for this company' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Unit mismatch is intentionally NOT rejected here. UI warns; the whole
  -- point of merge can be fixing a row that was created with the wrong
  -- unit. Both units are captured in merge_history labels for audit.

  -- Can't delete a source that still has live variants. When p_delete_source
  -- is false the source stays with its variants intact.
  IF p_delete_source THEN
    SELECT EXISTS(
      SELECT 1 FROM product_variants
      WHERE parent_product_id = p_source_id AND is_active = true
    ) INTO v_has_variants;
    IF v_has_variants THEN
      RAISE EXCEPTION 'Source has active variants — merge or remove them first';
    END IF;
  END IF;

  -- ─── stock_levels (özel: aynı depoda topla) ───────────
  -- 1) Aynı depoda her iki üründe de row varsa → target'a ekle, source'u sil.
  WITH overlapping AS (
    SELECT s.id AS src_id, s.warehouse_id, s.quantity AS src_qty
    FROM stock_levels s
    JOIN stock_levels t
      ON t.product_id = p_target_id
     AND t.warehouse_id = s.warehouse_id
    WHERE s.product_id = p_source_id
  ),
  summed AS (
    UPDATE stock_levels t
       SET quantity = t.quantity + o.src_qty,
           updated_at = NOW()
      FROM overlapping o
     WHERE t.product_id = p_target_id
       AND t.warehouse_id = o.warehouse_id
    RETURNING t.id
  ),
  deleted AS (
    DELETE FROM stock_levels WHERE id IN (SELECT src_id FROM overlapping)
    RETURNING id
  )
  SELECT COUNT(*) INTO v_stock_level_summed FROM deleted;

  -- 2) Kalan source rowları (target'ın o depoda kaydı yok) → product_id taşı.
  UPDATE stock_levels SET product_id = p_target_id, updated_at = NOW()
   WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_stock_level_reassign = ROW_COUNT;

  -- ─── Generic FK taşımaları (15 tablo) ─────────────────
  UPDATE bom_inputs SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_bom_in_count = ROW_COUNT;

  UPDATE bom_outputs SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_bom_out_count = ROW_COUNT;

  UPDATE crm_quote_items SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_crm_quote_count = ROW_COUNT;

  UPDATE inventory_results SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_inv_result_count = ROW_COUNT;

  UPDATE inventory_sheet_items SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_inv_sheet_count = ROW_COUNT;

  UPDATE pos_quick_buttons SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_pos_btn_count = ROW_COUNT;

  UPDATE product_attribute_lines SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_attr_line_count = ROW_COUNT;

  UPDATE product_lots SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_lot_count = ROW_COUNT;

  UPDATE product_variants SET parent_product_id = p_target_id WHERE parent_product_id = p_source_id;
  GET DIAGNOSTICS v_variant_count = ROW_COUNT;

  UPDATE production_entries SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_prod_entry_count = ROW_COUNT;

  UPDATE purchase_order_items SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_po_item_count = ROW_COUNT;

  UPDATE sales_order_items SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_so_item_count = ROW_COUNT;

  UPDATE serial_numbers SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_serial_count = ROW_COUNT;

  UPDATE shipment_items SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_shipment_count = ROW_COUNT;

  UPDATE stock_movements SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_stock_movement_count = ROW_COUNT;

  UPDATE work_order_parts SET product_id = p_target_id WHERE product_id = p_source_id;
  GET DIAGNOSTICS v_wo_parts_count = ROW_COUNT;

  -- ─── Optional soft-delete of source ────────────────────
  IF p_delete_source THEN
    UPDATE products SET
      is_active = false,
      deleted_at = NOW(),
      deleted_by = auth.uid()
    WHERE id = p_source_id;
  END IF;

  v_total := v_bom_in_count + v_bom_out_count + v_crm_quote_count
           + v_inv_result_count + v_inv_sheet_count + v_pos_btn_count
           + v_attr_line_count + v_lot_count + v_variant_count
           + v_prod_entry_count + v_po_item_count + v_so_item_count
           + v_serial_count + v_shipment_count
           + v_stock_level_reassign + v_stock_level_summed
           + v_stock_movement_count + v_wo_parts_count;

  -- ─── Audit trail ────────────────────────────────────────
  INSERT INTO merge_history (
    company_id, entity_type, source_id, target_id,
    source_label, target_label, records_moved, source_deleted,
    performed_by
  ) VALUES (
    v_source.company_id, 'product', p_source_id, p_target_id,
    COALESCE(v_source.sku, '') || ' — ' || v_source.name
      || ' (' || COALESCE(v_source.unit, '?') || ')',
    COALESCE(v_target.sku, '') || ' — ' || v_target.name
      || ' (' || COALESCE(v_target.unit, '?') || ')',
    v_total, p_delete_source,
    auth.uid()
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_moved', v_total,
    'source_deleted', p_delete_source,
    'counts', jsonb_build_object(
      'bom_inputs',             v_bom_in_count,
      'bom_outputs',            v_bom_out_count,
      'crm_quote_items',        v_crm_quote_count,
      'inventory_results',      v_inv_result_count,
      'inventory_sheet_items',  v_inv_sheet_count,
      'pos_quick_buttons',      v_pos_btn_count,
      'product_attribute_lines',v_attr_line_count,
      'product_lots',           v_lot_count,
      'product_variants',       v_variant_count,
      'production_entries',     v_prod_entry_count,
      'purchase_order_items',   v_po_item_count,
      'sales_order_items',      v_so_item_count,
      'serial_numbers',         v_serial_count,
      'shipment_items',         v_shipment_count,
      'stock_levels_summed',    v_stock_level_summed,
      'stock_levels_reassigned',v_stock_level_reassign,
      'stock_movements',        v_stock_movement_count,
      'work_order_parts',       v_wo_parts_count
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.merge_products(uuid, uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merge_products(uuid, uuid, boolean) TO authenticated;

INSERT INTO migrations_log (file_name, notes)
VALUES ('076_merge_products_rpc.sql',
  'merge_products RPC — atomic 17-FK transfer (bom_inputs, bom_outputs, crm_quote_items, inventory_results, inventory_sheet_items, pos_quick_buttons, product_attribute_lines, product_lots, product_variants.parent_product_id, production_entries, purchase_order_items, sales_order_items, serial_numbers, shipment_items, stock_levels [same-warehouse sum + reassign], stock_movements, work_order_parts). Variant-guard when p_delete_source=true. Unit mismatch allowed (UI warning only). Audits to merge_history with entity_type=product.');

COMMIT;
