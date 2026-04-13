-- ============================================================
-- Migration 023: Fix RLS policies — EXISTS → get_my_company_ids()
-- Replace unsafe company_users subquery pattern on 42+ tables
-- ============================================================

-- ============================
-- STANDARD: company_id direct
-- ============================

-- Tables WITH deleted_at → SELECT adds AND deleted_at IS NULL
-- Tables WITHOUT deleted_at → plain USING

-- Helper: drops all policies on a table, safer than naming each
DO $$
DECLARE
  _tbl text;
  _pol record;
BEGIN
  FOR _tbl IN
    SELECT unnest(ARRAY[
      'attendance','bom','departments','drivers','employees','equipment',
      'exchange_rates','failure_records','leave_requests','leave_types',
      'maintenance_history','maintenance_plans','payments','payroll',
      'positions','production_orders','products',
      'service_providers','stock_levels','stock_movements','tax_rates',
      'tax_regimes','user_permissions','vehicles','warehouses','work_orders',
      'company_modules','chart_of_accounts'
    ])
  LOOP
    -- Drop all existing policies on this table
    FOR _pol IN
      SELECT polname FROM pg_policy WHERE polrelid = _tbl::regclass
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', _pol.polname, _tbl);
    END LOOP;
  END LOOP;
END $$;

-- Tables with company_id + deleted_at → SELECT filters deleted
-- attendance (no deleted_at)
CREATE POLICY att_select ON attendance FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY att_modify ON attendance FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- bom (no deleted_at)
CREATE POLICY bom_select ON bom FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY bom_modify ON bom FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- departments (no deleted_at)
CREATE POLICY dep_select ON departments FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY dep_modify ON departments FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- drivers (deleted_at)
CREATE POLICY drv_select ON drivers FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY drv_modify ON drivers FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- employees (deleted_at)
CREATE POLICY emp_select ON employees FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY emp_modify ON employees FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- equipment (deleted_at)
CREATE POLICY eq_select ON equipment FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY eq_modify ON equipment FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- exchange_rates (no deleted_at)
CREATE POLICY exr_select ON exchange_rates FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY exr_modify ON exchange_rates FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- failure_records (no deleted_at)
CREATE POLICY fr_select ON failure_records FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY fr_modify ON failure_records FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- leave_requests (no deleted_at)
CREATE POLICY lr_select ON leave_requests FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY lr_modify ON leave_requests FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- leave_types (no deleted_at)
CREATE POLICY lt_select ON leave_types FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY lt_modify ON leave_types FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- maintenance_history (no deleted_at)
CREATE POLICY mh_select ON maintenance_history FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY mh_modify ON maintenance_history FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- maintenance_plans (no deleted_at)
CREATE POLICY mp_select ON maintenance_plans FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY mp_modify ON maintenance_plans FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- payments (deleted_at)
CREATE POLICY pay_select ON payments FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY pay_modify ON payments FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- payroll (no deleted_at)
CREATE POLICY pr_select ON payroll FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY pr_modify ON payroll FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- positions (no deleted_at)
CREATE POLICY pos_select ON positions FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY pos_modify ON positions FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- production_entries (via production_order_id, no company_id)
-- handled below in nested section

-- production_orders (deleted_at)
CREATE POLICY po_select ON production_orders FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY po_modify ON production_orders FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- products (deleted_at)
CREATE POLICY prod_select ON products FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY prod_modify ON products FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- service_providers (deleted_at)
CREATE POLICY sp_select ON service_providers FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY sp_modify ON service_providers FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- stock_levels (no deleted_at)
CREATE POLICY sl_select ON stock_levels FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY sl_modify ON stock_levels FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- stock_movements (deleted_at)
CREATE POLICY sm_select ON stock_movements FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY sm_modify ON stock_movements FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- tax_rates (deleted_at)
CREATE POLICY tr_select ON tax_rates FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY tr_modify ON tax_rates FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- tax_regimes (no deleted_at, has company_id)
CREATE POLICY txr_select ON tax_regimes FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY txr_modify ON tax_regimes FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- user_permissions (no deleted_at)
CREATE POLICY up_select ON user_permissions FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY up_modify ON user_permissions FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- vehicles (deleted_at)
CREATE POLICY veh_select ON vehicles FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY veh_modify ON vehicles FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- warehouses (deleted_at)
CREATE POLICY wh_select ON warehouses FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY wh_modify ON warehouses FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- work_orders (deleted_at)
CREATE POLICY wo_select ON work_orders FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY wo_modify ON work_orders FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- company_modules (no deleted_at, is_active means "enabled" not deleted)
CREATE POLICY cm_select ON company_modules FOR SELECT USING (company_id = ANY(get_my_company_ids()));
CREATE POLICY cm_modify ON company_modules FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- chart_of_accounts (deleted_at)
CREATE POLICY coa_select ON chart_of_accounts FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY coa_modify ON chart_of_accounts FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- ============================
-- SPECIAL: companies table (id not company_id)
-- ============================
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'companies'::regclass AND polname NOT IN ('companies_insert')
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON companies', _pol.polname); END LOOP;
END $$;

CREATE POLICY companies_visible ON companies
  FOR SELECT USING (id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY companies_update ON companies
  FOR UPDATE USING (id = ANY(get_my_company_ids())) WITH CHECK (id = ANY(get_my_company_ids()));
CREATE POLICY companies_delete ON companies
  FOR DELETE USING (id = ANY(get_my_company_ids()));

-- ============================
-- SPECIAL: order items (via order_id → parent table)
-- ============================
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'sales_order_items'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON sales_order_items', _pol.polname); END LOOP;
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'purchase_order_items'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON purchase_order_items', _pol.polname); END LOOP;
END $$;

-- sales_orders (deleted_at)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'sales_orders'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON sales_orders', _pol.polname); END LOOP;
END $$;
CREATE POLICY so_select ON sales_orders FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY so_modify ON sales_orders FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- purchase_orders (deleted_at)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'purchase_orders'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON purchase_orders', _pol.polname); END LOOP;
END $$;
CREATE POLICY puo_select ON purchase_orders FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY puo_modify ON purchase_orders FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

CREATE POLICY soi_all ON sales_order_items FOR ALL
  USING (order_id IN (SELECT id FROM sales_orders WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (order_id IN (SELECT id FROM sales_orders WHERE company_id = ANY(get_my_company_ids())));

CREATE POLICY poi_all ON purchase_order_items FOR ALL
  USING (order_id IN (SELECT id FROM purchase_orders WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (order_id IN (SELECT id FROM purchase_orders WHERE company_id = ANY(get_my_company_ids())));

-- ============================
-- SPECIAL: project-linked tables (via project_id)
-- ============================
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid IN ('projects'::regclass,'milestones'::regclass,'tasks'::regclass,'project_expenses'::regclass,'time_logs'::regclass,'shipments'::regclass,'shipment_items'::regclass)
  LOOP
    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON %s', _pol.polname,
        (SELECT relname FROM pg_class WHERE oid = (SELECT polrelid FROM pg_policy WHERE polname = _pol.polname LIMIT 1)));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

-- projects (deleted_at, has company_id)
CREATE POLICY proj_select ON projects FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY proj_modify ON projects FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- milestones (via project_id, no company_id)
CREATE POLICY ms_all ON milestones FOR ALL
  USING (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())));

-- tasks (via project_id, has deleted_at)
CREATE POLICY tsk_select ON tasks FOR ALL
  USING (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())));

-- project_expenses (via project_id, no company_id)
CREATE POLICY pex_all ON project_expenses FOR ALL
  USING (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())));

-- time_logs (via project_id)
CREATE POLICY tl_all ON time_logs FOR ALL
  USING (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (project_id IN (SELECT id FROM projects WHERE company_id = ANY(get_my_company_ids())));

-- shipments (deleted_at, has company_id)
CREATE POLICY ship_select ON shipments FOR SELECT USING (company_id = ANY(get_my_company_ids()) AND deleted_at IS NULL);
CREATE POLICY ship_modify ON shipments FOR ALL USING (company_id = ANY(get_my_company_ids())) WITH CHECK (company_id = ANY(get_my_company_ids()));

-- shipment_items (via shipment_id)
CREATE POLICY si_all ON shipment_items FOR ALL
  USING (shipment_id IN (SELECT id FROM shipments WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (shipment_id IN (SELECT id FROM shipments WHERE company_id = ANY(get_my_company_ids())));

-- ============================
-- SPECIAL: nested tables (via parent FK)
-- ============================

-- bom_inputs/bom_outputs (via bom_id)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid IN ('bom_inputs'::regclass,'bom_outputs'::regclass)
  LOOP
    BEGIN EXECUTE format('DROP POLICY IF EXISTS %I ON bom_inputs', _pol.polname); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE format('DROP POLICY IF EXISTS %I ON bom_outputs', _pol.polname); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
END $$;

CREATE POLICY bi_all ON bom_inputs FOR ALL
  USING (bom_id IN (SELECT id FROM bom WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (bom_id IN (SELECT id FROM bom WHERE company_id = ANY(get_my_company_ids())));

CREATE POLICY bo_all ON bom_outputs FOR ALL
  USING (bom_id IN (SELECT id FROM bom WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (bom_id IN (SELECT id FROM bom WHERE company_id = ANY(get_my_company_ids())));

-- payroll_items (via payroll_id)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'payroll_items'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON payroll_items', _pol.polname); END LOOP;
END $$;

CREATE POLICY pi_all ON payroll_items FOR ALL
  USING (payroll_id IN (SELECT id FROM payroll WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (payroll_id IN (SELECT id FROM payroll WHERE company_id = ANY(get_my_company_ids())));

-- work_order_parts (via work_order_id)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'work_order_parts'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON work_order_parts', _pol.polname); END LOOP;
END $$;

-- production_entries (via production_order_id)
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'production_entries'::regclass
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON production_entries', _pol.polname); END LOOP;
END $$;

CREATE POLICY pe_all ON production_entries FOR ALL
  USING (production_order_id IN (SELECT id FROM production_orders WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (production_order_id IN (SELECT id FROM production_orders WHERE company_id = ANY(get_my_company_ids())));

CREATE POLICY wop_all ON work_order_parts FOR ALL
  USING (work_order_id IN (SELECT id FROM work_orders WHERE company_id = ANY(get_my_company_ids())))
  WITH CHECK (work_order_id IN (SELECT id FROM work_orders WHERE company_id = ANY(get_my_company_ids())));

-- ============================
-- SPECIAL: profiles
-- ============================
DO $$
DECLARE _pol record;
BEGIN
  FOR _pol IN SELECT polname FROM pg_policy WHERE polrelid = 'profiles'::regclass AND polname LIKE '%company%'
  LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON profiles', _pol.polname); END LOOP;
END $$;

-- Keep existing direct auth policies, replace company_users subquery one
CREATE POLICY profiles_company ON profiles FOR SELECT
  USING (
    id = auth.uid()
    OR id IN (
      SELECT cu.user_id FROM company_users cu
      WHERE cu.company_id = ANY(get_my_company_ids())
    )
  );

-- ============================
-- REFRESH SCHEMA CACHE
-- ============================
NOTIFY pgrst, 'reload schema';

INSERT INTO migrations_log (file_name, notes)
VALUES ('023_fix_rls_policies.sql',
  'Replace unsafe EXISTS company_users pattern with safe get_my_company_ids() on 42+ tables. Added deleted_at IS NULL to SELECT policies.')
ON CONFLICT (file_name) DO NOTHING;
