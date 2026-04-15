import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })

    // Resolve API key: prefer Supabase secret, fall back to app_settings table
    let apiKey = Deno.env.get('ANTHROPIC_API_KEY') || ''
    if (!apiKey) {
      const { data } = await supabase.from('app_settings').select('value').eq('key', 'anthropic_api_key').maybeSingle()
      apiKey = data?.value || ''
    }
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'Anthropic API key not configured' }), {
        status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const body = await req.json().catch(() => ({}))
    const {
      prompt,            // shorthand: single-user-message form
      messages,          // full messages array (preferred)
      system,            // optional system prompt
      model,
      max_tokens
    } = body

    const msgs = Array.isArray(messages) && messages.length
      ? messages
      : (prompt ? [{ role: 'user', content: String(prompt) }] : null)
    if (!msgs) {
      return new Response(JSON.stringify({ error: 'prompt or messages is required' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const payload: Record<string, unknown> = {
      model: model || 'claude-sonnet-4-20250514',
      max_tokens: Math.min(Math.max(+max_tokens || 1024, 1), 4096),
      messages: msgs
    }
    if (system) payload.system = String(system)

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
    return new Response(text, {
      status: resp.status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
