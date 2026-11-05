-- Accounts, email codes and login sessions for BaKhi_API. Runs first.
-- The API connects as the database owner and, for every request, switches
-- to role `authenticated` (signed-in player) or `anon` (no token) and puts
-- the player's id in request.jwt.claim.sub. Row level security and the game
-- functions read it through auth.uid().
begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
-- The API's own login must be allowed to "set role" to both.
grant anon, authenticated to current_user;

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(email) and char_length(email) between 3 and 254),
  -- BCrypt hash; the password itself is never stored.
  password_hash text not null,
  -- {"display_name": "..."}; copied into public.profiles on confirmation.
  raw_user_meta_data jsonb not null default '{}',
  email_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists users_email on auth.users(email);

-- One active code per address and purpose. Only its SHA-256 is stored.
create table if not exists auth.email_codes (
  email text not null,
  purpose text not null check (purpose in ('signup', 'recovery')),
  code_hash text not null,
  attempts integer not null default 0,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (email, purpose)
);

-- Long-lived tokens that buy a new access token. Rotated on every use.
create table if not exists auth.refresh_tokens (
  token_hash text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists refresh_tokens_user on auth.refresh_tokens(user_id);

create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

-- Players reach auth.uid() only; accounts and tokens stay with the API.
grant usage on schema auth to anon, authenticated;
revoke all on all tables in schema auth from public, anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

commit;
