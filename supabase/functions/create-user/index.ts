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
    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })

    // Verify caller from Authorization header JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const token = authHeader.replace('Bearer ', '')
    const { data: { user: caller }, error: authErr } = await supabase.auth.getUser(token)
    if (authErr || !caller) {
      return new Response(JSON.stringify({ error: 'Invalid or expired token' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const body = await req.json()
    const { email, password, full_name, company_id, role } = body
    console.log('[create-user] email:', email, 'password length:', password?.length, 'role:', role, 'company_id:', company_id)

    if (!email || !password || !full_name || !company_id || !role) {
      return new Response(JSON.stringify({ error: 'Missing required fields', received: { email: !!email, password: !!password, full_name: !!full_name, company_id: !!company_id, role: !!role } }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Check caller is owner/admin of this company
    const { data: callerRole, error: roleErr } = await supabase.from('company_users')
      .select('role').eq('company_id', company_id).eq('user_id', caller.id).single()
    console.log('[create-user] caller role:', callerRole, 'error:', roleErr)
    if (!callerRole || !['owner', 'admin'].includes(callerRole.role)) {
      return new Response(JSON.stringify({ error: 'Only owner/admin can add users' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Create user with admin API (auto-confirm email)
    const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name, skip_company_creation: true, added_to_company: company_id }
    })
    console.log('[create-user] createUser result:', newUser?.user?.id, 'error:', createErr)
    if (createErr) {
      return new Response(JSON.stringify({ error: createErr.message }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const userId = newUser.user.id

    // Add to company_users
    const { error: cuErr } = await supabase.from('company_users').insert({
      company_id, user_id: userId, role, status: 'active', joined_at: new Date().toISOString()
    })
    console.log('[create-user] company_users insert:', cuErr ? cuErr.message : 'OK')

    // Add profile with must_change_password flag
    const { error: profErr } = await supabase.from('profiles').upsert({
      id: userId, full_name, company_id, must_change_password: true
    }, { onConflict: 'id' })
    console.log('[create-user] profiles upsert:', profErr ? profErr.message : 'OK')

    // Add default permissions based on role
    const { data: defaults, error: permErr } = await supabase.rpc('get_default_permissions', { p_role: role })
    console.log('[create-user] permissions:', defaults?.length || 0, 'error:', permErr)
    if (defaults && defaults.length) {
      await supabase.from('user_permissions').insert(
        defaults.map((d: any) => ({
          company_id, user_id: userId, module: d.module,
          can_view: d.can_view, can_create: d.can_create, can_edit: d.can_edit, can_delete: d.can_delete
        }))
      )
    }

    return new Response(JSON.stringify({ success: true, user_id: userId, email, company_id }), {
      status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
