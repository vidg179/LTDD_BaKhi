-- Run after 004_caro_vietnam_rule.sql. Safe to run again.
-- Clients can no longer insert into game_results directly. A result reaches the
-- online leaderboard only when it goes through submit_game_result with a
-- session that the server started (start_game_session) and passes plausibility
-- checks. Results without a valid session are stored but never ranked.
-- Rows that existed before this migration cannot be verified and stay unranked.
begin;

create table if not exists public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null check (game in ('sudoku', 'puzzle', 'caro', 'rubik')),
  difficulty text not null check (difficulty in ('easy', 'medium', 'hard')),
  started_at timestamptz not null default clock_timestamp(),
  used_at timestamptz
);
create index if not exists game_sessions_user on public.game_sessions(user_id, started_at desc);
-- Never readable or writable by clients; only the functions below touch it.
alter table public.game_sessions enable row level security;
revoke all on public.game_sessions from anon, authenticated;

alter table public.game_results
  add column if not exists session_id uuid unique references public.game_sessions(id) on delete set null,
  add column if not exists ranked boolean not null default false;

drop policy if exists results_insert on public.game_results;
revoke insert, update, delete on public.game_results from anon, authenticated;

-- Fastest believable solve. Rubik counts each guided step (moves = steps).
create or replace function public.min_game_seconds(game text, difficulty text, moves integer)
returns integer language sql immutable set search_path = '' as $$
  select case game
    when 'sudoku' then case difficulty when 'hard' then 120 when 'medium' then 90 else 60 end
    when 'puzzle' then case difficulty when 'hard' then 30 when 'medium' then 15 else 5 end
    when 'caro' then 5
    else 2 * greatest(moves, 1) end;
$$;

-- Sudoku must fill every empty cell (the app generates 42/34/28 clues);
-- a Caro win needs five own stones, so at least 9 stones on the board.
create or replace function public.min_game_moves(game text, difficulty text)
returns integer language sql immutable set search_path = '' as $$
  select case game
    when 'sudoku' then case difficulty when 'hard' then 53 when 'medium' then 47 else 39 end
    when 'caro' then 9
    else 1 end;
$$;

create or replace function public.start_game_session(game_name text, level text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sid uuid;
begin
  if uid is null then raise exception 'Cần đăng nhập để được xếp hạng.'; end if;
  if game_name is null or game_name not in ('sudoku', 'puzzle', 'caro', 'rubik')
     or level is null or level not in ('easy', 'medium', 'hard') then
    raise exception 'Trò chơi hoặc độ khó không hợp lệ.';
  end if;
  if (select count(*) from public.game_sessions s
      where s.user_id = uid and s.started_at > clock_timestamp() - interval '1 hour') >= 120 then
    raise exception 'Bạn bắt đầu quá nhiều ván trong thời gian ngắn. Hãy thử lại sau.';
  end if;
  insert into public.game_sessions(user_id, game, difficulty) values (uid, game_name, level)
    returning id into sid;
  return jsonb_build_object('id', sid);
end;
$$;

create or replace function public.submit_game_result(
  result_id uuid, game_session uuid, game_name text, level text,
  seconds_taken integer, mistake_count integer, move_count integer,
  result_outcome text, played timestamptz
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); saved public.game_results; s public.game_sessions;
  linked uuid; is_ranked boolean := false; elapsed numeric;
begin
  if uid is null then raise exception 'Cần đăng nhập để đồng bộ kết quả.'; end if;
  -- Idempotent retry after a lost network response.
  select * into saved from public.game_results r where r.id = result_id;
  if found then
    if saved.user_id <> uid then raise exception 'Mã kết quả không hợp lệ.'; end if;
    return jsonb_build_object('score', saved.score, 'ranked', saved.ranked);
  end if;
  if result_id is null
     or game_name is null or game_name not in ('sudoku', 'puzzle', 'caro', 'rubik')
     or level is null or level not in ('easy', 'medium', 'hard')
     or result_outcome is null or result_outcome not in ('win', 'loss', 'draw')
     or seconds_taken is null or seconds_taken not between 0 and 604800
     or mistake_count is null or mistake_count not between 0 and 10000
     or move_count is null or move_count not between 0 and 1000000 then
    raise exception 'Dữ liệu kết quả không hợp lệ.';
  end if;

  if game_session is not null then
    select * into s from public.game_sessions gs
      where gs.id = game_session and gs.user_id = uid for update;
    -- A session belongs to one result only; reusing it gives an unranked row.
    if found and s.used_at is null then
      linked := s.id;
      update public.game_sessions gs set used_at = clock_timestamp() where gs.id = s.id;
      elapsed := extract(epoch from clock_timestamp() - s.started_at);
      -- Paused time is excluded on the device, so the claimed time may be
      -- shorter than the server's, never longer (30 s covers network delay).
      is_ranked := result_outcome = 'win'
        and s.game = game_name and s.difficulty = level
        and elapsed <= 604800
        and seconds_taken <= elapsed + 30
        and seconds_taken >= public.min_game_seconds(game_name, level, move_count)
        and move_count >= public.min_game_moves(game_name, level)
        and mistake_count <= move_count;
    end if;
  end if;

  insert into public.game_results(id, user_id, game, difficulty, seconds, mistakes, moves,
      outcome, played_at, session_id, ranked)
    values (result_id, uid, game_name, level, seconds_taken, mistake_count, move_count,
      result_outcome, least(coalesce(played, clock_timestamp()), clock_timestamp()), linked, is_ranked)
    returning * into saved;
  return jsonb_build_object('score', saved.score, 'ranked', saved.ranked);
end;
$$;

-- Same columns as in 010 (achieved_at last), so running this file again
-- after 010 does not fail with "cannot drop columns from view".
create or replace view public.leaderboard with (security_invoker = true) as
  select distinct on (r.game, r.difficulty, r.user_id)
    r.user_id, p.display_name, r.game, r.difficulty, r.score, r.seconds, r.mistakes,
    r.created_at as achieved_at
  from public.game_results r join public.profiles p on p.id = r.user_id
  where r.outcome = 'win' and r.ranked
  order by r.game, r.difficulty, r.user_id, r.score desc, r.seconds, r.mistakes, r.created_at;

revoke all on function public.min_game_seconds(text, text, integer), public.min_game_moves(text, text),
  public.start_game_session(text, text),
  public.submit_game_result(uuid, uuid, text, text, integer, integer, integer, text, timestamptz)
  from public, anon;
grant execute on function public.start_game_session(text, text),
  public.submit_game_result(uuid, uuid, text, text, integer, integer, integer, text, timestamptz)
  to authenticated;

commit;
