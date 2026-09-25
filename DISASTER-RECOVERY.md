# If something breaks — what to do

## The till won't sign in / shows "session ended"
Sign in again. If it keeps happening on one device, that device's saved login has gone stale — signing out and back in fixes it.

## "N unsynced" never clears
The device is offline, or its session expired without showing the sign-in prompt. Check wifi, then sign out and back in. Orders already taken are safe — they're stored on the device until they sync.

## A device shows a "sync conflict" count going up
Two devices edited the same order at the same time (rare, usually from staff double-tapping "Send to kitchen" on two tills for the same table). One edit wins automatically; nothing crashes. If a specific order looks wrong, reopen it from the Orders tab and re-check the items before payment.

## No sound / notification on a device
That device hasn't enabled notifications (Staff tab → Notifications), or on iPhone, hasn't been added to the Home Screen. Realtime sound alerts only work while the app is actually open on screen; background push needs the one-time setup.

## The printer isn't printing
This app uses the browser's own print dialog — it's not a direct printer connection. Check: printer is set as the OS default, paper size is 80mm (or 58mm, matching Settings), and Chrome was started with `--kiosk-printing` if you want it to skip the print dialog.

## The whole app won't load
1. Check https://og-book-cafe-pos.vercel.app loads on a phone with mobile data (rules out that specific device/wifi).
2. If it's down everywhere, the Supabase project may be paused (free-tier projects pause after ~1 week of no activity) — this is the single most likely cause of a total outage right now. Someone with access to the Supabase dashboard needs to un-pause it.
3. If Supabase is up but the site is down, check Vercel's status page (vercel-status.com).

## You need to get all the data out (backup / leaving the platform)
Every order, menu item, and customer record lives in one Postgres table (`records`) in the Supabase project. Anyone with dashboard access can go to **Table Editor → records → Export** for a full CSV/JSON export at any time. This works regardless of anything else being broken.

## You've lost access to the Supabase or Vercel account
This is the single biggest real risk right now — there is currently no documented secondary admin. Whoever set these accounts up should add a second trusted person as an admin/owner on both the Supabase organization and the Vercel team **before** this becomes an emergency, not after.

## Who to call
There's no formal support contract in place yet — right now, this means contacting whoever built/maintains the system directly. Worth formalizing as the client base grows.
