# Restaurant POS: Setup Guide
Everything runs on **your own** accounts (Supabase for the database, Vercel for hosting). Nothing is tied to the developer or any third-party AI account. Allow about 30 minutes.

## What you need
- A Supabase account (supabase.com) and a Vercel account (vercel.com), both signed up with **your** email
- A computer with Node.js installed (only for deploying), plus Chrome on the till tablet or PC
- Optional: a thermal receipt printer (80mm) and your own domain

## 1. Create the database
1. Supabase: New project. Pick the region closest to you and save the database password.
2. Open **SQL Editor > New query**, paste all of `supabase/schema.sql`, click **Run**.

## 2. Create the owner login
1. **Authentication > Users > Add user > Create new user**. Enter your email and password and tick **Auto confirm user**. The first user created is the **owner**.
2. **Authentication > Sign In / Providers**: turn **OFF** "Allow new users to sign up". This stops strangers creating accounts.

## 3. Connect the app to your database
1. **Project Settings > API**. Copy the Project URL and the anon / publishable key.
2. Open `config.js` in a text editor and replace the two placeholder values. Save.

## 4. Put it online
In a terminal, inside this folder:
```
npm i -g vercel
vercel login
vercel --prod
```
Answer the questions: no framework ("Other"), no build command, keep the default output. Vercel prints your live address. To use your own domain, add it under the project's **Settings > Domains**.

## 5. First-time setup in the app
1. Open the address in Chrome, sign in, then open **Settings**: business name, address, phone, GSTIN, GST %, invoice prefix. Add your tables.
2. Open **Menu**: add categories and items. For sizes, type `Half:49, Full:69` in the sizes field.
3. Install the app: Chrome menu > **Install app** (phone: **Add to Home Screen**). **Sign in once while online**; after that it works offline.

## 6. Staff
Add each staff member in Supabase (**Authentication > Users**). They start as **cashier**. To make someone a manager, run in SQL Editor:
`update profiles set role='manager' where email='name@example.com';`
- **Cashier**: sell, send to kitchen, take payment, print.
- **Manager**: also discounts, voids, removing items already sent to the kitchen.
- **Owner**: also menu, tables, settings.

## 7. Daily use
- **Sell**: choose Dine-in, Takeaway or Delivery. For dine-in choose the table. Tap items, then **Send to kitchen** (prints only the new items). Use **Hold** to keep the table open and add items later.
- **Pay**: enter an amount and tap Cash, UPI or Card. Repeat to split the bill. The change is shown. **Complete and print** finishes the sale.
- **Kitchen** tab: open on a second device. Tap **Ready** when done.
- **Orders**: reopen a table, reprint, share the bill on WhatsApp, void (manager).
- **Reports**: pick a date to see sales, GST, cash/UPI/card, expenses and the cash expected in the drawer. Add expenses here.

## 7b. Receipt printer
Set the thermal printer as the default in the operating system, paper size 80mm, margins none. For one-tap printing without the dialog, start Chrome with the `--kiosk-printing` option.

## 8. Test before opening day
1. Turn Wi-Fi off, make a sale. The header shows "1 unsynced".
2. Turn Wi-Fi on. It returns to "synced" within a minute.
3. On a second device, sign in and check the sale appears in **Orders** and the kitchen order in **Kitchen**.

## 9. Backups and costs
- Take the Supabase **Pro** plan for a live restaurant: daily backups, and free projects pause after a week without use.
- Vercel's free Hobby plan is meant for non-commercial use; a business should use a paid plan (or another host such as Netlify or Cloudflare Pages). Check their current terms.
- Export data any time: **Table Editor > records > Export**.

## 10. Troubleshooting
- "Setup needed": `config.js` still has the placeholders.
- "N unsynced" never clears: you are signed out or offline. Sign out, sign in again, and check the keys in `config.js`.
- Old screen after an update: close and reopen the app, or clear the site data in Chrome.
- Sign-in fails: check the user exists and is confirmed in Supabase.

## Known limits
Tills sync through the internet, so two devices cannot share orders during a full outage (each keeps working alone and syncs later). No UPI QR codes, recipe-based stock or Swiggy/Zomato import yet. Cashier limits are enforced in the app; the database only separates owner from staff.
