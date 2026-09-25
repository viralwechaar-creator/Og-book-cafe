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
create policy r_ins on records for insert with check(me() is not null and (kind in('order','exp') or me()='owner'));
create policy r_upd on records for update using(me() is not null and (kind in('order','exp') or me()='owner')) with check(me() is not null and (kind in('order','exp') or me()='owner'));
alter publication supabase_realtime add table records;
-- Promote a user:  update profiles set role='manager' where email='someone@example.com';
