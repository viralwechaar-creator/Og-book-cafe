import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

// VAPID keys identify this server to push services. Not user secrets, but
// kept out of client code since only this function needs to sign with them.
const VAPID_PUBLIC = "BN_aBfhAkcWmYJ8RArUKpcXFBId6rUsNO7bAuhyPr4To51XeATMoWY-8NxtJMCG_iHm4O4UbhV_EZnxloXkEMe4";
const VAPID_PRIVATE = "yXhFYwFxBrl8KVBm072v_JV3PV_UeAEQY6T65ChFKEw";
// Shared secret the DB trigger must present, since this function has
// verify_jwt disabled (Postgres triggers can't carry a user JWT).
const TRIGGER_SECRET = "ce341201e148ab63e776da0fbdb63ebfe30368d241f27ac4";

webpush.setVapidDetails("mailto:owner@ogbookcafe.example", VAPID_PUBLIC, VAPID_PRIVATE);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.headers.get("x-trigger-secret") !== TRIGGER_SECRET) {
    return new Response("forbidden", { status: 403 });
  }
  let payload: { title?: string; body?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }
  const title = payload.title || "OG Book Cafe";
  const body = payload.body || "";

  const { data: subs, error } = await supabase.from("push_subs").select("*");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  let sent = 0, removed = 0;
  await Promise.allSettled((subs || []).map(async (s: any) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify({ title, body }),
      );
      sent++;
    } catch (e: any) {
      if (e.statusCode === 404 || e.statusCode === 410) {
        await supabase.from("push_subs").delete().eq("id", s.id);
        removed++;
      }
    }
  }));

  return new Response(JSON.stringify({ sent, removed, total: (subs || []).length }), {
    headers: { "Content-Type": "application/json" },
  });
});
