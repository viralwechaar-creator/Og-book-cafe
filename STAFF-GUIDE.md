# OG Book Cafe POS — Staff Quick Guide

Covers the newer features added after initial setup. See SETUP-GUIDE.md for the basics (signing in, adding menu items, tables, etc.).

## Notifications
Each device should enable its own alerts once: **Staff tab → Notifications → "Enable notifications on this device."** This gets you an order alert even if the app/browser is fully closed. On iPhone, the app must first be "Added to Home Screen" (Share button → Add to Home Screen) — Safari tabs alone can't receive it.

## Selling
- **Customer name and phone are required** before you can complete payment or send an order to kitchen from the self-order QR page.
- **Item modifiers** (if set up in Menu, e.g. "Extra shot +₹20"): tapping an item with modifiers shows a checklist before it's added to the cart.
- **Split bill**: in the Pay screen, "Split equally" asks how many people are splitting; "Split by item" lets you pick which items to charge now.

## Kitchen
- The Kitchen tab now has **All / Kitchen / Bar / Dessert** filter buttons. Set an item's station in Menu → Edit item.
- Orders and self-orders trigger a loud alert automatically on every device with notifications enabled.

## Orders tab
- **Print**: reprinting an already-paid invoice shows a "DUPLICATE — REPRINT" watermark automatically — this is expected and correct for audit purposes.
- **Refund** (manager/owner only): records a partial or full refund with a reason. It does not process money back through any payment gateway — that step still happens manually (cash back, UPI refund, etc.) the same way it always did; this just keeps the books correct.
- **Void** (manager/owner only): now requires a typed reason, which is logged permanently for audit purposes.

## Reports
- **Close day** (owner only): locks that date's expenses/voids/refunds against further edits. Use this at the end of each business day once the till is settled.
- **Reopen day** (owner only): undoes a close, if you need to fix something afterward.
- **Export orders CSV** / **Export items CSV**: downloads that day's data for accounting.

## Customers tab
Shows repeat visitors by phone number — visit count, total spend, last visit. This is built from your own sales history automatically; nothing to set up.

## Website (site.html)
Editable from **Settings → Website** (owner only): headline, subheading, about text, hours, Instagram/Maps links, and hero/about/gallery photos. Uploaded photos are compressed automatically — no need to resize before uploading.

## If something looks wrong
See DISASTER-RECOVERY.md.
