import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_MODEL = 'claude-sonnet-4-20250514'

// ===== TOOL DEFINITIONS =====
const TOOLS = [
  {
    name: 'get_sales_summary',
    description: 'Get sales summary for a period: total revenue, order count, paid amount, pending amount.',
    input_schema: {
      type: 'object',
      properties: {
        period: { type: 'string', enum: ['today','this_week','this_month','last_month','this_year'] }
      },
      required: ['period']
    }
  },
  {
    name: 'get_top_products',
    description: 'Get top selling products by revenue for a period.',
    input_schema: {
      type: 'object',
      properties: {
        period: { type: 'string', enum: ['today','this_week','this_month','this_year'] },
        limit: { type: 'number', description: 'How many products, default 5' }
      },
      required: ['period']
    }
  },
  {
    name: 'get_pending_payments',
    description: 'List unpaid invoices. type=receivable for customer-owed, payable for supplier-owed, all for both.',
    input_schema: {
      type: 'object',
      properties: { type: { type: 'string', enum: ['receivable','payable','all'] } },
      required: ['type']
    }
  },
  {
    name: 'get_stock_status',
    description: 'Stock levels. filter=low (below min_stock), out (zero), all (everything). product_name filters by name.',
    input_schema: {
      type: 'object',
      properties: {
        filter: { type: 'string', enum: ['low','out','all'] },
        product_name: { type: 'string', description: 'Optional product name search (partial)' }
      },
      required: ['filter']
    }
  },
  {
    name: 'get_contact_balance',
    description: 'Get balance for a specific customer or supplier (search by name).',
    input_schema: {
      type: 'object',
      properties: { contact_name: { type: 'string' } },
      required: ['contact_name']
    }
  },
  {
    name: 'get_cash_bank_balances',
    description: 'Current cash register and bank account balances for the company.',
    input_schema: { type: 'object', properties: {} }
  },
  {
    name: 'get_recent_transactions',
    description: 'Recent sales / purchase orders. type=sales, purchases, or all.',
    input_schema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['sales','purchases','all'] },
        limit: { type: 'number' }
      },
      required: ['type']
    }
  }
]

// ===== HELPERS =====
function periodRange(period: string){
  const n = new Date()
  const todayStr = n.toISOString().slice(0,10)
  switch(period){
    case 'today':      return { start: todayStr+'T00:00:00', end: todayStr+'T23:59:59' }
    case 'this_week': {
      const dow = (n.getDay()+6)%7
      const start = new Date(n.getFullYear(), n.getMonth(), n.getDate()-dow).toISOString()
      return { start, end: new Date().toISOString() }
    }
    case 'this_month': return { start: new Date(n.getFullYear(), n.getMonth(), 1).toISOString(), end: new Date().toISOString() }
    case 'last_month': {
      const s = new Date(n.getFullYear(), n.getMonth()-1, 1).toISOString()
      const e = new Date(n.getFullYear(), n.getMonth(), 1).toISOString()
      return { start: s, end: e }
    }
    case 'this_year':  return { start: new Date(n.getFullYear(), 0, 1).toISOString(), end: new Date().toISOString() }
    default:           return { start: new Date(n.getFullYear(), n.getMonth(), 1).toISOString(), end: new Date().toISOString() }
  }
}

// ===== TOOL EXECUTION =====
async function executeTool(name: string, input: any, sb: any, companyId: string){
  if (!companyId) return { error: 'company_id missing' }

  switch(name){
    case 'get_sales_summary': {
      const { start, end } = periodRange(input.period)
      const { data: orders } = await sb.from('sales_orders')
        .select('id, total, status')
        .eq('company_id', companyId).eq('is_active', true)
        .in('status', ['invoiced','paid','overdue'])
        .gte('issue_date', start.slice(0,10)).lte('issue_date', end.slice(0,10))
      const total = (orders||[]).reduce((s:number,o:any) => s + parseFloat(o.total||0), 0)
      const orderIds = (orders||[]).map((o:any) => o.id)
      let paid = 0
      if (orderIds.length){
        const { data: pays } = await sb.from('payments').select('amount').in('order_id', orderIds)
        paid = (pays||[]).reduce((s:number,p:any) => s + parseFloat(p.amount||0), 0)
      }
      return {
        period: input.period,
        total_revenue: total,
        order_count: (orders||[]).length,
        paid_amount: paid,
        pending_amount: Math.max(0, total - paid)
      }
    }

    case 'get_top_products': {
      const { start, end } = periodRange(input.period)
      const limit = input.limit || 5
      const { data: orders } = await sb.from('sales_orders')
        .select('id').eq('company_id', companyId).eq('is_active', true)
        .gte('issue_date', start.slice(0,10)).lte('issue_date', end.slice(0,10))
      const oids = (orders||[]).map((o:any) => o.id)
      if (!oids.length) return { products: [], period: input.period }
      const { data: items } = await sb.from('sales_order_items')
        .select('product_id, quantity, total, products(name)').in('order_id', oids)
      const grouped: any = {}
      ;(items||[]).forEach((it:any) => {
        if (!it.product_id) return
        const id = it.product_id
        if (!grouped[id]) grouped[id] = { name: it.products?.name || '—', total: 0, quantity: 0 }
        grouped[id].total    += parseFloat(it.total||0)
        grouped[id].quantity += parseFloat(it.quantity||0)
      })
      const sorted = Object.values(grouped).sort((a:any,b:any) => b.total - a.total).slice(0, limit)
      return { products: sorted, period: input.period }
    }

    case 'get_pending_payments': {
      const t = input.type
      const out: any[] = []
      if (t === 'receivable' || t === 'all'){
        const { data: orders } = await sb.from('sales_orders')
          .select('id, order_number, total, contacts(name)')
          .eq('company_id', companyId).eq('is_active', true)
          .in('status', ['invoiced','overdue']).order('issue_date', { ascending: false }).limit(20)
        const ids = (orders||[]).map((o:any) => o.id)
        const payMap: any = {}
        if (ids.length){
          const { data: pays } = await sb.from('payments').select('order_id, amount').in('order_id', ids)
          ;(pays||[]).forEach((p:any) => payMap[p.order_id] = (payMap[p.order_id]||0) + parseFloat(p.amount||0))
        }
        ;(orders||[]).forEach((o:any) => {
          const pending = parseFloat(o.total||0) - (payMap[o.id]||0)
          if (pending > 0) out.push({ type:'receivable', reference: o.order_number, contact: o.contacts?.name, pending_amount: pending })
        })
      }
      if (t === 'payable' || t === 'all'){
        const { data: orders } = await sb.from('purchase_orders')
          .select('id, order_number, total, contacts(name)')
          .eq('company_id', companyId).eq('is_active', true)
          .in('status', ['invoiced','overdue']).order('issue_date', { ascending: false }).limit(20)
        const ids = (orders||[]).map((o:any) => o.id)
        const payMap: any = {}
        if (ids.length){
          const { data: pays } = await sb.from('payments').select('purchase_order_id, amount').in('purchase_order_id', ids)
          ;(pays||[]).forEach((p:any) => payMap[p.purchase_order_id] = (payMap[p.purchase_order_id]||0) + parseFloat(p.amount||0))
        }
        ;(orders||[]).forEach((o:any) => {
          const pending = parseFloat(o.total||0) - (payMap[o.id]||0)
          if (pending > 0) out.push({ type:'payable', reference: o.order_number, contact: o.contacts?.name, pending_amount: pending })
        })
      }
      return { pending_payments: out }
    }

    case 'get_stock_status': {
      let q = sb.from('products').select('name, sku, quantity, min_stock, unit, categories(name)')
        .eq('company_id', companyId).eq('is_active', true).limit(30)
      if (input.product_name) q = q.ilike('name', `%${input.product_name}%`)
      const { data } = await q
      let items = data || []
      if (!input.product_name){
        if (input.filter === 'low')      items = items.filter((p:any) => parseFloat(p.min_stock||0) > 0 && parseFloat(p.quantity||0) <= parseFloat(p.min_stock||0) && parseFloat(p.quantity||0) > 0)
        else if (input.filter === 'out') items = items.filter((p:any) => parseFloat(p.quantity||0) <= 0)
      }
      return { products: items.map((p:any) => ({
        name: p.name, sku: p.sku, category: p.categories?.name,
        quantity: parseFloat(p.quantity||0), min_stock: parseFloat(p.min_stock||0), unit: p.unit
      })), filter: input.filter }
    }

    case 'get_contact_balance': {
      const { data: contacts } = await sb.from('contacts')
        .select('id, name, is_customer, is_supplier').eq('company_id', companyId)
        .ilike('name', `%${input.contact_name}%`).limit(1)
      if (!contacts || !contacts.length) return { error: 'Cari bulunamadı: ' + input.contact_name }
      const c = contacts[0]
      let salesTotal = 0, purchTotal = 0, salesPaid = 0, purchPaid = 0
      if (c.is_customer){
        const { data: so } = await sb.from('sales_orders').select('id, total').eq('company_id', companyId)
          .eq('customer_id', c.id).eq('is_active', true).in('status', ['invoiced','paid','overdue'])
        salesTotal = (so||[]).reduce((s:number,o:any) => s + parseFloat(o.total||0), 0)
        const ids = (so||[]).map((o:any) => o.id)
        if (ids.length){
          const { data: pays } = await sb.from('payments').select('amount').in('order_id', ids)
          salesPaid = (pays||[]).reduce((s:number,p:any) => s + parseFloat(p.amount||0), 0)
        }
      }
      if (c.is_supplier){
        const { data: po } = await sb.from('purchase_orders').select('id, total').eq('company_id', companyId)
          .eq('supplier_id', c.id).eq('is_active', true).in('status', ['invoiced','paid','overdue'])
        purchTotal = (po||[]).reduce((s:number,o:any) => s + parseFloat(o.total||0), 0)
        const ids = (po||[]).map((o:any) => o.id)
        if (ids.length){
          const { data: pays } = await sb.from('payments').select('amount').in('purchase_order_id', ids)
          purchPaid = (pays||[]).reduce((s:number,p:any) => s + parseFloat(p.amount||0), 0)
        }
      }
      const receivable = Math.max(0, salesTotal - salesPaid)
      const payable    = Math.max(0, purchTotal - purchPaid)
      return {
        contact_name: c.name,
        kind: c.is_customer && c.is_supplier ? 'both' : (c.is_customer ? 'customer' : 'supplier'),
        sales_total: salesTotal, sales_paid: salesPaid, receivable,
        purchase_total: purchTotal, purchase_paid: purchPaid, payable,
        net_balance: receivable - payable
      }
    }

    case 'get_cash_bank_balances': {
      const [cash, bank] = await Promise.all([
        sb.from('cash_registers').select('name, current_balance, currency_code').eq('company_id', companyId).eq('is_active', true),
        sb.from('bank_accounts').select('account_name, current_balance, currency_code, banks(name)').eq('company_id', companyId).eq('is_active', true)
      ])
      return {
        cash_registers: (cash.data||[]).map((c:any) => ({ name: c.name, balance: parseFloat(c.current_balance||0), currency: c.currency_code })),
        bank_accounts: (bank.data||[]).map((b:any) => ({ name: b.account_name, bank: b.banks?.name, balance: parseFloat(b.current_balance||0), currency: b.currency_code })),
        total_cash: (cash.data||[]).reduce((s:number,c:any) => s + parseFloat(c.current_balance||0), 0),
        total_bank: (bank.data||[]).reduce((s:number,b:any) => s + parseFloat(b.current_balance||0), 0)
      }
    }

    case 'get_recent_transactions': {
      const limit = input.limit || 10
      const out: any[] = []
      if (input.type === 'sales' || input.type === 'all'){
        const { data } = await sb.from('sales_orders')
          .select('order_number, total, status, issue_date, contacts(name)')
          .eq('company_id', companyId).eq('is_active', true)
          .order('issue_date', { ascending: false }).limit(limit)
        ;(data||[]).forEach((o:any) => out.push({
          type:'sale', reference: o.order_number, contact: o.contacts?.name,
          amount: parseFloat(o.total||0), status: o.status, date: o.issue_date
        }))
      }
      if (input.type === 'purchases' || input.type === 'all'){
        const { data } = await sb.from('purchase_orders')
          .select('order_number, total, status, issue_date, contacts(name)')
          .eq('company_id', companyId).eq('is_active', true)
          .order('issue_date', { ascending: false }).limit(limit)
        ;(data||[]).forEach((o:any) => out.push({
          type:'purchase', reference: o.order_number, contact: o.contacts?.name,
          amount: parseFloat(o.total||0), status: o.status, date: o.issue_date
        }))
      }
      out.sort((a,b) => (b.date||'').localeCompare(a.date||''))
      return { transactions: out.slice(0, limit) }
    }

    default: return { error: 'Unknown tool: ' + name }
  }
}

// ===== MAIN HANDLER =====
async function callAnthropic(apiKey: string, payload: any){
  const resp = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify(payload)
  })
  const text = await resp.text()
  if (!resp.ok) return { ok: false, status: resp.status, body: text }
  return { ok: true, status: resp.status, body: text }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const sb = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } })

    let apiKey = Deno.env.get('ANTHROPIC_API_KEY') || ''
    if (!apiKey) {
      const { data } = await sb.from('app_settings').select('value').eq('key', 'anthropic_api_key').maybeSingle()
      apiKey = data?.value || ''
    }
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'Anthropic API key not configured' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const body = await req.json().catch(() => ({}))
    const { prompt, messages, system, model, max_tokens, companyId, useTools } = body
    const msgs = Array.isArray(messages) && messages.length
      ? [...messages]
      : (prompt ? [{ role: 'user', content: String(prompt) }] : null)
    if (!msgs) {
      return new Response(JSON.stringify({ error: 'prompt or messages is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const wantTools = useTools !== false && !!companyId  // default ON when companyId is provided

    const payload: any = {
      model: model || ANTHROPIC_MODEL,
      max_tokens: Math.min(Math.max(+max_tokens || 1024, 1), 4096),
      messages: msgs
    }
    if (system) payload.system = String(system)
    if (wantTools) payload.tools = TOOLS

    let result: any
    let attempt = 0
    let pendingMsgs = msgs
    // Tool-loop: max 3 turns
    while (attempt < 3) {
      attempt++
      const callPayload = { ...payload, messages: pendingMsgs }
      const r = await callAnthropic(apiKey, callPayload)
      if (!r.ok) {
        return new Response(r.body, { status: r.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      result = JSON.parse(r.body)
      if (result.stop_reason !== 'tool_use' || !wantTools) break
      // Execute tools
      const toolResults: any[] = []
      for (const block of (result.content || [])) {
        if (block.type === 'tool_use') {
          const tr = await executeTool(block.name, block.input || {}, sb, companyId)
          toolResults.push({ type:'tool_result', tool_use_id: block.id, content: JSON.stringify(tr) })
        }
      }
      pendingMsgs = [
        ...pendingMsgs,
        { role: 'assistant', content: result.content },
        { role: 'user', content: toolResults }
      ]
    }

    return new Response(JSON.stringify(result), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
