-- Run once in Supabase > SQL Editor
create table profiles(id uuid primary key references auth.users on delete cascade,email text,role text not null default 'cashier' check(role in('owner','manager','cashier')));
create table records(id text primary key,kind text not null,data jsonb not null,deleted boolean not null default false,author uuid default auth.uid(),updated_at timestamptz not null default now());
create index on records(updated_at);
alter table profiles enable row level security; alter table records enable row level security;
create function me() returns text language sql security definer stable set search_path=public as $$select role from profiles where id=auth.uid()$$;
create function on_signup() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,email,role) values(new.id,new.email,case when exists(select 1 from profiles) then 'cashier' else 'owner' end);return new;end$$;
create trigger t_signup after insert on auth.users for each row execute function on_signup();
create function touch() returns trigger language plpgsql as $$begin new.updated_at=now();return new;end$$;
create trigger t_touch before insert or update on records for each row execute function touch();
create policy p_read on profiles for select using(id=auth.uid() or me()='owner');
create policy p_set on profiles for update using(me()='owner');
create policy r_read on records for select using(me() is not null);
create policy r_ins on records for insert with check(me() is not null and (kind in('order','exp','shift','ing','waste','voidlog') or me()='owner'));
create policy r_upd on records for update using(me() is not null and (kind in('order','exp','shift','ing','waste','voidlog') or me()='owner')) with check(me() is not null and (kind in('order','exp','shift','ing','waste','voidlog') or me()='owner'));
alter publication supabase_realtime add table records;
-- Promote a user:  update profiles set role='manager' where email='someone@example.com';

-- Self-order via table QR (order.html): guests place orders without logging in.
create table guest_orders(id uuid primary key default gen_random_uuid(),tbl text not null,name text not null,phone text not null,note text,items jsonb not null,status text not null default 'new',created_at timestamptz not null default now());
alter table guest_orders enable row level security;
create policy g_read on guest_orders for select using(me() is not null);
create policy g_upd on guest_orders for update using(me() is not null) with check(me() is not null);
alter publication supabase_realtime add table guest_orders;

create function public_menu() returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object(
  'items',coalesce((select jsonb_agg(data) from records where kind='item' and not deleted),'[]'::jsonb),
  'cats',coalesce((select jsonb_agg(data) from records where kind='cat' and not deleted),'[]'::jsonb),
  'tables',coalesce((select jsonb_agg(data) from records where kind='table' and not deleted),'[]'::jsonb),
  'cfg',coalesce((select data from records where id='settings'),'{}'::jsonb)
 )
$$;
grant execute on function public_menu() to anon;

create function place_order(t text,n text,p text,nt text,its jsonb) returns void language plpgsql security definer set search_path=public as $$
declare cnt int; is_closed boolean;
begin
 select coalesce((data->>'closed')::boolean,false) into is_closed from records where id='settings';
 if is_closed then raise exception 'closed: we are not taking online orders right now'; end if;
 select count(*) into cnt from guest_orders where tbl=t and status='new' and created_at>now()-interval '30 minutes';
 if cnt>=5 then raise exception 'busy: too many pending orders for this table'; end if;
 insert into guest_orders(tbl,name,phone,note,items) values(t,n,p,nt,its);
end;
$$;
grant execute on function place_order(text,text,text,text,jsonb) to anon;

-- Shareable invoice link (i.html?o=<share token>), e.g. for WhatsApp. Looked up
-- by a random unguessable per-order token (not the invoice number, which is
-- short and sequential and must never double as a public lookup key).
create function public_invoice(oid text) returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object(
  'order',(select data from records where kind='order' and not deleted and data->>'tok'=oid order by (data->>'paidAt') desc nulls last limit 1),
  'cfg',coalesce((select data from records where id='settings'),'{}'::jsonb)
 )
$$;
grant execute on function public_invoice(text) to anon;
create index if not exists records_order_tok_idx on records(((data->>'tok'))) where kind='order';

-- Server-issued sequential invoice numbers (avoids per-device numbering,
-- which could collide or gap). Falls back to a local number offline, marked
-- with a trailing '~' and replaced by a real number once back online.
create sequence if not exists invoice_seq start 1;
create function next_invoice_no(prefix text) returns text language plpgsql security definer set search_path=public as $$
declare n bigint; begin
 if me() is null then raise exception 'not authorized'; end if;
 n:=nextval('invoice_seq'); return prefix||'-'||lpad(n::text,6,'0');
end $$;
revoke execute on function next_invoice_no(text) from public;
grant execute on function next_invoice_no(text) to authenticated;

-- Conditional write with optimistic concurrency: rejects (rather than
-- silently overwriting) a write whose `base` no longer matches the current
-- server row, unless `force` is set. The client detects the conflict, makes
-- the conflict visible to staff, then retries once with force=true so a
-- record never gets stuck — this is best-effort conflict *visibility*, not
-- full field-level merge.
create function push_record(rid text, rkind text, rdata jsonb, rdeleted boolean, base timestamptz, force boolean default false) returns jsonb language plpgsql security definer set search_path=public as $$
declare cur timestamptz; conflict boolean:=false; newv timestamptz;
begin
 if me() is null or not(rkind in('order','exp','shift','ing','waste','voidlog') or me()='owner') then
   raise exception 'not authorized';
 end if;
 select updated_at into cur from records where id=rid;
 if cur is null then
   insert into records(id,kind,data,deleted) values(rid,rkind,rdata,rdeleted) returning updated_at into newv;
 elsif force or base is null or cur=base then
   update records set kind=rkind,data=rdata,deleted=rdeleted where id=rid returning updated_at into newv;
 else
   conflict:=true; newv:=cur;
 end if;
 return jsonb_build_object('ok', not conflict,'conflict',conflict,'server_updated_at',newv);
end $$;
revoke execute on function push_record(text,text,jsonb,boolean,timestamptz,boolean) from public;
grant execute on function push_record(text,text,jsonb,boolean,timestamptz,boolean) to authenticated;

-- Public storage bucket for the customer-facing website (site.html): hero,
-- about and gallery photos the owner uploads from Settings, compressed
-- client-side before upload. Publicly readable, owner-only writes.
insert into storage.buckets (id, name, public) values ('site','site', true) on conflict (id) do nothing;
create policy site_public_read on storage.objects for select using (bucket_id='site');
create policy site_owner_write on storage.objects for insert with check (bucket_id='site' and me()='owner');
create policy site_owner_update on storage.objects for update using (bucket_id='site' and me()='owner') with check (bucket_id='site' and me()='owner');
create policy site_owner_delete on storage.objects for delete using (bucket_id='site' and me()='owner');

-- Web Push: lets a device get an order alert even when the app/browser is
-- fully closed, via the OS notification system rather than Realtime (which
-- only works while a tab/PWA is actually running). Each staff device that
-- taps "Enable notifications" (Staff tab) stores its push subscription here;
-- a trigger on new/ready orders (and new self-orders) calls the deployed
-- `send-push` Edge Function, which signs and delivers the push to every
-- subscribed device. The Edge Function holds the VAPID key pair and a
-- shared secret the trigger must present (it has verify_jwt off, since a
-- DB trigger can't carry a user JWT) — see supabase/functions/send-push.
create extension if not exists pg_net;

create table push_subs(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users on delete cascade,endpoint text unique not null,p256dh text not null,auth text not null,created_at timestamptz not null default now());
alter table push_subs enable row level security;
create policy ps_ins on push_subs for insert with check(me() is not null and user_id=auth.uid());
create policy ps_read on push_subs for select using(me() is not null and user_id=auth.uid());
create policy ps_upd on push_subs for update using(me() is not null and user_id=auth.uid()) with check(me() is not null and user_id=auth.uid());
create policy ps_del on push_subs for delete using(me() is not null and user_id=auth.uid());

create function notify_push(title text, body text) returns void language sql as $$
 select net.http_post(
  url:='https://turweopxvskqmbzpblkm.supabase.co/functions/v1/send-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-trigger-secret','ce341201e148ab63e776da0fbdb63ebfe30368d241f27ac4'),
  body:=jsonb_build_object('title',title,'body',body)
 )
$$;

create function notify_order_change() returns trigger language plpgsql as $$
declare kstat_old text; kstat_new text;
begin
 if NEW.kind<>'order' or NEW.deleted then return NEW; end if;
 kstat_new:=NEW.data->>'kstat';
 kstat_old:=case when TG_OP='UPDATE' then OLD.data->>'kstat' else null end;
 if kstat_new is distinct from kstat_old and kstat_new in('new','ready') then
  perform notify_push(
   case kstat_new when 'new' then 'New order' else 'Order ready' end,
   coalesce(NEW.data->>'no','Order')||' · '||coalesce(NEW.data->'cust'->>'name','')
  );
 end if;
 return NEW;
end $$;
create trigger t_notify_order after insert or update on records for each row execute function notify_order_change();

create function notify_guest_order() returns trigger language plpgsql as $$
begin
 if NEW.status='new' then
  perform notify_push('New self-order', coalesce(NEW.name,'A guest')||' via table QR');
 end if;
 return NEW;
end $$;
create trigger t_notify_guest after insert on guest_orders for each row execute function notify_guest_order();
