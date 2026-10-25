// Synthetic, opt-in integration check for a confirmed development Supabase project.
// Leaves QA-prefixed records in that project for browser follow-up. Never run against production.
import { createClient } from '@supabase/supabase-js';
import { randomUUID, randomBytes } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { formatInTimeZone, fromZonedTime } from 'date-fns-tz';

const env = Object.fromEntries((await readFile('.env.local', 'utf8')).split(/\r?\n/).filter(line => line && !line.startsWith('#') && line.includes('=')).map(line => line.split(/=(.*)/s).slice(0, 2)));
const url = env.NEXT_PUBLIC_SUPABASE_URL;
const service = createClient(url, env.SUPABASE_SECRET_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const tag = Date.now().toString(36);
const qa = { tag, users: [], businesses: [] };
const assertOk = (result, label) => { if (result.error) throw new Error(`${label}: ${result.error.message}`); return result.data; };
async function identity(label) {
  const email = `turfos-${label}-${tag}@example.invalid`;
  const password = randomBytes(24).toString('base64url');
  const user = assertOk(await service.auth.admin.createUser({ email, password, email_confirm: true }), `create ${label}`).user;
  const db = createClient(url, env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  assertOk(await db.auth.signInWithPassword({ email, password }), `sign in ${label}`);
  qa.users.push({ id: user.id, email, password });
  return db;
}

try {
  const one = await identity('owner-a');
  const two = await identity('owner-b');
  const staff = await identity('staff');
  const b1 = assertOk(await one.rpc('onboard', { d: { slug: `qa-arena-a-${tag}`, name: `QA Arena A ${tag}`, phone: '+8801711110001', city: 'Dhaka', plan: 'business' } }), 'onboard A');
  const b2 = assertOk(await two.rpc('onboard', { d: { slug: `qa-arena-b-${tag}`, name: `QA Arena B ${tag}`, phone: '+8801711110002', city: 'Dhaka', plan: 'business' } }), 'onboard B');
  qa.businesses.push(b1, b2);
  const branch = assertOk(await one.rpc('mutate', { b: b1.id, action: 'branch', d: { name: 'QA Main', address: 'Synthetic test location', timezone: 'Asia/Dhaka' } }), 'branch A');
  const facility = assertOk(await one.rpc('mutate', { b: b1.id, action: 'facility', d: { branch_id: branch.id, name: 'QA Ground', sport: 'football', rate_minor: 120000, capacity: 12, durations: [60], opens: '06:00', closes: '23:00' } }), 'facility A');
  assertOk(await one.rpc('mutate', { b: b1.id, action: 'settings', d: { name: `QA Arena A ${tag}`, phone: '+8801711110001', city: 'Dhaka', public_phone: '', published: true, lead_minutes: 60, horizon_days: 60 } }), 'publish A');
  const catalog = assertOk(await service.rpc('public_catalog', { slug_value: b1.slug }), 'catalog');
  assert.equal(catalog.facilities.length, 1);
  assert.equal(JSON.stringify(catalog).includes('QA Customer'), false);

  const localDay = formatInTimeZone(new Date(Date.now() + 2 * 86400000), 'Asia/Dhaka', 'yyyy-MM-dd');
  const starts_at = fromZonedTime(`${localDay}T18:00`, 'Asia/Dhaka').toISOString();
  const ends_at = fromZonedTime(`${localDay}T19:00`, 'Asia/Dhaka').toISOString();
  const slot = { facility_id: facility.id, starts_at, ends_at, customer_name: 'QA Customer', phone: '+8801711110003', idempotency_key: randomUUID(), source: 'manual' };
  const second = createClient(url, env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  assertOk(await second.auth.signInWithPassword({ email: qa.users[0].email, password: qa.users[0].password }), 'second session');
  const secondSlot = { ...slot, phone: '+8801711110004', idempotency_key: randomUUID() };
  const outcomes = await Promise.all([one.rpc('create_booking', { b: b1.id, d: slot, guest: false }), second.rpc('create_booking', { b: b1.id, d: secondSlot, guest: false })]);
  assert.equal(outcomes.filter(x => !x.error).length, 1, 'only one concurrent confirmation wins');
  const booking = outcomes.find(x => !x.error).data;
  assert.equal(assertOk(await one.rpc('create_booking', { b: b1.id, d: outcomes[0].error ? secondSlot : slot, guest: false }), 'idempotent retry').id, booking.id);
  assert.equal((assertOk(await two.from('bookings').select('id'), 'tenant B booking read')).length, 0);
  assert.ok((await two.rpc('record_payment', { b: b1.id, d: { booking_id: booking.id, amount_minor: 1, kind: 'collection', method: 'cash', idempotency_key: randomUUID() } })).error);
  assertOk(await one.rpc('record_payment', { b: b1.id, d: { booking_id: booking.id, amount_minor: 50000, kind: 'collection', method: 'cash', idempotency_key: randomUUID() } }), 'manual collection');
  const report = assertOk(await one.rpc('business_report', { b: b1.id, from_at: fromZonedTime(`${localDay}T00:00`, 'Asia/Dhaka').toISOString(), to_at: fromZonedTime(`${formatInTimeZone(new Date(Date.parse(`${localDay}T00:00:00Z`) + 86400000), 'Asia/Dhaka', 'yyyy-MM-dd')}T00:00`, 'Asia/Dhaka').toISOString(), branch: null }), 'report');
  assert.equal(report.booking_value_minor, 120000);
  assert.equal(report.outstanding_minor, 70000);
  const invitation = assertOk(await one.rpc('mutate', { b: b1.id, action: 'invite', d: { email: qa.users[2].email, role: 'staff' } }), 'invite staff');
  assertOk(await staff.rpc('accept_invite', { token: invitation.token }), 'accept staff');
  assert.equal((assertOk(await staff.from('payments').select('id'), 'staff payment read')).length, 0);
  assert.ok((await staff.rpc('record_payment', { b: b1.id, d: { booking_id: booking.id, amount_minor: 100, kind: 'collection', method: 'cash', idempotency_key: randomUUID() } })).error);
  assert.ok((await staff.rpc('platform_mutate', { action: 'business_state', d: { id: b1.id, state: 'suspended', reason: 'QA test' } })).error);
  await mkdir('.local', { recursive: true });
  await writeFile('.local/hosted-qa.json', JSON.stringify(qa, null, 2));
  console.log('PASS: hosted development onboarding, tenant isolation, booking race, idempotency, manual ledger, reports, invite acceptance, staff/admin denial');
  console.log('QA records retained in the development project; credentials saved only in ignored .local/hosted-qa.json');
} catch (error) {
  await mkdir('.local', { recursive: true });
  await writeFile('.local/hosted-qa-partial.json', JSON.stringify(qa, null, 2));
  console.error(error instanceof Error ? error.message : 'Hosted test failed');
  process.exitCode = 1;
}
