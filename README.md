# TurfOS

Private sports facility operations SaaS built with Next.js, TypeScript, Tailwind and Supabase PostgreSQL/Auth. The app has a locally tested P0 foundation. It is not ready for paid facilities or production bookings; see [implementation state](docs/implementation-state.md).

## Local setup

1. Use Node.js 20.9+ and run `npm ci`.
2. Use a confirmed development Supabase project. Copy `.env.example` to `.env.local` and configure its URL, publishable key, server secret, `APP_BASE_URL`, `RATE_LIMIT_SALT`, and `CRON_AUTH_TOKEN`. Never expose secret keys with a `NEXT_PUBLIC_` prefix.
3. Configure verified email and an approved `/auth/callback` redirect in Supabase. A verified sender is needed for email delivery.
4. Apply the versioned migrations in order. If `profiles` already exists and the first migration was previously applied, apply only the missing later migrations. The second copies older customer notes into a role-restricted table before removing the old column. The third adapts function lookup for Supabase's `extensions` schema. Never rerun the whole first migration in an existing project.
5. Run `npm run dev` and open `http://127.0.0.1:3200`.

An authorized database operator must add a verified identity to `public.platform_admins` in the protected Supabase console. Platform administration requires an authenticator AAL2 session. There is no public admin signup.

## Checks

- `npm run lint`, `npm run typecheck`, and `npm run build` check the application.
- `npm test` runs pure domain tests.
- `npm run test:db` starts an isolated PostgreSQL cluster in ignored `.local/`, applies all three migrations, and checks tenant isolation, conflicts, finance, permissions and migration replay. It never touches hosted data.
- `node scripts/browser-smoke.mjs` checks public routes, desktop/mobile overflow, and a WCAG 2 A/AA scan. Start the dev server first. This script currently uses a local Chrome path on Windows.
- `node scripts/browser-auth-smoke.mjs` checks authenticated owner routes in the confirmed development project using synthetic users saved by the hosted QA scripts in ignored `.local/`.
- Owner and manager reports can be downloaded as a CSV from the Reports page. The export uses the selected date range and branch and escapes spreadsheet formulas in facility names.
- The calendar shows a 30-minute day timeline by facility. Selecting an open cell prefills the new booking drawer; week and month summaries open the corresponding day.

For subscription transitions, schedule `POST /api/internal/subscriptions` with `Authorization: Bearer <CRON_AUTH_TOKEN>`. Booking writes enforce subscription deadlines even if this job is late. Staff invitations currently return an expiring single-use link to share privately; automatic email delivery needs a verified sender. Legal pages remain drafts pending qualified local review.

See [architecture](docs/architecture.md) and [implementation state](docs/implementation-state.md) for scope and remaining launch gates.
