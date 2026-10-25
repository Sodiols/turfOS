# TurfOS implementation state

Status: P0 implementation in progress; not release ready. Empty workspace assessed 2026-10-25.

## Requirement map
M01-M11: marketing/features/pricing; identity/recovery/invites; help/legal; four-step onboarding.
B01-B21: overview/calendar/drawer/list/detail/requests; facilities/hours/closures/branches; CRM; immutable ledger; reports; team; settings/subscription/audit. B14/B19/B21 are P1.
C01-C04: published facility, candidate availability, validated guest request, accurate acknowledgement. C05/C06 P1 require OTP/gateway; C07 P2.
A01-A08: admin MFA, metadata, versioned plans, separate SaaS billing, support, audit, health. A09 P1.

## Architecture / decisions
Next.js App Router + strict TypeScript + Tailwind + Radix + Lucide; Supabase SSR/Auth and SQL functions. PostgreSQL composite tenant foreign keys, RLS, exclusion constraint, immutable payment records. Exact BDT minor units.
Request mode default; pending requests do not reserve; 30-minute grid; configurable resource durations; UTC storage/branch-local presentation; 14-day trial/7-day grace. Manual payments explicitly attested, no gateways simulated.
Visual: #14283B navy, #008F8B teal, #F4F8F9 background, #203247 text. 248px desktop sidebar, 64px header, five mobile destinations. Marketing variance 4/motion 2/density 4. Radix dialogs; system-neutral typography.

## Implemented locally
- Marketing, pricing, help/contact, draft legal, auth/recovery/invite, four-step onboarding and responsive workspace shell.
- Tenant schema with RLS, compound foreign keys, no browser table writes, role checks, exclusion constraint, idempotent booking writes, UTC/local-time validation and immutable booking/payment history.
- Branch/facility/hours/closure management, manual and public-request bookings, state changes, CRM, manual collections/refunds, daily reporting query and CSV export, staff invitations/membership, subscription state enforcement and admin metadata/billing/support views.
- Guest catalog and availability expose only published data; guest submission is revalidated and rate limited. No customer payment gateway is represented as configured.
- Separate facility and SaaS ledgers, versioned plans, trial/grace/read-only logic, cron endpoint, MFA requirement for admin routes.

## Verified locally
- `npm run lint`, `npm run typecheck`, `npm run build`, `npm test`, and `npm run test:db` pass after the report export addition.
- Local PostgreSQL tests passed full migration, the second migration with older-note data, migration replay, cross-tenant read/write denial, simultaneous booking conflict, idempotency, ledger limits, role denial, reports and read-only subscription enforcement.
- Desktop and mobile public-route browser smoke passed at 1440px and 390px, including home-page WCAG 2 A/AA automated checks and no horizontal overflow. Authenticated owner smoke passed overview, calendar, bookings, customers, and reports at both widths; overview and calendar WCAG 2 A/AA automated checks found no violations. Day cells, slot prefill, week navigation and month navigation passed with synthetic data. This does not cover every workflow or assistive technology.

## Remaining P0 work and limitations
- Perform complete authenticated staging E2E for signup, email verification, onboarding, all booking and payment edits, and admin MFA. Configure verified email delivery and safe invitation sharing.
- The day calendar has a 30-minute facility timeline and cell-to-booking prefill; week/month show per-day summaries that open the day timeline. Deeper week/month resource grids and booking detail edits remain to implement.
- Admin plan changes and subscription settlement need live staging verification. Direct invoice download and a full customer-facing booking lookup need later work.
- Complete monitoring, backup/restore drill, rate-limit abuse test, cross-browser/device checks, support process and qualified legal review before any paid pilot.

## External gates
A local Supabase URL and keys exist, and the user identified the connected project as development/staging with no real business data. The original and second TurfOS schemas were confirmed through read-only catalog queries. Synthetic hosted tests passed onboarding, booking conflict, idempotency, manual collection, reports, invitation acceptance/single use, and staff/admin permission denial; the third migration is therefore effective in the development project. Synthetic QA records are in that project only. No production deployment is claimed. Domain, legal entity, monitored support mailbox, legal review, merchant arrangement, monitoring/backups and pilot validation need founder provisioning.
P1/P2 remain gated on P0 acceptance and pilot evidence; no planned feature is advertised as working.
