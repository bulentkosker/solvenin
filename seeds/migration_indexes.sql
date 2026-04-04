-- Solvenin Database Index Migration
-- Created: 2026-04-04
-- 50 new indexes for query performance

-- payments
CREATE INDEX IF NOT EXISTS idx_payments_company ON payments(company_id);
CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(company_id, paid_at DESC);

-- sales_order_items
CREATE INDEX IF NOT EXISTS idx_sales_order_items_order ON sales_order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_sales_order_items_product ON sales_order_items(product_id);

-- purchase_order_items
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_order ON purchase_order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_product ON purchase_order_items(product_id);

-- employees
CREATE INDEX IF NOT EXISTS idx_employees_company ON employees(company_id);
CREATE INDEX IF NOT EXISTS idx_employees_department ON employees(company_id, department_id);

-- attendance
CREATE INDEX IF NOT EXISTS idx_attendance_company ON attendance(company_id);
CREATE INDEX IF NOT EXISTS idx_attendance_employee ON attendance(company_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(company_id, date DESC);

-- leave_requests
CREATE INDEX IF NOT EXISTS idx_leave_requests_company ON leave_requests(company_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(company_id, employee_id);

-- departments
CREATE INDEX IF NOT EXISTS idx_departments_company ON departments(company_id);

-- positions
CREATE INDEX IF NOT EXISTS idx_positions_company ON positions(company_id);

-- shipments
CREATE INDEX IF NOT EXISTS idx_shipments_company ON shipments(company_id);
CREATE INDEX IF NOT EXISTS idx_shipments_status ON shipments(company_id, status);
CREATE INDEX IF NOT EXISTS idx_shipments_date ON shipments(company_id, created_at DESC);

-- vehicles
CREATE INDEX IF NOT EXISTS idx_vehicles_company ON vehicles(company_id);

-- drivers
CREATE INDEX IF NOT EXISTS idx_drivers_company ON drivers(company_id);

-- work_orders
CREATE INDEX IF NOT EXISTS idx_work_orders_company ON work_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_work_orders_status ON work_orders(company_id, status);
CREATE INDEX IF NOT EXISTS idx_work_orders_equipment ON work_orders(company_id, equipment_id);

-- equipment
CREATE INDEX IF NOT EXISTS idx_equipment_company ON equipment(company_id);
CREATE INDEX IF NOT EXISTS idx_equipment_category ON equipment(company_id, category_id);

-- maintenance_plans
CREATE INDEX IF NOT EXISTS idx_maintenance_plans_company ON maintenance_plans(company_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_plans_equipment ON maintenance_plans(equipment_id);

-- tasks
CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks(project_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks(assignee_id);

-- projects
CREATE INDEX IF NOT EXISTS idx_projects_company ON projects(company_id);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(company_id, status);

-- time_logs
CREATE INDEX IF NOT EXISTS idx_time_logs_task ON time_logs(task_id);
CREATE INDEX IF NOT EXISTS idx_time_logs_user ON time_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_time_logs_project ON time_logs(project_id);

-- production_orders
CREATE INDEX IF NOT EXISTS idx_production_orders_company ON production_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_production_orders_status ON production_orders(company_id, status);

-- pos_sessions
CREATE INDEX IF NOT EXISTS idx_pos_sessions_company ON pos_sessions(company_id);
CREATE INDEX IF NOT EXISTS idx_pos_sessions_register ON pos_sessions(cash_register_id);
CREATE INDEX IF NOT EXISTS idx_pos_sessions_cashier ON pos_sessions(cashier_id);

-- pos_cash_transfers
CREATE INDEX IF NOT EXISTS idx_pos_cash_transfers_company ON pos_cash_transfers(company_id);
CREATE INDEX IF NOT EXISTS idx_pos_cash_transfers_session ON pos_cash_transfers(session_id);

-- stock_movements (additional)
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_date ON stock_movements(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_warehouse ON stock_movements(company_id, warehouse_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_invoice ON stock_movements(invoice_id) WHERE invoice_id IS NOT NULL;

-- stock_levels
CREATE INDEX IF NOT EXISTS idx_stock_levels_company ON stock_levels(company_id);

-- payroll
CREATE INDEX IF NOT EXISTS idx_payroll_company ON payroll(company_id);
CREATE INDEX IF NOT EXISTS idx_payroll_employee ON payroll(company_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_payroll_period ON payroll(company_id, period_year DESC, period_month DESC);
