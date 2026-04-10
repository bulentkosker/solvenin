-- 015_hierarchical_category_vat.sql
-- Updates get_product_tax_rate to walk the category parent chain:
--   product category → parent category → grandparent → ... → company default → 0
-- Previously only checked the product's immediate category.

CREATE OR REPLACE FUNCTION get_product_tax_rate(
  p_product_id uuid,
  p_company_id uuid
) RETURNS decimal
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product  products%ROWTYPE;
  v_cat_id   uuid;
  v_cat      categories%ROWTYPE;
  v_tax_rate decimal := 0;
  v_depth    int := 0;
BEGIN
  SELECT * INTO v_product
  FROM products
  WHERE id = p_product_id AND company_id = p_company_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  CASE COALESCE(v_product.tax_source, 'category')
    WHEN 'manual' THEN
      IF v_product.tax_rate_id IS NOT NULL THEN
        SELECT rate INTO v_tax_rate FROM tax_rates WHERE id = v_product.tax_rate_id;
      ELSE
        v_tax_rate := COALESCE(v_product.tax_rate_override, 0);
      END IF;

    WHEN 'fixed' THEN
      SELECT COALESCE(tr.rate, 0) INTO v_tax_rate
      FROM companies c
      LEFT JOIN tax_rates tr ON tr.id = c.default_tax_rate_id
      WHERE c.id = p_company_id;

    ELSE -- 'category': walk up the category hierarchy
      v_cat_id := v_product.category_id;

      WHILE v_cat_id IS NOT NULL AND v_depth < 10 LOOP
        SELECT * INTO v_cat FROM categories WHERE id = v_cat_id;
        IF NOT FOUND THEN EXIT; END IF;

        IF v_cat.tax_rate_id IS NOT NULL THEN
          SELECT rate INTO v_tax_rate FROM tax_rates WHERE id = v_cat.tax_rate_id;
          IF v_tax_rate IS NOT NULL AND v_tax_rate > 0 THEN
            RETURN v_tax_rate;
          END IF;
        END IF;

        IF v_cat.tax_rate_override IS NOT NULL THEN
          RETURN v_cat.tax_rate_override;
        END IF;

        v_cat_id := v_cat.parent_id;
        v_depth := v_depth + 1;
      END LOOP;

      -- Fallback to company default
      SELECT COALESCE(tr.rate, 0) INTO v_tax_rate
      FROM companies c
      LEFT JOIN tax_rates tr ON tr.id = c.default_tax_rate_id
      WHERE c.id = p_company_id;
  END CASE;

  RETURN COALESCE(v_tax_rate, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_product_tax_rate(uuid, uuid) TO authenticated, anon;

INSERT INTO migrations_log (file_name, notes)
VALUES ('015_hierarchical_category_vat.sql', 'get_product_tax_rate walks category parent chain for VAT inheritance')
ON CONFLICT (file_name) DO NOTHING;
