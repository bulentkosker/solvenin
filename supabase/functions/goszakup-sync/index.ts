// Goszakup-sync — fetches public-procurement tenders from
// goszakup.gov.kz GraphQL for one company (or all KZ-enabled
// companies in cron mode), upserts them into goszakup_tenders /
// _lots, then runs goszakup_match_tender_to_subscriptions for each
// tender so any matching subscription lights up.
//
// Deploy: supabase functions deploy goszakup-sync (chat-side).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ALLOWED_ORIGINS = ['https://solvenin.com', 'https://www.solvenin.com', 'http://localhost:3000']

function getCorsHeaders(req: Request) {
  const origin = req.headers.get('origin') || ''
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0]
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  }
}

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const sb = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const GOSZAKUP_ENDPOINT = 'https://ows.goszakup.gov.kz/v3/graphql'

// GraphQL field names (Trd_Buy, name_ru, ref_kato_code_id, ...) are based on
// the published Goszakup v3 schema. If first real call returns schema errors,
// adjust the query here — the raw payload is preserved as raw_data so we
// don't lose data while iterating.
const TENDERS_QUERY = `
  query getTenders($from: String!, $to: String!) {
    Trd_Buy(filter: {publish_date: [$from, $to]}, limit: 200) {
      id
      name_ru
      name_kz
      customer_bin
      customer_name_ru
      customer_name_kz
      total_sum
      publish_date
      start_date_app_office
      end_date_app_office
      ref_buy_status_id
      ref_subject_type_id
      ref_kato_code_id
      Lots {
        id
        lot_number
        name_ru
        name_kz
        description_ru
        description_kz
        amount
        count
        total_sum
        delivery_address_ru
        ref_lot_status_id
        ref_kato_code_id
      }
    }
  }
`

interface SyncResult {
  success: boolean
  fetched?: number
  new?: number
  updated?: number
  matches_created?: number
  error?: string
}

async function syncCompany(companyId: string, triggerSource = 'manual'): Promise<SyncResult> {
  // Settings — token + lookback window. Function exits early when the
  // tenant hasn't enabled the integration.
  const { data: settings } = await sb
    .from('goszakup_settings')
    .select('api_token, is_enabled, sync_lookback_days')
    .eq('company_id', companyId)
    .maybeSingle()

  if (!settings || !settings.api_token || !settings.is_enabled) {
    return { success: false, error: 'Settings not configured' }
  }

  // Open a sync log immediately so a crash mid-sync still leaves a
  // breadcrumb the UI can surface.
  const { data: log, error: logErr } = await sb
    .from('goszakup_sync_logs')
    .insert({ company_id: companyId, status: 'running', trigger_source: triggerSource })
    .select('id')
    .single()
  if (logErr || !log) {
    return { success: false, error: `sync_log insert failed: ${logErr?.message || 'unknown'}` }
  }

  const finishLog = async (patch: Record<string, unknown>) => {
    await sb.from('goszakup_sync_logs')
      .update({ ...patch, completed_at: new Date().toISOString() })
      .eq('id', log.id)
  }

  try {
    // Lookback window — Goszakup expects YYYY-MM-DD strings.
    const today = new Date()
    const lookback = settings.sync_lookback_days || 7
    const fromDate = new Date(today.getTime() - lookback * 86400000)
    const fromStr = fromDate.toISOString().split('T')[0]
    const toStr = today.toISOString().split('T')[0]

    // Helper closure so the 429 retry doesn't duplicate the call site.
    const callGoszakup = async () => fetch(GOSZAKUP_ENDPOINT, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${settings.api_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: TENDERS_QUERY, variables: { from: fromStr, to: toStr } }),
    })

    let response = await callGoszakup()

    // 401 → token problem; surface it on the settings row so the UI
    // can show "invalid token" without parsing the log.
    if (response.status === 401) {
      const errMsg = 'Token geçersiz veya süresi dolmuş'
      await sb.from('goszakup_settings').update({
        last_sync_at: new Date().toISOString(),
        last_sync_status: 'auth_failed',
        last_sync_error: errMsg,
      }).eq('company_id', companyId)
      await finishLog({ status: 'auth_failed', error_message: 'Invalid token' })
      return { success: false, error: 'Invalid token' }
    }

    // 429 → one retry after a 5-minute back-off, then give up. Retry
    // is intentionally simple — Goszakup publishes no rate-limit
    // budget and aggressive retries would just compound the problem.
    if (response.status === 429) {
      await new Promise(r => setTimeout(r, 5 * 60 * 1000))
      response = await callGoszakup()
    }

    if (!response.ok) {
      throw new Error(`Goszakup API error: ${response.status} ${response.statusText}`)
    }

    const result = await response.json()
    if (result.errors) {
      throw new Error(`GraphQL errors: ${JSON.stringify(result.errors)}`)
    }

    const tenders: any[] = result.data?.Trd_Buy || []

    // Resolve KATO → region name once per sync; cheap lookup avoids a
    // round-trip per tender.
    const { data: regions } = await sb.from('goszakup_regions').select('code, name_ru')
    const regionMap = new Map<string, string>((regions || []).map((r: any) => [r.code, r.name_ru]))

    let newCount = 0
    let updatedCount = 0
    let totalMatches = 0

    for (const t of tenders) {
      // Region heuristic — KATO codes encode region in the leading two
      // digits. If goszakup ships a richer region field later we can
      // override this from the raw_data without re-syncing.
      const katoStr = t.ref_kato_code_id ? String(t.ref_kato_code_id) : null
      const regionCode = katoStr ? katoStr.substring(0, 2) : null

      const tenderRow = {
        company_id: companyId,
        external_id: String(t.id),
        title_ru: t.name_ru ?? null,
        title_kz: t.name_kz ?? null,
        customer_bin: t.customer_bin ?? null,
        customer_name_ru: t.customer_name_ru ?? null,
        customer_name_kz: t.customer_name_kz ?? null,
        total_sum: t.total_sum ?? null,
        currency: 'KZT',
        publish_date: t.publish_date ?? null,
        start_date: t.start_date_app_office ?? t.start_date ?? null,
        end_date: t.end_date_app_office ?? t.end_date ?? null,
        region_code: regionCode,
        region_name_ru: regionCode ? (regionMap.get(regionCode) ?? null) : null,
        trade_method_code: t.ref_subject_type_id != null ? String(t.ref_subject_type_id) : null,
        status_code: t.ref_buy_status_id != null ? String(t.ref_buy_status_id) : null,
        raw_data: t,
        last_seen_at: new Date().toISOString(),
      }

      const { data: tenderData, error: tenderErr } = await sb
        .from('goszakup_tenders')
        .upsert(tenderRow, { onConflict: 'company_id,external_id' })
        .select('id, fetched_at')
        .single()

      if (tenderErr || !tenderData) {
        console.error('Tender upsert error:', tenderErr)
        continue
      }

      // fetched_at is a server default that fires on INSERT; on a pure
      // UPDATE we keep the original value. The 60s window distinguishes
      // freshly-inserted rows from rows we just re-saw.
      const isNew = Date.now() - new Date(tenderData.fetched_at).getTime() < 60_000
      if (isNew) newCount++
      else updatedCount++

      const lots: any[] = Array.isArray(t.Lots) ? t.Lots : []
      if (lots.length > 0) {
        const lotsRows = lots.map(l => ({
          tender_id: tenderData.id,
          external_id: String(l.id),
          lot_number: l.lot_number ?? null,
          name_ru: l.name_ru ?? null,
          name_kz: l.name_kz ?? null,
          description_ru: l.description_ru ?? null,
          description_kz: l.description_kz ?? null,
          amount: l.amount ?? null,
          count: l.count ?? null,
          total_sum: l.total_sum ?? null,
          delivery_address: l.delivery_address_ru ?? null,
          kato_code: l.ref_kato_code_id != null ? String(l.ref_kato_code_id) : null,
          status_code: l.ref_lot_status_id != null ? String(l.ref_lot_status_id) : null,
          raw_data: l,
        }))
        const { error: lotsErr } = await sb
          .from('goszakup_lots')
          .upsert(lotsRows, { onConflict: 'tender_id,external_id' })
        if (lotsErr) console.error('Lots upsert error:', lotsErr)
      }

      // Match function returns the number of new match rows inserted
      // for this tender — the function itself dedupes against existing
      // (subscription_id, tender_id) pairs.
      const { data: matchCount, error: matchErr } = await sb.rpc(
        'goszakup_match_tender_to_subscriptions',
        { p_tender_id: tenderData.id }
      )
      if (matchErr) console.error('Match RPC error:', matchErr)
      else totalMatches += Number(matchCount) || 0
    }

    // Settings + log — clear last_sync_error on a clean run.
    await sb.from('goszakup_settings').update({
      last_sync_at: new Date().toISOString(),
      last_sync_status: 'success',
      last_synced_count: tenders.length,
      last_sync_error: null,
    }).eq('company_id', companyId)

    await finishLog({
      status: 'success',
      fetched_count: tenders.length,
      new_count: newCount,
      updated_count: updatedCount,
      matches_created: totalMatches,
    })

    return {
      success: true,
      fetched: tenders.length,
      new: newCount,
      updated: updatedCount,
      matches_created: totalMatches,
    }
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e)
    await sb.from('goszakup_settings').update({
      last_sync_at: new Date().toISOString(),
      last_sync_status: 'failed',
      last_sync_error: errMsg,
    }).eq('company_id', companyId)
    await finishLog({ status: 'failed', error_message: errMsg })
    return { success: false, error: errMsg }
  }
}

Deno.serve(async (req) => {
  const corsHeaders = getCorsHeaders(req)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const json = (body: unknown, status = 200) => new Response(
    JSON.stringify(body),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status }
  )

  try {
    const body = await req.json().catch(() => ({}))

    // Cron mode: { all: true } → fan out to every KZ company that has
    // the integration enabled. Returns aggregate counts only.
    if (body.all === true) {
      const { data: rows, error: listErr } = await sb
        .from('goszakup_settings')
        .select('company_id, companies!inner(country_code)')
        .eq('is_enabled', true)
        .not('api_token', 'is', null)
        .eq('companies.country_code', 'KZ')

      if (listErr) return json({ error: listErr.message }, 500)

      const ids = (rows || []).map((r: any) => r.company_id)
      const results = await Promise.allSettled(ids.map(id => syncCompany(id, 'cron')))

      const success = results.filter(r => r.status === 'fulfilled' && (r.value as SyncResult).success).length
      const failed = results.length - success

      return json({ total: results.length, success, failed })
    }

    if (!body.company_id) {
      return json({ error: 'company_id required' }, 400)
    }

    const result = await syncCompany(body.company_id, 'manual')
    return json(result, result.success ? 200 : 500)
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e)
    return json({ error: errMsg }, 500)
  }
})
