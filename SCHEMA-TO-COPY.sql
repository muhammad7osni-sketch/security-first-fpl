-- SquadIQ database schema
-- Copy ALL of this and paste in Supabase SQL Editor
-- Then click RUN

create extension if not exists "pgcrypto";

-- ============================================================
-- Identity
-- ============================================================

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  email text not null unique,
  display_name text,
  fpl_manager_id integer,
  created_at timestamptz not null default now()
);

create table if not exists user_preferences (
  user_id uuid primary key references users(id) on delete cascade,
  notification_settings jsonb not null default '{}'::jsonb,
  locked_players integer[] not null default '{}',
  ai_tone text not null default 'concise',
  updated_at timestamptz not null default now()
);

-- ============================================================
-- Fantasy data cache
-- ============================================================

create table if not exists clubs (
  id integer primary key,
  name text not null,
  short_name text not null
);

create table if not exists gameweeks (
  id integer primary key,
  number integer not null,
  deadline_time timestamptz not null,
  is_current boolean not null default false,
  finished boolean not null default false
);

create table if not exists players (
  id integer primary key,
  name text not null,
  club_id integer not null references clubs(id),
  position text not null check (position in ('goalkeeper','defender','midfielder','forward')),
  price_tenths integer not null,
  ownership_percent numeric(5,2) not null default 0,
  form numeric(5,2) not null default 0,
  status text not null default 'a',
  updated_at timestamptz not null default now()
);

create table if not exists fixtures (
  id integer primary key,
  gameweek_id integer references gameweeks(id),
  home_club_id integer not null references clubs(id),
  away_club_id integer not null references clubs(id),
  home_difficulty smallint not null default 3,
  away_difficulty smallint not null default 3,
  kickoff_time timestamptz,
  finished boolean not null default false
);

create table if not exists player_statistics (
  player_id integer not null references players(id),
  gameweek_id integer not null references gameweeks(id),
  minutes integer not null default 0,
  points integer not null default 0,
  xg numeric(5,2),
  xa numeric(5,2),
  primary key (player_id, gameweek_id)
);

create table if not exists injuries (
  id uuid primary key default gen_random_uuid(),
  player_id integer not null references players(id),
  status text not null,
  source text not null,
  detail text,
  updated_at timestamptz not null default now()
);

create table if not exists news (
  id uuid primary key default gen_random_uuid(),
  player_id integer references players(id),
  content_summary text not null,
  source text not null,
  published_at timestamptz not null default now()
);

-- ============================================================
-- User's fantasy team + decisions
-- ============================================================

create table if not exists fantasy_teams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references users(id) on delete cascade,
  budget_tenths integer not null default 1000,
  chips_used text[] not null default '{}',
  current_squad_snapshot jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists transfers (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references fantasy_teams(id) on delete cascade,
  player_out integer not null references players(id),
  player_in integer not null references players(id),
  gameweek_id integer not null references gameweeks(id),
  is_hit boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists recommendations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references fantasy_teams(id) on delete cascade,
  type text not null check (type in ('captain','transfer','chip','differential')),
  payload_json jsonb not null,
  confidence_score numeric(5,2) not null check (confidence_score between 0 and 100),
  created_at timestamptz not null default now()
);

create table if not exists emergency_coach_events (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references fantasy_teams(id) on delete cascade,
  gameweek_id integer not null references gameweeks(id),
  detected_issues_json jsonb not null,
  proposed_plan_json jsonb not null,
  user_action text not null default 'pending' check (
    user_action in ('pending','accepted','dismissed','applied_externally')
  ),
  created_at timestamptz not null default now()
);

create table if not exists audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id),
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================
-- AI Assistant
-- ============================================================

create table if not exists ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  started_at timestamptz not null default now()
);

create table if not exists ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references ai_conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant','tool')),
  content text not null,
  tool_calls_json jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Coins / Wallet / Monetization
-- ============================================================

create table if not exists wallets (
  user_id uuid primary key references users(id) on delete cascade,
  coin_balance bigint not null default 0 check (coin_balance >= 0)
);

create table if not exists coin_transactions (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references wallets(user_id),
  amount bigint not null,
  type text not null,
  reference_id text,
  created_at timestamptz not null default now()
);

create table if not exists store_products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price_coins integer,
  price_money_cents integer,
  feature_key text not null unique
);

create table if not exists purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  product_id uuid not null references store_products(id),
  receipt_ref text not null,
  status text not null default 'pending' check (status in ('pending','validated','refunded','failed')),
  created_at timestamptz not null default now()
);

create table if not exists subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  tier text not null check (tier in ('free','premium','pro')),
  status text not null check (status in ('active','canceled','expired','trialing')),
  renewal_date date,
  created_at timestamptz not null default now()
);

create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null,
  priority text not null check (priority in ('urgent','high','medium','low')),
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Indexes
-- ============================================================

create index if not exists idx_players_club_position on players (club_id, position);
create index if not exists idx_fixtures_gameweek on fixtures (gameweek_id);
create index if not exists idx_coin_transactions_wallet_created on coin_transactions (wallet_id, created_at);
create index if not exists idx_ai_messages_conversation_created on ai_messages (conversation_id, created_at);
create index if not exists idx_recommendations_team_created on recommendations (team_id, created_at desc);
create index if not exists idx_emergency_events_team_gw on emergency_coach_events (team_id, gameweek_id);

-- ============================================================
-- Row-Level Security
-- ============================================================

alter table users enable row level security;
alter table user_preferences enable row level security;
alter table fantasy_teams enable row level security;
alter table transfers enable row level security;
alter table recommendations enable row level security;
alter table emergency_coach_events enable row level security;
alter table ai_conversations enable row level security;
alter table ai_messages enable row level security;
alter table wallets enable row level security;
alter table coin_transactions enable row level security;
alter table purchases enable row level security;
alter table subscriptions enable row level security;
alter table notifications enable row level security;
alter table audit_log enable row level security;

-- Drop existing policies if they exist
drop policy if exists "users_select_own" on users;
drop policy if exists "users_insert_own" on users;
drop policy if exists "users_update_own" on users;
drop policy if exists "user_preferences_owner" on user_preferences;
drop policy if exists "fantasy_teams_owner" on fantasy_teams;
drop policy if exists "wallets_owner_select" on wallets;
drop policy if exists "coin_transactions_owner_select" on coin_transactions;

-- Create policies
create policy "users_select_own" on users
  for select using (auth_user_id = auth.uid());

create policy "users_insert_own" on users
  for insert with check (auth_user_id = auth.uid());

create policy "users_update_own" on users
  for update using (auth_user_id = auth.uid());

create policy "user_preferences_owner" on user_preferences
  for all using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "fantasy_teams_owner" on fantasy_teams
  for all using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "wallets_owner_select" on wallets
  for select using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "coin_transactions_owner_select" on coin_transactions
  for select using (
    wallet_id in (select id from users where auth_user_id = auth.uid())
  );

-- Grant access to public reference tables
grant select on clubs, players, fixtures, gameweeks, injuries, news, store_products
  to anon, authenticated;
