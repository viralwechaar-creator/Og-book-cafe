-- AUZlabs multi-tenant platform schema — DRAFT, NOT APPLIED ANYWHERE.
--
-- This is additive/parallel to schema.sql, which remains the accurate
-- description of OG Book Cafe's live, single-tenant production database.
-- Nothing here has been run against any project. It sketches what OG Book
-- Cafe's schema becomes once multiple restaurants share one Supabase
-- project, isolated by tenant_id + RLS instead of "one project per client".
--
-- This is a genuine architecture change, not a config swap: every table,
-- every RLS policy and every RPC function in schema.sql assumes a single
-- restaurant per project (e.g. `me()` just checks "is this uid a staff
-- profile in *the* profiles table" — there is only ever one restaurant's
-- worth of profiles). None of that can be config-driven; it has to be
-- rewritten to filter and stamp every row with tenant_id. Treat this file
-- as the starting proposal for that rewrite, to be reviewed before it
-- becomes real migrations.

create table tenants(
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  plan text not null default 'starter' check(plan in('starter','pro','enterprise')),
  status text not null default 'trial' check(status in('trial','active','suspended','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table tenant_settings(
  tenant_id uuid primary key references tenants(id) on delete cascade,
  branding jsonb not null default '{}',
  -- {"name","logo_url","primary_color","invoice_prefix", ...}
  features jsonb not null default '{"pos":true,"self_order":true,"crm":true,"inventory":true}',
  business_rules jsonb not null default '{}',
  -- {"currency":"INR","currency_symbol":"₹","tax_rate":5,"tax_labels":["CGST","SGST"],
  --  "invoice_footer":"Thank you!","paper_width":80,"invoice_style":"mono"}
  updated_at timestamptz not null default now()
);
alter table tenants enable row level security;
alter table tenant_settings enable row level security;
-- Looking up a tenant/its branding by slug is how every page boots — it
-- must be readable by anyone, logged in or not (this is the client-side
-- equivalent of the withTenant() DB-session-variable pattern: there's no
-- server process here to hold a "current tenant" session, so every page
-- resolves it itself from the subdomain on load, per tenant.js).
create policy tenants_read on tenants for select using(true);
create policy tenant_settings_read on tenant_settings for select using(true);
-- Writes are service-role only (the AUZlabs admin backend), not exposed here.

-- Every staff member belongs to exactly one tenant. Replaces `profiles`
-- being implicitly scoped to "the one restaurant this project runs".
create table staff(
  id uuid primary key references auth.users on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  email text,
  role text not null default 'cashier' check(role in('owner','manager','cashier'))
);
alter table staff enable row level security;
create function my_tenant() returns uuid language sql security definer stable set search_path=public as $$
  select tenant_id from staff where id=auth.uid()
$$;
create function my_role() returns text language sql security definer stable set search_path=public as $$
  select role from staff where id=auth.uid()
$$;
create policy staff_read on staff for select using(tenant_id=my_tenant());
create policy staff_write on staff for update using(tenant_id=my_tenant() and my_role()='owner');

-- IMPORTANT — open decision, not solved by this file:
-- schema.sql's on_signup() trigger makes "the first person to ever sign up"
-- the owner, because there's only one restaurant. That rule breaks here:
-- with a shared auth.users table, the second tenant's first real signup
-- would land after other tenants' rows already exist in `staff`, so the
-- "am I the first" check must be scoped to a tenant, and a bare
-- Postgres trigger on auth.users has no way to know which tenant a new
-- signup is *for* (it isn't in the JWT yet, there's no request context).
-- Realistic options, pick one before implementing:
--  (a) invite-only signup: an `invites(tenant_id, email, role)` table an
--      owner populates; on_signup looks up the invite by email and
--      inserts into `staff` with that tenant_id (rejects signup if none).
--  (b) admin-provisioned accounts: AUZlabs backend creates the user via
--      the service role and inserts the `staff` row in the same
--      transaction, with no public self-signup at all.
-- (a) matches this app's existing "owner manages who has access" model
-- most closely and is the recommended default.

-- records: add tenant_id, and every RLS policy now checks the caller's
-- own tenant instead of "any authenticated staff member of this project".
alter table records add column tenant_id uuid references tenants(id);
create index on records(tenant_id);
drop policy if exists r_read on records;
drop policy if exists r_ins on records;
drop policy if exists r_upd on records;
create policy r_read on records for select using(tenant_id=my_tenant());
create policy r_ins on records for insert with check(
  tenant_id=my_tenant() and (kind in('order','exp','shift','ing','waste','voidlog') or my_role()='owner')
);
create policy r_upd on records for update using(
  tenant_id=my_tenant() and (kind in('order','exp','shift','ing','waste','voidlog') or my_role()='owner')
) with check(
  tenant_id=my_tenant() and (kind in('order','exp','shift','ing','waste','voidlog') or my_role()='owner')
);
-- Every client-side save() call must now also set tenant_id explicitly
-- (see tenant.js) — RLS above is the backstop that rejects it if it's
-- wrong or missing, matching the "still send tenant_id, RLS is the
-- backstop" note in the extraction brief.

-- guest_orders and push_subs: same pattern, add tenant_id, scope policies,
-- and public_menu/place_order/public_invoice/next_invoice_no all take an
-- extra tenant slug/id argument instead of implicitly meaning "the one
-- restaurant this project has". Sketched, not written out line-by-line
-- here since they're mechanical repeats of the records change above —
-- happy to write the full migration once the invite-vs-admin-provisioning
-- decision above is made, since it also affects how these RPCs authorize.
alter table guest_orders add column tenant_id uuid references tenants(id);
create index on guest_orders(tenant_id);
alter table push_subs add column tenant_id uuid references tenants(id);
create index on push_subs(tenant_id);
