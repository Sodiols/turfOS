# Architecture

Next.js Server Components read through Supabase SSR sessions. Server actions validate inputs and call PostgreSQL security-definer operations. Public catalog, availability and requests use narrow server routes. The browser receives only the Supabase publishable key.

Business ID is the tenant root. Composite foreign keys keep branches, facilities, customers, bookings and payments in the same business. Row Level Security protects reads; authenticated browser roles have no direct write grants. Membership and subscription checks run inside database functions. Platform administrators need a separate admin record and AAL2 authentication.

Confirmed bookings use a PostgreSQL exclusion constraint on resource/time ranges. Pending requests do not hold a slot. Booking prices are snapshotted. Facility collections and SaaS subscription receipts have separate ledgers. All BDT amounts are stored as integer paisa.

The database test harness creates synthetic businesses only in ignored local clusters. Before applying SQL to a hosted project, identify its environment, back it up, and use the versioned upgrade for existing installations.
