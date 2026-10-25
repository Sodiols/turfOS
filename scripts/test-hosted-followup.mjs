// Continues the synthetic development test after the Supabase extensions migration.
import { createClient } from '@supabase/supabase-js';
import { readFile, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const env = Object.fromEntries((await readFile('.env.local', 'utf8')).split(/\r?\n/).filter(line => line && !line.startsWith('#') && line.includes('=')).map(line => line.split(/=(.*)/s).slice(0, 2)));
const qa = JSON.parse(await readFile('.local/hosted-qa-partial.json', 'utf8'));
const client = () => createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const owner = client(), staff = client();
const assertOk = (result, label) => { if (result.error) throw new Error(`${label}: ${result.error.message}`); return result.data; };

assertOk(await owner.auth.signInWithPassword({ email: qa.users[0].email, password: qa.users[0].password }), 'owner sign in');
assertOk(await staff.auth.signInWithPassword({ email: qa.users[2].email, password: qa.users[2].password }), 'staff sign in');
const b = qa.businesses[0];
const invitation = assertOk(await owner.rpc('mutate', { b: b.id, action: 'invite', d: { email: qa.users[2].email, role: 'staff' } }), 'create invitation');
assert.equal(assertOk(await staff.rpc('accept_invite', { token: invitation.token }), 'accept invitation').slug, b.slug);
assert.ok((await staff.rpc('accept_invite', { token: invitation.token })).error, 'invitation cannot be reused');
assert.equal(assertOk(await staff.from('payments').select('id'), 'staff ledger read').length, 0);
assert.ok((await staff.rpc('platform_mutate', { action: 'business_state', d: { id: b.id, state: 'suspended', reason: 'QA role test' } })).error);
await writeFile('.local/hosted-qa.json', JSON.stringify(qa, null, 2));
console.log('PASS: hosted development staff invitation, single use, ledger isolation and platform admin denial');
