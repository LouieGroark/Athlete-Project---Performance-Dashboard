-- ============================================================
-- Athlete Project — Performance Dashboard
-- Supabase schema: run this once in the Supabase SQL editor
-- (Project > SQL Editor > New query > paste all of this > Run)
-- ============================================================

-- ---------- 1. profiles ----------
-- One row per user, created automatically on sign-up.
-- Holds their username, their generated programme, and setup status.
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  email text,
  display_name text,
  sport text default 'rugby',
  programme_id uuid,
  programme jsonb,                       -- the personal, generated weeks/fixtures (account setup)
  setup_complete boolean default false,  -- false until the account-setup form has been submitted
  role text default 'athlete',           -- 'athlete' or 'coach'
  created_at timestamptz default now()
);

alter table profiles enable row level security;

create policy "profiles: select own"
  on profiles for select
  using (auth.uid() = id);

create policy "profiles: update own"
  on profiles for update
  using (auth.uid() = id);

create policy "profiles: insert own"
  on profiles for insert
  with check (auth.uid() = id);

-- Auto-create a profile row whenever someone signs up.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, email, sport)
  values (new.id, new.raw_user_meta_data->>'username', new.email, coalesce(new.raw_user_meta_data->>'sport', 'rugby'));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- 1b. username login ----------
-- The dashboard's login page only asks for a username + password, but
-- Supabase Auth itself is email-based (each account uses a placeholder
-- email built from the username, e.g. jsmith@users.athlete-project.local).
-- This function safely maps a username back to its email so the client can
-- sign in with supa.auth.signInWithPassword. security definer lets it read
-- the email column despite RLS, but it returns ONLY the email — nothing
-- else about the account is exposed.
create or replace function get_email_by_username(uname text)
returns text as $$
  select email from profiles where lower(username) = lower(uname) limit 1;
$$ language sql security definer stable;

grant execute on function get_email_by_username(text) to anon, authenticated;

-- IMPORTANT: since these accounts don't have real email addresses, go to
-- Supabase > Authentication > Providers > Email and turn OFF "Confirm
-- email" — a confirmation email can never reach a placeholder address.


-- ---------- 2. programmes ----------
-- Shared reference library, NOT user-owned. One row per sport/programme.
-- "data" holds the same shape as the dashboard's current app-data JSON
-- (season plan, weekly sessions, fixtures, testing battery, exercise bank).
create table if not exists programmes (
  id uuid primary key default gen_random_uuid(),
  sport text not null,
  name text not null,
  is_default boolean default false,
  data jsonb not null,
  created_at timestamptz default now()
);

alter table programmes enable row level security;

-- Any signed-in user can read the programme library (it's not private data).
create policy "programmes: read for signed-in users"
  on programmes for select
  using (auth.role() = 'authenticated');

-- No insert/update/delete policy is defined on purpose: only you, editing
-- from the Supabase table view (or using the service-role key), can add or
-- change programmes. Regular users can never modify the library.

-- ---------- 3. user_data ----------
-- Generic private key/value store. Each row is one of the dashboard's
-- existing localStorage keys (brfc_completed, brfc_testing,
-- brfc_nutrition_meals, brfc_wellbeing, etc.) scoped to one user.
create table if not exists user_data (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value jsonb not null,
  updated_at timestamptz default now(),
  unique (user_id, key)
);

alter table user_data enable row level security;

create policy "user_data: select own"
  on user_data for select
  using (auth.uid() = user_id);

create policy "user_data: insert own"
  on user_data for insert
  with check (auth.uid() = user_id);

create policy "user_data: update own"
  on user_data for update
  using (auth.uid() = user_id);

create policy "user_data: delete own"
  on user_data for delete
  using (auth.uid() = user_id);

-- ============================================================
-- Seed: turn the dashboard's current hardcoded demo data into the
-- first programme row ("Rugby — Demo Programme"), so existing users
-- have something to load immediately. Paste the JSON currently inside
-- the dashboard's <script id="app-data"> tag as the value below, or
-- run this later from the Supabase table editor instead.
-- ============================================================
-- insert into programmes (sport, name, is_default, data)
-- values ('rugby', 'Rugby — Demo Programme', true, '{ ...app-data json... }'::jsonb);
