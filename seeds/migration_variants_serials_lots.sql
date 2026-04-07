-- ===== VARIANTS / SERIAL NUMBERS / LOTS TRACKING =====
-- 2026-04-07

-- Product attributes (Color, Size, Capacity ...)
CREATE TABLE IF NOT EXISTS product_attributes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  name varchar(100) NOT NULL,
  display_type varchar(20) DEFAULT 'select', -- select, color, button
  created_at timestamptz DEFAULT now()
);

-- Attribute values (Red, S, 256GB ...)
CREATE TABLE IF NOT EXISTS product_attribute_values (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  attribute_id uuid REFERENCES product_attributes(id) ON DELETE CASCADE,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  name varchar(100) NOT NULL,
  color_code varchar(10),
  sequence int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- Product variants
CREATE TABLE IF NOT EXISTS product_variants (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  parent_product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  name varchar(255),
  sku varchar(100),
  barcode varchar(100),
  price_extra decimal(18,2) DEFAULT 0,
  quantity decimal(18,3) DEFAULT 0,
  min_stock decimal(18,3) DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- Variant ↔ attribute value link
CREATE TABLE IF NOT EXISTS product_variant_attributes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  variant_id uuid REFERENCES product_variants(id) ON DELETE CASCADE,
  attribute_id uuid REFERENCES product_attributes(id),
  value_id uuid REFERENCES product_attribute_values(id)
);

-- Which attributes a product uses (parent definition lines)
CREATE TABLE IF NOT EXISTS product_attribute_lines (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  attribute_id uuid REFERENCES product_attributes(id),
  value_ids uuid[]
);

-- Serial numbers
CREATE TABLE IF NOT EXISTS serial_numbers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  variant_id uuid REFERENCES product_variants(id),
  serial_number varchar(100) NOT NULL,
  status varchar(20) DEFAULT 'in_stock', -- in_stock, sold, returned, defective, scrapped
  purchase_order_id uuid REFERENCES purchase_orders(id),
  purchase_order_item_id uuid,
  sales_order_id uuid REFERENCES sales_orders(id),
  sales_order_item_id uuid,
  warranty_expires_at date,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, serial_number)
);

-- Lots / batches (food, pharma)
CREATE TABLE IF NOT EXISTS product_lots (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  variant_id uuid REFERENCES product_variants(id),
  lot_number varchar(100) NOT NULL,
  quantity decimal(18,3) DEFAULT 0,
  expiry_date date,
  manufacture_date date,
  notes text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, product_id, lot_number)
);

-- Add tracking_type to products
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS tracking_type varchar(20) DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS has_variants boolean DEFAULT false;

-- Add variant/serial/lot refs to stock_movements
ALTER TABLE stock_movements
  ADD COLUMN IF NOT EXISTS serial_number_id uuid REFERENCES serial_numbers(id),
  ADD COLUMN IF NOT EXISTS lot_id uuid REFERENCES product_lots(id),
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES product_variants(id);

-- Add to sales_order_items
ALTER TABLE sales_order_items
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES product_variants(id),
  ADD COLUMN IF NOT EXISTS serial_number_ids uuid[],
  ADD COLUMN IF NOT EXISTS lot_id uuid REFERENCES product_lots(id);

-- Add to purchase_order_items
ALTER TABLE purchase_order_items
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES product_variants(id),
  ADD COLUMN IF NOT EXISTS lot_id uuid REFERENCES product_lots(id);

-- RLS
ALTER TABLE product_attributes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_attributes_policy ON product_attributes;
CREATE POLICY product_attributes_policy ON product_attributes
  FOR ALL USING (company_id = ANY(get_my_company_ids()));

ALTER TABLE product_attribute_values ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_attribute_values_policy ON product_attribute_values;
CREATE POLICY product_attribute_values_policy ON product_attribute_values
  FOR ALL USING (company_id = ANY(get_my_company_ids()));

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_variants_policy ON product_variants;
CREATE POLICY product_variants_policy ON product_variants
  FOR ALL USING (company_id = ANY(get_my_company_ids()));

ALTER TABLE product_variant_attributes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_variant_attributes_policy ON product_variant_attributes;
CREATE POLICY product_variant_attributes_policy ON product_variant_attributes
  FOR ALL USING (
    variant_id IN (
      SELECT id FROM product_variants
      WHERE company_id = ANY(get_my_company_ids())
    )
  );

ALTER TABLE product_attribute_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_attribute_lines_policy ON product_attribute_lines;
CREATE POLICY product_attribute_lines_policy ON product_attribute_lines
  FOR ALL USING (
    product_id IN (
      SELECT id FROM products
      WHERE company_id = ANY(get_my_company_ids())
    )
  );

ALTER TABLE serial_numbers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS serial_numbers_policy ON serial_numbers;
CREATE POLICY serial_numbers_policy ON serial_numbers
  FOR ALL USING (company_id = ANY(get_my_company_ids()));

ALTER TABLE product_lots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_lots_policy ON product_lots;
CREATE POLICY product_lots_policy ON product_lots
  FOR ALL USING (company_id = ANY(get_my_company_ids()));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_product_variants_parent
  ON product_variants(company_id, parent_product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_barcode
  ON product_variants(company_id, barcode);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_company
  ON serial_numbers(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_status
  ON serial_numbers(company_id, status);
CREATE INDEX IF NOT EXISTS idx_serial_numbers_sn
  ON serial_numbers(company_id, serial_number);
CREATE INDEX IF NOT EXISTS idx_product_lots_company
  ON product_lots(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_product_lots_expiry
  ON product_lots(company_id, expiry_date);
CREATE INDEX IF NOT EXISTS idx_product_attribute_values_attribute
  ON product_attribute_values(attribute_id);
CREATE INDEX IF NOT EXISTS idx_product_variant_attributes_variant
  ON product_variant_attributes(variant_id);
