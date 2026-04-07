-- ===== COMPANY LOGO =====
-- 2026-04-07
-- Stores company logo as a base64 data URL directly in companies.logo_url
-- (text column). Avoids Supabase Storage RLS complications since the
-- exec_sql role can't create policies on storage.objects, and lets the
-- logo load instantly with the company row, no extra HTTP request.
-- Client downsizes to 256x256 PNG before saving (typical 30-80KB).

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS logo_url text;

-- Service-panel companies listing also exposes logo_url for thumbnails
CREATE OR REPLACE FUNCTION sp_companies() RETURNS json LANGUAGE sql SECURITY DEFINER AS $BODY$
SELECT COALESCE(json_agg(row_to_json(c) ORDER BY c.created_at DESC), '[]'::json) FROM (
  SELECT c.id, c.name, c.country_code, c.plan, c.created_at, c.is_frozen, c.freeze_reason, c.logo_url,
    (SELECT COUNT(*) FROM company_users cu WHERE cu.company_id = c.id) as user_count,
    (SELECT COUNT(*) FROM sales_orders so WHERE so.company_id = c.id AND so.status IN ('invoiced','paid','overdue') AND so.is_active=true) as invoice_count,
    (SELECT COUNT(*) FROM stock_movements sm WHERE sm.company_id = c.id AND sm.is_active=true) as stock_count,
    (SELECT spu.name FROM service_panel_users spu WHERE spu.id = c.partner_id) as partner_name
  FROM companies c
) c;
$BODY$;
