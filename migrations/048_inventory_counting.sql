-- Migration 048: Inventory counting module
-- (M046/M047 already used for anthropic key + app_settings.updated_at)

CREATE TABLE IF NOT EXISTS inventory_sessions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  reference_datetime timestamptz NOT NULL,
  warehouse_id uuid REFERENCES warehouses(id) ON DELETE SET NULL,
  category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
  status varchar(20) DEFAULT 'active' CHECK (status IN ('active','completed','approved')),
  variance_threshold_pct decimal DEFAULT 2.0,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_sheets (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES inventory_sessions(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  sheet_number serial,
  section_name text,
  counted_by uuid REFERENCES auth.users(id),
  status varchar(20) DEFAULT 'open' CHECK (status IN ('open','completed','locked')),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_sheet_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sheet_id uuid NOT NULL REFERENCES inventory_sheets(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES inventory_sessions(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  barcode text,
  counted_quantity decimal NOT NULL,
  unit varchar(20),
  via_barcode boolean DEFAULT false,
  notes text,
  counted_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS inventory_results (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES inventory_sessions(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES products(id),
  system_quantity decimal DEFAULT 0,
  counted_quantity decimal DEFAULT 0,
  variance decimal DEFAULT 0,
  variance_pct decimal DEFAULT 0,
  status varchar(20) DEFAULT 'pending' CHECK (status IN ('pending','approved','recount','auto_approved')),
  variance_reason varchar(50),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  notes text,
  UNIQUE(session_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_inv_sessions_company_status ON inventory_sessions(company_id, status);
CREATE INDEX IF NOT EXISTS idx_inv_sheets_session_status   ON inventory_sheets(session_id, status);
CREATE INDEX IF NOT EXISTS idx_inv_items_session_product   ON inventory_sheet_items(session_id, product_id);
CREATE INDEX IF NOT EXISTS idx_inv_items_sheet             ON inventory_sheet_items(sheet_id);
CREATE INDEX IF NOT EXISTS idx_inv_results_session_product ON inventory_results(session_id, product_id);

ALTER TABLE inventory_sessions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_sheets       ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_sheet_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_results      ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['inventory_sessions','inventory_sheets','inventory_sheet_items','inventory_results']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_insert ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_update ON %I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_delete ON %I', t, t);
    EXECUTE format('CREATE POLICY %I_select ON %I FOR SELECT USING (company_id = ANY (get_my_company_ids()))', t, t);
    EXECUTE format('CREATE POLICY %I_insert ON %I FOR INSERT WITH CHECK (company_id = ANY (get_my_company_ids()))', t, t);
    EXECUTE format('CREATE POLICY %I_update ON %I FOR UPDATE USING (company_id = ANY (get_my_company_ids())) WITH CHECK (company_id = ANY (get_my_company_ids()))', t, t);
    EXECUTE format('CREATE POLICY %I_delete ON %I FOR DELETE USING (company_id = ANY (get_my_company_ids()))', t, t);
  END LOOP;
END $$;

-- Auto-touch updated_at
DROP TRIGGER IF EXISTS inv_sessions_touch ON inventory_sessions;
CREATE TRIGGER inv_sessions_touch BEFORE UPDATE ON inventory_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
DROP TRIGGER IF EXISTS inv_sheets_touch ON inventory_sheets;
CREATE TRIGGER inv_sheets_touch BEFORE UPDATE ON inventory_sheets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Helper: system quantity at session reference_datetime
CREATE OR REPLACE FUNCTION inventory_system_qty(p_session uuid)
RETURNS TABLE(product_id uuid, qty decimal)
LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE v_ref timestamptz; v_wh uuid; v_company uuid;
BEGIN
  SELECT reference_datetime, warehouse_id, company_id INTO v_ref, v_wh, v_company
  FROM inventory_sessions WHERE id = p_session;
  RETURN QUERY
  SELECT m.product_id,
    SUM(CASE WHEN m.type IN ('in','return') THEN m.quantity ELSE -m.quantity END)::decimal
  FROM stock_movements m
  WHERE m.company_id = v_company
    AND m.created_at <= v_ref
    AND COALESCE(m.is_active, true) = true
    AND (v_wh IS NULL OR m.warehouse_id = v_wh)
  GROUP BY m.product_id;
END $$;
GRANT EXECUTE ON FUNCTION inventory_system_qty(uuid) TO authenticated;

-- Compute and upsert results + auto-approve <= threshold
CREATE OR REPLACE FUNCTION sp_inventory_compute_results(p_session uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_threshold decimal; v_company uuid;
BEGIN
  SELECT variance_threshold_pct, company_id INTO v_threshold, v_company FROM inventory_sessions WHERE id = p_session;
  IF v_company IS NULL THEN RETURN jsonb_build_object('error','session_not_found'); END IF;

  -- Build per-product counted totals
  WITH counted AS (
    SELECT product_id, SUM(counted_quantity)::decimal AS qty
    FROM inventory_sheet_items
    WHERE session_id = p_session
    GROUP BY product_id
  ), sysq AS (
    SELECT product_id, qty FROM inventory_system_qty(p_session)
  ), combined AS (
    SELECT COALESCE(c.product_id, s.product_id) AS product_id,
           COALESCE(s.qty, 0) AS system_quantity,
           COALESCE(c.qty, 0) AS counted_quantity
    FROM counted c FULL OUTER JOIN sysq s ON s.product_id = c.product_id
  )
  INSERT INTO inventory_results (session_id, company_id, product_id, system_quantity, counted_quantity, variance, variance_pct, status)
  SELECT p_session, v_company, cb.product_id,
         cb.system_quantity,
         cb.counted_quantity,
         (cb.counted_quantity - cb.system_quantity),
         CASE WHEN cb.system_quantity = 0 THEN (CASE WHEN cb.counted_quantity = 0 THEN 0 ELSE 9999 END)
              ELSE ROUND(ABS(cb.counted_quantity - cb.system_quantity) / NULLIF(ABS(cb.system_quantity),0) * 100, 2) END,
         CASE WHEN cb.counted_quantity = cb.system_quantity THEN 'auto_approved'
              WHEN cb.system_quantity = 0 THEN 'pending'
              WHEN ABS(cb.counted_quantity - cb.system_quantity) / NULLIF(ABS(cb.system_quantity),0) * 100 <= v_threshold THEN 'auto_approved'
              ELSE 'pending' END
  FROM combined cb
  ON CONFLICT (session_id, product_id) DO UPDATE SET
    system_quantity = EXCLUDED.system_quantity,
    counted_quantity = EXCLUDED.counted_quantity,
    variance = EXCLUDED.variance,
    variance_pct = EXCLUDED.variance_pct,
    status = CASE WHEN inventory_results.status = 'approved' THEN inventory_results.status ELSE EXCLUDED.status END;

  UPDATE inventory_sessions SET status = 'completed', updated_at = now() WHERE id = p_session AND status = 'active';
  RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION sp_inventory_compute_results(uuid) TO authenticated;

-- Apply approved results as stock_movements adjustments, lock sheets, mark session approved
CREATE OR REPLACE FUNCTION sp_inventory_apply_results(p_session uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_company uuid; v_wh uuid; v_name text; v_user uuid; v_count int := 0;
        rec RECORD;
BEGIN
  SELECT company_id, warehouse_id, name INTO v_company, v_wh, v_name FROM inventory_sessions WHERE id = p_session;
  IF v_company IS NULL THEN RETURN jsonb_build_object('error','session_not_found'); END IF;
  v_user := auth.uid();

  FOR rec IN
    SELECT * FROM inventory_results WHERE session_id = p_session AND status IN ('approved','auto_approved') AND variance <> 0
  LOOP
    INSERT INTO stock_movements (company_id, product_id, warehouse_id, type, quantity, reference, notes, is_active, created_at)
    VALUES (v_company, rec.product_id, v_wh,
            CASE WHEN rec.variance > 0 THEN 'in' ELSE 'out' END,
            ABS(rec.variance),
            'inv_count:' || p_session,
            'Sayım Düzeltmesi — ' || COALESCE(v_name,''),
            true, now());
    v_count := v_count + 1;
  END LOOP;

  UPDATE inventory_sheets SET status = 'locked', updated_at = now() WHERE session_id = p_session;
  UPDATE inventory_sessions SET status = 'approved', approved_by = v_user, approved_at = now(), updated_at = now()
    WHERE id = p_session;

  RETURN jsonb_build_object('success', true, 'adjustments', v_count);
END $$;
GRANT EXECUTE ON FUNCTION sp_inventory_apply_results(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('048_inventory_counting.sql', 'Inventory counting module: sessions/sheets/sheet_items/results + compute + apply RPCs + RLS')
ON CONFLICT (file_name) DO NOTHING;
