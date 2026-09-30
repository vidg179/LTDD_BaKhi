-- Run once in a new Supabase project. No service-role key belongs in Flutter.
begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 40),
  created_at timestamptz not null default now()
);
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values (new.id,
    case when char_length(trim(coalesce(new.raw_user_meta_data->>'display_name', ''))) >= 2
      then left(trim(new.raw_user_meta_data->>'display_name'), 40) else 'Người chơi' end);
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.game_score(game text, difficulty text, seconds integer, mistakes integer, outcome text)
returns integer language sql immutable set search_path = '' as $$
  select case when outcome <> 'win' then 0 else greatest(100,
    (case game when 'sudoku' then 2000 when 'puzzle' then 1500 else 1000 end) *
    (case difficulty when 'hard' then 3 when 'medium' then 2 else 1 end) - seconds * 2 - mistakes * 100) end;
$$;

create table public.game_results (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null check (game in ('sudoku', 'puzzle', 'caro', 'rubik')),
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard')),
  seconds integer not null check (seconds between 0 and 604800),
  mistakes integer not null check (mistakes between 0 and 10000),
  moves integer not null check (moves between 0 and 1000000),
  outcome text not null check (outcome in ('win', 'loss', 'draw')),
  score integer generated always as (public.game_score(game, difficulty, seconds, mistakes, outcome)) stored,
  played_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index game_results_rank on public.game_results(game, difficulty, score desc);
create index game_results_owner on public.game_results(user_id);

create view public.leaderboard with (security_invoker = true) as
  select distinct on (r.game, r.difficulty, r.user_id)
    r.user_id, p.display_name, r.game, r.difficulty, r.score, r.seconds, r.mistakes
  from public.game_results r join public.profiles p on p.id = r.user_id
  where r.outcome = 'win'
  order by r.game, r.difficulty, r.user_id, r.score desc, r.seconds, r.mistakes, r.created_at;

create table public.messages (
  id uuid primary key,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  room_key text generated always as (least(sender_id::text, recipient_id::text) || ':' || greatest(sender_id::text, recipient_id::text)) stored,
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index messages_room on public.messages(room_key, created_at desc);
create index messages_recipient on public.messages(recipient_id);

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles(id) on delete cascade,
  opponent_id uuid not null references public.profiles(id) on delete cascade,
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard')),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'completed')),
  winner_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (challenger_id <> opponent_id)
);
create index challenges_challenger on public.challenges(challenger_id);
create index challenges_opponent on public.challenges(opponent_id);
-- Never readable by clients: start_challenge reveals the board after starting the timer.
create table public.challenge_puzzles (
  challenge_id uuid primary key references public.challenges(id) on delete cascade,
  givens integer[] not null check (array_length(givens, 1) = 81)
);
create table public.challenge_runs (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  seconds integer,
  mistakes integer,
  score integer,
  unique(challenge_id, user_id)
);

alter table public.profiles enable row level security;
alter table public.game_results enable row level security;
alter table public.messages enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_puzzles enable row level security;
alter table public.challenge_runs enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (true);
create policy results_read on public.game_results for select to authenticated using (true);
create policy results_insert on public.game_results for insert to authenticated with check (user_id = (select auth.uid()));
create policy messages_read on public.messages for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = (select auth.uid()));
create policy challenges_read on public.challenges for select to authenticated
  using ((select auth.uid()) in (challenger_id, opponent_id));
create policy runs_read on public.challenge_runs for select to authenticated using (
  exists (select 1 from public.challenges c where c.id = challenge_id and (select auth.uid()) in (c.challenger_id, c.opponent_id))
);

create function public.create_challenge(opponent_id uuid, level text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); cid uuid; board text; values_array integer[];
  digit_offset integer := floor(random() * 9)::integer;
begin
  if uid is null or uid = $1 or not exists(select 1 from public.profiles where id = $1) then
    raise exception 'Người nhận không hợp lệ.';
  end if;
  if level not in ('easy', 'medium', 'hard') or level is null then raise exception 'Độ khó không hợp lệ.'; end if;
  if (select count(*) from public.challenges c where c.challenger_id = uid and c.status = 'pending') >= 20 then
    raise exception 'Bạn đang có quá nhiều lời mời chưa được trả lời.';
  end if;
  -- Curated unique-solution boards; digit permutation keeps uniqueness.
  board := case level
    when 'easy' then '000260701680070090190004500820100040004602900050003028009300074040050036703018000'
    when 'medium' then '530070000600195000098000060800060003400803001700020006060000280000419005000080079'
    else '000000010400000000020000000000050407008000300001090000300400200050100000000806000' end;
  select array_agg(case when substr(board, i, 1) = '0' then 0
    else ((substr(board, i, 1)::integer - 1 + digit_offset) % 9) + 1 end order by i)
    into values_array from generate_series(1,81) i;
  insert into public.challenges(challenger_id, opponent_id, difficulty) values(uid, $1, level) returning id into cid;
  insert into public.challenge_puzzles(challenge_id, givens) values(cid, values_array);
  return cid;
end;
$$;

create function public.respond_challenge(challenge_id uuid, accept_invite boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.challenges c set status = case when accept_invite then 'accepted' else 'declined' end
    where c.id = $1 and c.opponent_id = auth.uid() and c.status = 'pending';
  if not found then raise exception 'Lời mời không còn chờ hoặc bạn không phải người nhận.'; end if;
end;
$$;

create function public.start_challenge(challenge_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.challenges; run public.challenge_runs; puzzle integer[];
begin
  select * into c from public.challenges where id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id) or c.status <> 'accepted' then
    raise exception 'Thách đấu chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  insert into public.challenge_runs(challenge_id, user_id) values($1, auth.uid()) on conflict do nothing;
  select * into run from public.challenge_runs r where r.challenge_id = $1 and r.user_id = auth.uid();
  if run.finished_at is not null then raise exception 'Bạn đã hoàn thành thách đấu này.'; end if;
  select givens into puzzle from public.challenge_puzzles p where p.challenge_id = $1;
  return jsonb_build_object('givens', puzzle, 'started_at', run.started_at, 'difficulty', c.difficulty,
    'server_now', clock_timestamp());
end;
$$;

create function public.submit_challenge(challenge_id uuid, answer integer[], error_count integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges; run public.challenge_runs; puzzle integer[]; elapsed integer; points integer;
  a public.challenge_runs; b public.challenge_runs; winner uuid;
begin
  select * into c from public.challenges where id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id) then
    raise exception 'Bạn không có quyền nộp kết quả.';
  end if;
  select * into run from public.challenge_runs r where r.challenge_id = $1 and r.user_id = auth.uid() for update;
  if not found then raise exception 'Bạn chưa bắt đầu thách đấu.'; end if;
  -- Idempotent retry after a lost network response.
  if run.finished_at is not null then return jsonb_build_object('score', run.score, 'seconds', run.seconds); end if;
  if c.status <> 'accepted' then raise exception 'Thách đấu không còn hoạt động.'; end if;
  if error_count is null or error_count < 0 or error_count > 10000 or
    answer is null or cardinality(answer) <> 81 or array_ndims(answer) <> 1 or array_lower(answer, 1) <> 1 or
    exists(select 1 from unnest(answer) v where v is null or v not between 1 and 9) then
    raise exception 'Dữ liệu kết quả không hợp lệ.';
  end if;
  select givens into puzzle from public.challenge_puzzles p where p.challenge_id = $1;
  for i in 1..81 loop
    if puzzle[i] <> 0 and puzzle[i] <> answer[i] then raise exception 'Bạn đã thay đổi ô gợi ý.'; end if;
  end loop;
  for r in 0..8 loop
    if (select count(distinct answer[r*9+x]) from generate_series(1,9) x) <> 9 or
       (select count(distinct answer[x*9+r+1]) from generate_series(0,8) x) <> 9 or
       (select count(distinct answer[(r/3*3+x/3)*9+(r%3*3+x%3)+1]) from generate_series(0,8) x) <> 9 then
      raise exception 'Bảng Sudoku chưa đúng.';
    end if;
  end loop;
  elapsed := greatest(0, least(604800, floor(extract(epoch from (clock_timestamp() - run.started_at)))::integer));
  points := public.game_score('sudoku', c.difficulty, elapsed, error_count, 'win');
  update public.challenge_runs r set finished_at = clock_timestamp(), seconds = elapsed, mistakes = error_count, score = points
    where r.id = run.id;
  select * into a from public.challenge_runs r where r.challenge_id = $1 and r.user_id = c.challenger_id;
  select * into b from public.challenge_runs r where r.challenge_id = $1 and r.user_id = c.opponent_id;
  if a.finished_at is not null and b.finished_at is not null then
    winner := case when (a.score, -a.seconds, -a.mistakes) > (b.score, -b.seconds, -b.mistakes) then a.user_id
      when (a.score, -a.seconds, -a.mistakes) < (b.score, -b.seconds, -b.mistakes) then b.user_id else null end;
    update public.challenges set status = 'completed', winner_id = winner where id = $1;
  end if;
  return jsonb_build_object('score', points, 'seconds', elapsed);
end;
$$;

revoke all on public.profiles, public.game_results, public.messages, public.challenges, public.challenge_puzzles, public.challenge_runs, public.leaderboard from anon, authenticated;
grant select on public.profiles, public.game_results, public.messages, public.challenges, public.challenge_runs, public.leaderboard to authenticated;
grant insert on public.game_results, public.messages to authenticated;
revoke all on function public.handle_new_user() from public;
revoke all on function public.create_challenge(uuid,text), public.respond_challenge(uuid,boolean), public.start_challenge(uuid), public.submit_challenge(uuid,integer[],integer) from public;
grant execute on function public.create_challenge(uuid,text), public.respond_challenge(uuid,boolean), public.start_challenge(uuid), public.submit_challenge(uuid,integer[],integer) to authenticated;

alter publication supabase_realtime add table public.messages, public.challenges;
commit;
