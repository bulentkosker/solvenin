import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceKey)

    // Verify the calling user is owner/admin
    const authHeader = req.headers.get('Authorization')!
    const anonClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!)
    const { data: { user: caller } } = await anonClient.auth.getUser(authHeader.replace('Bearer ', ''))
    if (!caller) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { email, password, full_name, company_id, role } = await req.json()
    if (!email || !password || !full_name || !company_id || !role) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Check caller is owner/admin of this company
    const { data: callerRole } = await supabase.from('company_users')
      .select('role').eq('company_id', company_id).eq('user_id', caller.id).single()
    if (!callerRole || !['owner', 'admin'].includes(callerRole.role)) {
      return new Response(JSON.stringify({ error: 'Only owner/admin can add users' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Create user with admin API (auto-confirm)
    const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name }
    })
    if (createErr) {
      return new Response(JSON.stringify({ error: createErr.message }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const userId = newUser.user.id

    // Add to company_users
    await supabase.from('company_users').insert({
      company_id, user_id: userId, role, status: 'active', joined_at: new Date().toISOString()
    })

    // Add profile
    await supabase.from('profiles').upsert({
      id: userId, full_name, company_id, must_change_password: true
    }, { onConflict: 'id' })

    // Add default permissions
    const { data: defaults } = await supabase.rpc('get_default_permissions', { p_role: role })
    if (defaults && defaults.length) {
      await supabase.from('user_permissions').insert(
        defaults.map((d: any) => ({
          company_id, user_id: userId, module: d.module,
          can_view: d.can_view, can_create: d.can_create, can_edit: d.can_edit, can_delete: d.can_delete
        }))
      )
    }

    return new Response(JSON.stringify({ success: true, user_id: userId }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
