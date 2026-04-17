-- 054_single_order_repair.sql
-- Per-order repair functions for fixing individual missing stock movements.

BEGIN;

CREATE OR REPLACE FUNCTION sp_fix_single_sales_stock(p_company_id uuid, p_order_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT soi.product_id, soi.quantity, soi.warehouse_id, so.order_number
    FROM sales_orders so
    JOIN sales_order_items soi ON soi.order_id = so.id
    WHERE so.id = p_order_id AND so.company_id = p_company_id
    AND soi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.sales_order_id = so.id AND sm.product_id = soi.product_id AND sm.type = 'out' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, sales_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, COALESCE(rec.warehouse_id, default_wh), 'out', rec.quantity, rec.order_number, p_order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

CREATE OR REPLACE FUNCTION sp_fix_single_purchase_stock(p_company_id uuid, p_order_id uuid)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $BODY$
DECLARE
  created_count int := 0;
  rec RECORD;
  default_wh uuid;
  owner_uid uuid;
BEGIN
  SELECT cu.user_id INTO owner_uid FROM company_users cu
  WHERE cu.company_id = p_company_id AND cu.role = 'owner' LIMIT 1;
  IF owner_uid IS NULL THEN
    SELECT cu.user_id INTO owner_uid FROM company_users cu WHERE cu.company_id = p_company_id LIMIT 1;
  END IF;

  SELECT id INTO default_wh FROM warehouses
  WHERE company_id = p_company_id AND is_active = true ORDER BY is_default DESC NULLS LAST LIMIT 1;

  FOR rec IN
    SELECT poi.product_id, poi.quantity, po.order_number
    FROM purchase_orders po
    JOIN purchase_order_items poi ON poi.order_id = po.id
    WHERE po.id = p_order_id AND po.company_id = p_company_id
    AND poi.product_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM stock_movements sm
      WHERE sm.purchase_order_id = po.id AND sm.product_id = poi.product_id AND sm.type = 'in' AND sm.is_active = true
    )
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, purchase_order_id, notes, is_active, created_by, reference_type)
    VALUES (p_company_id, rec.product_id, default_wh, 'in', rec.quantity, rec.order_number, p_order_id, 'Stok Onarımı — Servis Paneli', true, owner_uid, 'repair');
    created_count := created_count + 1;
  END LOOP;

  RETURN json_build_object('ok', true, 'created', created_count);
END;
$BODY$;

INSERT INTO migrations_log (file_name, notes)
VALUES ('054_single_order_repair.sql',
  'Per-order repair RPCs: sp_fix_single_sales_stock, sp_fix_single_purchase_stock')
ON CONFLICT (file_name) DO NOTHING;

COMMIT;
