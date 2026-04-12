-- ============================================================
-- Migration 019: CHECK constraints on monetary columns and enums
-- Each wrapped in DO block to skip on data violations
-- ============================================================

-- ============================================================
-- STEP 1: Monetary column constraints
-- ============================================================

-- products: cost_price, sale_price >= 0
DO $$ BEGIN
  ALTER TABLE products ADD CONSTRAINT chk_products_cost_price CHECK (cost_price IS NULL OR cost_price >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_products_cost_price: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE products ADD CONSTRAINT chk_products_sale_price CHECK (sale_price IS NULL OR sale_price >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_products_sale_price: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- sales_order_items: quantity > 0, unit_price >= 0, total >= 0
DO $$ BEGIN
  ALTER TABLE sales_order_items ADD CONSTRAINT chk_soi_quantity CHECK (quantity > 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_soi_quantity: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE sales_order_items ADD CONSTRAINT chk_soi_unit_price CHECK (unit_price >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_soi_unit_price: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE sales_order_items ADD CONSTRAINT chk_soi_total CHECK (total >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_soi_total: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- purchase_order_items: same rules
DO $$ BEGIN
  ALTER TABLE purchase_order_items ADD CONSTRAINT chk_poi_quantity CHECK (quantity > 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_poi_quantity: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE purchase_order_items ADD CONSTRAINT chk_poi_unit_price CHECK (unit_price >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_poi_unit_price: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE purchase_order_items ADD CONSTRAINT chk_poi_total CHECK (total >= 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_poi_total: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- payments: amount > 0
DO $$ BEGIN
  ALTER TABLE payments ADD CONSTRAINT chk_payments_amount CHECK (amount > 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_payments_amount: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- cash_transactions: amount != 0
DO $$ BEGIN
  ALTER TABLE cash_transactions ADD CONSTRAINT chk_cash_amount_not_zero CHECK (amount != 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_cash_amount_not_zero: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- bank_transactions: amount != 0
DO $$ BEGIN
  ALTER TABLE bank_transactions ADD CONSTRAINT chk_bank_amount_not_zero CHECK (amount != 0);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_bank_amount_not_zero: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- tax_rates: rate 0-100
DO $$ BEGIN
  ALTER TABLE tax_rates ADD CONSTRAINT chk_tax_rate_range CHECK (rate >= 0 AND rate <= 100);
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_tax_rate_range: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- STEP 2: Status/type enum constraints
-- ============================================================

-- pos_sessions.status
DO $$ BEGIN
  ALTER TABLE pos_sessions ADD CONSTRAINT chk_pos_session_status
    CHECK (status IN ('open', 'closed', 'suspended'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_pos_session_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- shipments.status
DO $$ BEGIN
  ALTER TABLE shipments ADD CONSTRAINT chk_shipment_status
    CHECK (status IN ('draft', 'pending', 'in_transit', 'delivered', 'cancelled', 'returned'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_shipment_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- production_orders.status
DO $$ BEGIN
  ALTER TABLE production_orders ADD CONSTRAINT chk_production_status
    CHECK (status IN ('draft', 'planned', 'in_progress', 'completed', 'cancelled'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_production_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- crm_opportunities.stage (column is "stage" not "status")
DO $$ BEGIN
  ALTER TABLE crm_opportunities ADD CONSTRAINT chk_crm_opportunity_stage
    CHECK (stage IN ('lead', 'proposal', 'negotiation', 'won', 'lost'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_crm_opportunity_stage: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- tasks.status
DO $$ BEGIN
  ALTER TABLE tasks ADD CONSTRAINT chk_task_status
    CHECK (status IN ('open', 'in_progress', 'done', 'cancelled'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_task_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- work_orders.status
DO $$ BEGIN
  ALTER TABLE work_orders ADD CONSTRAINT chk_work_order_status
    CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_work_order_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- leave_requests.status
DO $$ BEGIN
  ALTER TABLE leave_requests ADD CONSTRAINT chk_leave_request_status
    CHECK (status IN ('pending', 'approved', 'rejected'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_leave_request_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- crm_quotes.status
DO $$ BEGIN
  ALTER TABLE crm_quotes ADD CONSTRAINT chk_crm_quote_status
    CHECK (status IN ('draft', 'sent', 'accepted', 'rejected', 'converted'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_crm_quote_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- projects.status
DO $$ BEGIN
  ALTER TABLE projects ADD CONSTRAINT chk_project_status
    CHECK (status IN ('planning', 'in_progress', 'on_hold', 'completed', 'cancelled'));
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'SKIP chk_project_status: existing data violates';
         WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- STEP 3: migrations_log
-- ============================================================

INSERT INTO migrations_log (file_name, notes)
VALUES ('019_check_constraints.sql',
  'Add CHECK constraints on monetary columns (non-negative) and status/type enum fields')
ON CONFLICT (file_name) DO NOTHING;
