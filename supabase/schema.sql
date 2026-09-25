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
create policy r_ins on records for insert with check(me() is not null and (kind in('order','exp','shift','ing','waste') or me()='owner'));
create policy r_upd on records for update using(me() is not null and (kind in('order','exp','shift','ing','waste') or me()='owner')) with check(me() is not null and (kind in('order','exp','shift','ing','waste') or me()='owner'));
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
declare cnt int;
begin
 select count(*) into cnt from guest_orders where tbl=t and status='new' and created_at>now()-interval '30 minutes';
 if cnt>=5 then raise exception 'busy: too many pending orders for this table'; end if;
 insert into guest_orders(tbl,name,phone,note,items) values(t,n,p,nt,its);
end;
$$;
grant execute on function place_order(text,text,text,text,jsonb) to anon;

-- Shareable invoice link (i.html?o=<invoice number>), e.g. for WhatsApp. Looked
-- up by the short invoice number rather than the order's internal id, for a
-- shorter URL.
create function public_invoice(oid text) returns jsonb language sql security definer stable set search_path=public as $$
 select jsonb_build_object(
  'order',(select data from records where kind='order' and not deleted and data->>'no'=oid order by (data->>'paidAt') desc nulls last limit 1),
  'cfg',coalesce((select data from records where id='settings'),'{}'::jsonb)
 )
$$;
grant execute on function public_invoice(text) to anon;
create index if not exists records_order_no_idx on records(((data->>'no'))) where kind='order';
