# OG Book Cafe → AUZlabs platform extraction — audit & draft refactor

Branch: `raw-platform-extract` (created off `claude/book-cafe-pos-deploy-0dq1s1` @ `c64e443`).
**Nothing here has been merged, deployed, or applied to any live database.**
The production branch and the live Vercel/Supabase project are untouched.

## 1. Inventory — current feature set

- **POS / billing** (`index.html`, tab "Sell"): menu grid with sizes/modifiers,
  cart, discounts (% or flat), split-bill payments (cash/UPI/card mixed),
  customer name+phone capture (required), GST-style tax calc, round-off,
  refunds, void with audit trail + reason, duplicate-reprint watermark,
  server-issued sequential invoice numbers with an offline local-number
  fallback.
- **Orders / KOT** (tabs "Orders", "Kitchen"): open-tab management, kitchen
  station routing, ready/served flow with a loud on-screen alert bar.
- **Self-ordering**: table QR → `site.html?t=<table>` → guest builds a cart
  and submits via the `place_order` RPC (rate-limited per table) → appears
  in a staff "Accept → kitchen" queue.
- **Customer-facing site** (`site.html`): Swiss-minimalist marketing site,
  live menu pulled from `public_menu`, admin-editable copy/photos/hours/
  socials, merged self-order flow.
- **Public invoice** (`i.html`): share-token based, no login, WhatsApp-
  friendly link; minimal "matte" print-style design.
- **Inventory** (tab "Stock"): ingredients with low-stock threshold, ±stock
  adjustments, wastage log.
- **Staff** (tab "Staff"): clock in/out (attendance), role management
  (owner/manager/cashier), push-notification opt-in.
- **CRM** (tab "Customers"): repeat-customer list derived from paid orders
  (visits, lifetime spend, last visit).
- **Reports**: day-close / Z-report locking, CSV export.
- **Notifications**: real Web Push (VAPID) via a Supabase Edge Function +
  DB triggers, working on Android/desktop/iOS (PWA installed).
- **Offline-first sync**: IndexedDB local store + sync queue, optimistic
  concurrency (`push_record`), realtime cross-device updates.
- **Admin CMS**: business details, invoice look, self-order welcome text,
  and the entire marketing site's copy/photos, all editable from Settings
  without touching code.

## 2 & 3. Hardcoded-values audit, categorized

Good news first: **most "settings" were already config-driven**, not
hardcoded — `cfg()` in `index.html` (line 21) already merges a defaults
object with a live `records` row (`id='settings'`, editable from the
Settings tab): name, address, phone, tax ID, tax %, invoice prefix, brand
colour, logo URL, invoice footer, paper width, invoice style/font size,
self-order welcome text, and the entire site's copy/photos. None of that
needed touching for the pattern to work — it just needs the *source* of
those settings to become `tenant_settings` instead of a plain `records`
row once tenants share one project (see §5).

What genuinely was hardcoded, found by grepping every file for the cafe's
name/logo/colors/tax model/currency:

| # | File:line (before fix) | Value | Category |
|---|---|---|---|
| 1 | `manifest.json:1` | `"name":"OG Book Cafe POS"`, `"short_name":"OG Book Cafe"` | branding |
| 2 | `index.html:1` | `<title>OG Book Cafe POS</title>` | branding |
| 3 | `sw.js:5` | fallback push title `'OG Book Cafe'` | branding (rarely hit — the Edge Function always sends an explicit title) |
| 4 | `site.html:1` | `<title>OG Book Cafe</title>` | branding |
| 5 | `site.html:2` | meta description "A quiet corner for books and coffee." | branding (one-off copy) |
| 6 | `site.html:91,103,154,157,173,178` | fallback strings `'OG Book Cafe'`, `'Books & Brew'` | branding (fallback defaults; the *live* value was already admin-editable) |
| 7 | `site.html:104-105,116,179-182` | hero/about copy "Quiet pages. Warm cups.", "espresso... stacks" | **genuine one-off content** — bespoke book-cafe copy, not a config value |
| 8 | `site.html` hero/about/gallery SVG doodles (book, coffee cup, teapot shapes) | inline SVG illustrations | **genuine one-off design** — flagging clearly, see below |
| 9 | `index.html:16,21`, `i.html:42`, `site.html:165` | `'₹'` hardcoded in every money-formatting function | business rule (currency) |
| 10 | `index.html:101-102`, `i.html:58-59` | `CGST`/`SGST` hardcoded as two fixed 50/50 invoice lines | business rule (India-specific tax model) |
| 11 | `index.html` footer / `i.html:65` | label text `GSTIN` | business rule (tax-ID naming is jurisdiction-specific) |
| 12 | `supabase/functions/send-push/index.ts:7` | `VAPID_SUBJECT="https://auzlabs.com"` | **not** a hardcode to fix — this identifies *AUZlabs* (the sender) to Apple/Google's push services, correctly shared across all tenants |
| 13 | `index.html:203` `seed()` | demo menu "Masala Tea"/"Coffee", 6 demo tables | one-off demo/seed data, low-stakes, left as-is |
| 14 | `config.js` | Supabase project URL + publishable key | **architecture-level**, not a value swap — see §5 |
| 15 | `supabase/schema.sql:2-15` (`profiles`, `on_signup()`, all RLS policies) | implicitly assumes one restaurant per project | **architecture-level, genuine one-off logic** — see §5 |
| 16 | `STAFF-GUIDE.md`, `DISASTER-RECOVERY.md`, `privacy.html`, `terms.html` | cafe name, live Vercel URL, contact details | one-off content/docs, not app code — needs per-tenant regeneration, not refactoring |

Items 1–6, 9–11 are fixed on this branch (see §5). Items 7–8, 13–16 are
flagged rather than silently reworked — they're real content/design/
architecture decisions, not values with an obvious generic default.

## 4. Proposed `tenant_settings` for OG Book Cafe

```json
{
  "branding": {
    "name": "OG Book Cafe",
    "logo_url": "/logo.png",
    "primary_color": "#1f3d2e",
    "site_kicker": "Books & Brew",
    "site_tagline": "Quiet pages.\nWarm cups.",
    "site_subheading": "A slow corner to read, work and linger — good coffee, good books, and a seat that doesn't rush you.",
    "site_about": "We're a small book cafe — part reading room, part coffee counter. Come for the espresso, stay for the stacks."
  },
  "features": {
    "pos": true,
    "self_order": true,
    "crm": true,
    "inventory": true,
    "kds": true,
    "push_notifications": true
  },
  "business_rules": {
    "currency": "INR",
    "currency_symbol": "₹",
    "tax_rate": 5,
    "tax_labels": ["CGST", "SGST"],
    "tax_id_label": "GSTIN",
    "invoice_prefix": "INV",
    "invoice_footer": "Thank you!",
    "paper_width_mm": 80,
    "invoice_style": "mono",
    "self_order_welcome": "Scan, order and relax. Your order goes straight to our kitchen."
  }
}
```

## 5. Refactor done on this branch

- `index.html`, `i.html`, `site.html`: currency symbol and GST-style tax
  labels are now read from settings (`currency`, `taxLabels` — an array,
  split evenly across however many lines you configure, so a single "Tax"
  region and a CGST+SGST region both work), with generic defaults
  (`₹`/`['Tax']`) instead of hardcoded India-specific values. Tax-ID label
  (`GSTIN` → configurable `taxIdLabel`, default "Tax ID") likewise.
  Settings tab now exposes both.
- `manifest.json`, `<title>` tags, `sw.js` fallback, `site.html` fallback
  copy: generic AUZlabs/"Restaurant" placeholders instead of OG Book
  Cafe's name and cafe-specific copy.
- New `supabase/multi-tenant-schema.sql` (draft, not applied): `tenants`,
  `tenant_settings`, a tenant-scoped `staff` table replacing `profiles`,
  and `tenant_id` + rewritten RLS added to `records`/`guest_orders`/
  `push_subs`.
- New `tenant.js` (draft, not wired into any page yet): the subdomain →
  tenant → settings resolution helper from the brief, plus a shared
  "tenant unavailable" render for suspended/cancelled/unknown tenants.

### What's *not* done, and why — real decisions, not oversights

1. **`config.js` / one-Supabase-project-per-client vs. one shared project.**
   Today, "multi-tenant" is done physically: every client gets their own
   Supabase project and their own static deploy, so `config.js`'s
   `{url, key}` *is* the tenant boundary. Moving to the shared-project
   model in the brief is the actual point of this exercise, but it means
   `config.js` becomes the same for every tenant, and `tenant.js` becomes
   how a page then figures out *which* restaurant it's showing — I've
   built that piece, but wiring it into `index.html`'s boot sequence isn't
   done yet because it depends on decision #2 below.
2. **How a new staff signup gets attached to a tenant.**
   `schema.sql`'s `on_signup()` makes "the first person to ever sign up"
   the owner — true today because there's only one restaurant's accounts
   in the table. Under a shared `auth.users`, that check needs to be
   scoped per-tenant, and a bare DB trigger has no way to know *which*
   tenant a signup is for. I've flagged two real options in
   `multi-tenant-schema.sql` (invite-table vs. admin-provisioned accounts)
   rather than guessing — this changes the signup UX, so it's your call.
3. **Where the admin-editable settings actually live.**
   Right now, Settings-tab edits write to a `records` row. Once
   `tenant_settings` exists, does Settings write there directly, or does
   `records` stay as a live override layer on top of tenant defaults? Both
   work; picking one affects the `cfg()` merge order.
4. **`manifest.json` can't vary by subdomain as a plain static file** — the
   browser fetches it directly, not through JS. Three honest options:
   keep the current one-deploy-per-client model (no code change, PWA icon
   is already per-client); add one tiny serverless function that serves
   `/manifest.json` dynamically per `Host` header (small, but no longer
   "static files, no build step"); or accept a generic "AUZlabs POS" home
   screen icon for every tenant (what this branch does for now). Not
   picking this for you.
5. **The book-cafe-specific hero copy and hand-drawn book/coffee-cup SVG
   doodles in `site.html`** are bespoke design work for this one client's
   brand identity, not a config value with a sensible generic default. A
   bakery or a bar client wouldn't want book-and-coffee doodles. Left
   as-is on this branch; becoming a real multi-vertical product means
   either a small set of swappable illustration themes or dropping to
   plain shapes/no doodles as the generic default.

## Files changed on this branch vs. production

```
manifest.json          | generic branding
sw.js                  | generic push-title fallback
index.html             | title, currency/tax-label config, Settings fields
i.html                 | currency/tax-label config, generic tax-ID label
site.html              | title/meta/fallback copy genericized, currency config
supabase/multi-tenant-schema.sql | NEW — draft tenants/tenant_settings/staff schema
tenant.js              | NEW — draft client-side tenant resolution helper
EXTRACTION_REPORT.md   | NEW — this report
```

No file on `claude/book-cafe-pos-deploy-0dq1s1` was modified; this all
lives on `raw-platform-extract` only, and nothing has been deployed.
