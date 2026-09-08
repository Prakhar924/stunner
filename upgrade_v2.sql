-- Stunner capability upgrade for an existing Supabase project.
-- Run once in Supabase SQL Editor after the original schema.sql.

alter table public.profiles
  add column if not exists username text,
  add column if not exists dating_intention text not null default 'figuring_out',
  add column if not exists interests jsonb not null default '[]',
  add column if not exists prompt_key text,
  add column if not exists prompt_answer text,
  add column if not exists job_title text,
  add column if not exists education text,
  add column if not exists opening_move text,
  add column if not exists phone_verified boolean not null default false,
  add column if not exists is_test boolean not null default false;

create unique index if not exists profiles_username_unique on public.profiles (lower(username)) where username is not null;

do $$ begin
  alter table public.profiles add constraint profiles_username_format_check check (username is null or username ~ '^[a-z0-9_]{4,24}$');
exception when duplicate_object then null;
end $$;

create or replace function public.resolve_login_username(login_username text) returns text
language sql stable security definer set search_path = public, auth as $$
  select u.email
  from public.profiles p join auth.users u on u.id = p.id
  where lower(p.username) = lower(trim(login_username)) and p.status <> 'banned'
  limit 1;
$$;

do $$ begin
  alter table public.profiles add constraint profiles_dating_intention_check
    check (dating_intention in ('relationship','casual','figuring_out','friendship'));
exception when duplicate_object then null;
end $$;

create or replace function public.protect_profile_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.phone_verified is distinct from new.phone_verified and not is_admin() then
    if not (new.phone_verified and exists (
      select 1 from auth.users where id = auth.uid() and phone_confirmed_at is not null
    )) then
      raise exception 'Phone verification must be confirmed through Supabase Auth';
    end if;
  end if;
  if old.status is distinct from new.status and not is_admin() then
    if not (old.status = 'onboarding' and new.status = 'pending') then
      raise exception 'Not allowed to change account status';
    end if;
  end if;
  return new;
end;
$$;

do $$ begin
  alter table public.profiles add constraint profiles_job_title_length_check check (char_length(job_title) <= 80);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.profiles add constraint profiles_education_length_check check (char_length(education) <= 100);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.profiles add constraint profiles_opening_move_length_check check (char_length(opening_move) <= 160);
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.profiles add constraint profiles_interests_array_check
    check (jsonb_typeof(interests) = 'array');
exception when duplicate_object then null;
end $$;

do $$ begin
  alter table public.profiles add constraint profiles_prompt_answer_length_check
    check (char_length(prompt_answer) <= 240);
exception when duplicate_object then null;
end $$;

drop policy if exists "insert own" on public.profiles;
drop policy if exists "insert own onboarding profile" on public.profiles;
create policy "insert own onboarding profile" on public.profiles
  for insert with check (id = auth.uid() and status = 'onboarding');

drop function if exists public.get_feed(int);
drop function if exists public.get_feed(int, int, int, text);
create or replace function public.get_feed(
  limit_n int default 20,
  min_age int default 18,
  max_age int default 80,
  intention_filter text default null,
  include_test boolean default false
)
returns setof public.profiles
language sql stable security definer set search_path = public as $$
  select p.*
  from profiles p
  join profiles me on me.id = auth.uid()
  where me.status = 'verified'
    and p.status = 'verified'
    and p.id <> me.id
    and (not p.is_test or (include_test and is_admin()))
    and p.city = me.city
    and extract(year from age(current_date, p.dob)) between min_age and max_age
    and (intention_filter is null or p.dating_intention = intention_filter)
    and (me.interested_in = 'everyone'
      or (me.interested_in = 'men' and p.gender = 'man')
      or (me.interested_in = 'women' and p.gender = 'woman'))
    and (p.interested_in = 'everyone'
      or (p.interested_in = 'men' and me.gender = 'man')
      or (p.interested_in = 'women' and me.gender = 'woman'))
    and not exists (select 1 from swipes s where s.swiper = me.id and s.target = p.id)
    and not exists (select 1 from blocks b
      where (b.blocker = me.id and b.blocked = p.id)
         or (b.blocker = p.id and b.blocked = me.id))
  order by random()
  limit limit_n;
$$;
