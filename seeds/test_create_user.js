require('dotenv').config();
/**
 * Test create-user flow
 *
 * Usage:
 *   node seeds/test_create_user.js
 *
 * Steps:
 *   1. Delete existing test user (if any)
 *   2. Create user with admin API
 *   3. Test login with created credentials
 */

const { createClient } = require('@supabase/supabase-js');

const URL = 'https://jaakjdzpdizjbzvbtcld.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const ANON_KEY = 'sb_publishable_Zp3NcrPr7yPrL8zgpiNmfA_YF7RGHe9';

if (!SERVICE_KEY) {
  console.error('Set SUPABASE_SERVICE_KEY env variable');
  process.exit(1);
}

const admin = createClient(URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});
const anon = createClient(URL, ANON_KEY);

const TEST_EMAIL = 'bulentkosker@hotmail.com';
const TEST_PASS = 'Test1234!';

async function main() {
  // Step 1: Clean up existing user
  console.log('\n--- Step 1: Cleanup ---');
  const { data: existingUsers } = await admin.auth.admin.listUsers();
  const existing = existingUsers?.users?.find(u => u.email === TEST_EMAIL);
  if (existing) {
    console.log('Found existing user:', existing.id);
    await admin.from('user_permissions').delete().eq('user_id', existing.id);
    await admin.from('company_users').delete().eq('user_id', existing.id);
    await admin.from('profiles').delete().eq('id', existing.id);
    const { error: delErr } = await admin.auth.admin.deleteUser(existing.id);
    console.log('Deleted:', delErr ? delErr.message : 'OK');
  } else {
    console.log('No existing user found');
  }

  // Step 2: Create user with admin API
  console.log('\n--- Step 2: Create User ---');
  const { data: newUser, error: createErr } = await admin.auth.admin.createUser({
    email: TEST_EMAIL,
    password: TEST_PASS,
    email_confirm: true,
    user_metadata: { full_name: 'Bulent Test' }
  });
  if (createErr) {
    console.error('CREATE ERROR:', createErr);
    return;
  }
  console.log('Created user:', newUser.user.id);
  console.log('Email confirmed:', newUser.user.email_confirmed_at ? 'YES' : 'NO');
  console.log('Identities:', newUser.user.identities?.length || 0);

  // Step 3: Test login
  console.log('\n--- Step 3: Login Test ---');
  const { data: loginData, error: loginErr } = await anon.auth.signInWithPassword({
    email: TEST_EMAIL,
    password: TEST_PASS
  });
  if (loginErr) {
    console.error('LOGIN ERROR:', loginErr.message);
    console.log('\nDebug: checking user state...');
    const { data: checkUser } = await admin.auth.admin.getUserById(newUser.user.id);
    console.log('User email:', checkUser.user?.email);
    console.log('Email confirmed at:', checkUser.user?.email_confirmed_at);
    console.log('Last sign in:', checkUser.user?.last_sign_in_at);
    console.log('Banned:', checkUser.user?.banned_until);
  } else {
    console.log('LOGIN SUCCESS!');
    console.log('Session token length:', loginData.session?.access_token?.length);
    console.log('User email:', loginData.user?.email);
  }

  // Cleanup test user
  console.log('\n--- Cleanup ---');
  const { error: cleanErr } = await admin.auth.admin.deleteUser(newUser.user.id);
  console.log('Cleanup:', cleanErr ? cleanErr.message : 'OK');
}

main().catch(e => console.error('Fatal:', e));
