-- ============================================================
-- ASLI — Supabase schema
-- Run this whole file in Supabase: SQL Editor → New query → Run
-- ============================================================

-- ---------- PROFILES ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  dob date check (dob <= (current_date - interval '18 years')),
  gender text check (gender in ('man','woman','nonbinary')),
  interested_in text check (interested_in in ('men','women','everyone')),
  city text not null default 'Delhi',
  bio text check (char_length(bio) <= 500),
  job_title text check (char_length(job_title) <= 80),
  education text check (char_length(education) <= 100),
  dating_intention text not null default 'figuring_out'
    check (dating_intention in ('relationship','casual','figuring_out','friendship')),
  interests jsonb not null default '[]' check (jsonb_typeof(interests) = 'array'),
  prompt_key text,
  prompt_answer text check (char_length(prompt_answer) <= 240),
  opening_move text check (char_length(opening_move) <= 160),
  is_test boolean not null default false,
  photos jsonb not null default '[]',
  status text not null default 'onboarding'
    check (status in ('onboarding','pending','verified','banned')),
  verification_code text,
  verification_selfie text,
  created_at timestamptz not null default now()
);

-- ---------- ADMINS ----------
create table public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admin_users where user_id = auth.uid());
$$;

-- ---------- SWIPES ----------
create table public.swipes (
  swiper uuid not null references public.profiles(id) on delete cascade,
  target uuid not null references public.profiles(id) on delete cascade,
  liked boolean not null,
  created_at timestamptz not null default now(),
  primary key (swiper, target),
  check (swiper <> target)
);

-- ---------- MATCHES ----------
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_a, user_b),
  check (user_a < user_b)
);

-- Mutual like → match (runs server-side, can't be faked from the client)
create or replace function public.handle_mutual_like() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.liked and exists (
    select 1 from swipes
    where swiper = new.target and target = new.swiper and liked
  ) then
    insert into matches (user_a, user_b)
    values (least(new.swiper, new.target), greatest(new.swiper, new.target))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger on_swipe_insert
after insert on public.swipes
for each row execute function public.handle_mutual_like();

-- ---------- MESSAGES ----------
create table public.messages (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches(id) on delete cascade,
  sender uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

-- ---------- BLOCKS ----------
create table public.blocks (
  blocker uuid not null references public.profiles(id) on delete cascade,
  blocked uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

-- ---------- REPORTS ----------
create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references public.profiles(id) on delete cascade,
  reported uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at timestamptz not null default now()
);

-- Auto-hide: 3 open reports from different people → back to pending (hidden) for review
create or replace function public.auto_hide_reported() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(distinct reporter) from reports
      where reported = new.reported and status = 'open') >= 3 then
    update profiles set status = 'pending'
    where id = new.reported and status = 'verified';
  end if;
  return new;
end;
$$;

create trigger on_report_insert
after insert on public.reports
for each row execute function public.auto_hide_reported();

-- ---------- STATUS PROTECTION ----------
-- Users may only move themselves onboarding → pending (submitting verification).
-- Every other status change is admin-only.
create or replace function public.protect_profile_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status is distinct from new.status and not is_admin() then
    if not (old.status = 'onboarding' and new.status = 'pending') then
      raise exception 'Not allowed to change account status';
    end if;
  end if;
  return new;
end;
$$;

create trigger protect_status
before update on public.profiles
for each row execute function public.protect_profile_status();

-- ---------- FEED ----------
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
      or (me.interested_in = 'men'   and p.gender = 'man')
      or (me.interested_in = 'women' and p.gender = 'woman'))
    and (p.interested_in = 'everyone'
      or (p.interested_in = 'men'   and me.gender = 'man')
      or (p.interested_in = 'women' and me.gender = 'woman'))
    and not exists (select 1 from swipes s
                    where s.swiper = me.id and s.target = p.id)
    and not exists (select 1 from blocks b
                    where (b.blocker = me.id and b.blocked = p.id)
                       or (b.blocker = p.id and b.blocked = me.id))
  order by random()
  limit limit_n;
$$;

-- ---------- ROW LEVEL SECURITY ----------
alter table public.profiles    enable row level security;
alter table public.admin_users enable row level security;
alter table public.swipes      enable row level security;
alter table public.matches     enable row level security;
alter table public.messages    enable row level security;
alter table public.blocks      enable row level security;
alter table public.reports     enable row level security;

-- profiles
create policy "read own, verified, or admin" on public.profiles
  for select using (id = auth.uid() or status = 'verified' or is_admin());
create policy "insert own onboarding profile" on public.profiles
  for insert with check (id = auth.uid() and status = 'onboarding');
create policy "update own or admin" on public.profiles
  for update using (id = auth.uid() or is_admin());

-- admin_users
create policy "admins read admin list" on public.admin_users
  for select using (is_admin());

-- swipes
create policy "swipe as self when verified" on public.swipes
  for insert with check (
    swiper = auth.uid()
    and exists (select 1 from profiles where id = auth.uid() and status = 'verified')
  );
create policy "read own swipes" on public.swipes
  for select using (swiper = auth.uid());

-- matches
create policy "members read matches" on public.matches
  for select using (auth.uid() in (user_a, user_b));

-- messages
create policy "members read messages" on public.messages
  for select using (exists (
    select 1 from matches m
    where m.id = match_id and auth.uid() in (m.user_a, m.user_b)
  ));
create policy "members send messages" on public.messages
  for insert with check (
    sender = auth.uid()
    and exists (select 1 from profiles where id = auth.uid() and status = 'verified')
    and exists (select 1 from matches m
                where m.id = match_id and auth.uid() in (m.user_a, m.user_b))
    and not exists (select 1 from blocks b
                    join matches m on m.id = match_id
                    where (b.blocker = m.user_a and b.blocked = m.user_b)
                       or (b.blocker = m.user_b and b.blocked = m.user_a))
  );

-- blocks
create policy "block as self" on public.blocks
  for insert with check (blocker = auth.uid());
create policy "read own blocks" on public.blocks
  for select using (blocker = auth.uid());

-- reports
create policy "report as self" on public.reports
  for insert with check (reporter = auth.uid());
create policy "admins read reports" on public.reports
  for select using (is_admin());
create policy "admins update reports" on public.reports
  for update using (is_admin());

-- ---------- REALTIME ----------
alter publication supabase_realtime add table public.messages;

-- ---------- STORAGE ----------
-- Public bucket for profile photos, private bucket for verification selfies
insert into storage.buckets (id, name, public) values ('photos', 'photos', true);
insert into storage.buckets (id, name, public) values ('verification', 'verification', false);

create policy "users upload own photos" on storage.objects
  for insert with check (
    bucket_id = 'photos'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "anyone views photos" on storage.objects
  for select using (bucket_id = 'photos');
create policy "users delete own photos" on storage.objects
  for delete using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users upload own selfie" on storage.objects
  for insert with check (
    bucket_id = 'verification'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "admins view selfies" on storage.objects
  for select using (bucket_id = 'verification' and public.is_admin());

-- ============================================================
-- AFTER RUNNING THIS FILE:
-- 1. Sign up in the app with the email you want as admin.
-- 2. Find your user id:   select id, email from auth.users;
-- 3. Make yourself admin: insert into admin_users values ('YOUR-USER-ID');
-- ============================================================
