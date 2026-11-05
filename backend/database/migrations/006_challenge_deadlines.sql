-- Run after 005_verified_results.sql. Safe to run again.
-- Challenges can no longer hang forever:
--   * a pending invite expires 24 hours after it was sent;
--   * an accepted challenge must be played within 24 hours: in Sudoku whoever
--     submitted wins (nobody: draw); in Caro a player who never came to the
--     board loses (nobody came: draw);
--   * online Caro gives 60 seconds per move once both players have joined;
--     the player who runs out of time loses;
--   * either player can resign.
-- No scheduler is needed: deadlines are settled whenever a participant calls
-- a challenge function, and the waiting player's app calls
-- check_challenge_timeout when the move clock runs out.
begin;

alter table public.challenges
  add column if not exists expires_at timestamptz not null default now() + interval '24 hours',
  add column if not exists deadline_at timestamptz,
  add column if not exists end_reason text check (end_reason in ('timeout', 'resign'));
alter table public.caro_matches
  add column if not exists x_joined_at timestamptz,
  add column if not exists o_joined_at timestamptz,
  add column if not exists turn_deadline timestamptz,
  add column if not exists end_reason text check (end_reason in ('timeout', 'resign'));

-- Challenges already in progress get a fresh 24-hour window.
update public.challenges set deadline_at = now() + interval '24 hours'
  where status = 'accepted' and deadline_at is null;

create or replace function public.caro_turn_limit() returns interval
language sql immutable set search_path = '' as $$ select interval '60 seconds' $$;

-- Internal: finishes an accepted challenge whose clock has run out. Returns
-- true when it changed the result. Locks the challenge before the match, the
-- order every challenge function uses.
create or replace function public.settle_challenge_deadline(cid uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges; m public.caro_matches; has_match boolean;
  a public.challenge_runs; b public.challenge_runs; winner uuid;
  now_ts timestamptz := clock_timestamp();
begin
  select * into c from public.challenges ch where ch.id = cid for update;
  if not found or c.status <> 'accepted' then return false; end if;
  if c.game = 'caro' then
    select * into m from public.caro_matches cm where cm.challenge_id = cid for update;
    has_match := found;
    if has_match and m.status <> 'playing' then return false; end if;
    if has_match and m.x_joined_at is not null and m.o_joined_at is not null then
      if m.turn_deadline is null or m.turn_deadline > now_ts then return false; end if;
      -- The player to move ran out of time.
      winner := case when m.turn_id = m.x_player_id then m.o_player_id else m.x_player_id end;
    else
      if c.deadline_at is null or c.deadline_at > now_ts then return false; end if;
      -- Only one player came to the board: they win. Nobody came: draw.
      winner := case when not has_match then null
        when m.x_joined_at is not null then m.x_player_id
        when m.o_joined_at is not null then m.o_player_id end;
    end if;
    if has_match then
      update public.caro_matches cm set status = 'completed', winner_id = winner, turn_id = null,
        turn_deadline = null, end_reason = 'timeout', updated_at = now_ts
        where cm.challenge_id = cid;
    end if;
  else
    if c.deadline_at is null or c.deadline_at > now_ts then return false; end if;
    select * into a from public.challenge_runs r where r.challenge_id = cid and r.user_id = c.challenger_id;
    select * into b from public.challenge_runs r where r.challenge_id = cid and r.user_id = c.opponent_id;
    -- Both finished would already be completed, so at most one submitted.
    winner := case when a.finished_at is not null then c.challenger_id
      when b.finished_at is not null then c.opponent_id end;
  end if;
  update public.challenges ch set status = 'completed', winner_id = winner, end_reason = 'timeout'
    where ch.id = cid;
  return true;
end;
$$;

create or replace function public.create_game_challenge(
  opponent_id uuid,
  level text,
  game_name text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); cid uuid; board_text text; values_array integer[];
  digit_offset integer := floor(random() * 9)::integer;
begin
  if uid is null or uid = $1 or not exists(select 1 from public.profiles where id = $1) then
    raise exception 'Người nhận không hợp lệ.';
  end if;
  if level not in ('easy', 'medium', 'hard') or level is null then
    raise exception 'Độ khó không hợp lệ.';
  end if;
  if game_name not in ('sudoku', 'caro') or game_name is null then
    raise exception 'Trò chơi không hợp lệ.';
  end if;
  -- Expired invites no longer count towards the limit.
  if (select count(*) from public.challenges c where c.challenger_id = uid and c.status = 'pending'
      and c.expires_at > clock_timestamp()) >= 20 then
    raise exception 'Bạn đang có quá nhiều lời mời chưa được trả lời.';
  end if;

  insert into public.challenges(challenger_id, opponent_id, difficulty, game)
    values(uid, $1, level, game_name) returning id into cid;

  if game_name = 'sudoku' then
    board_text := case level
      when 'easy' then '000260701680070090190004500820100040004602900050003028009300074040050036703018000'
      when 'medium' then '530070000600195000098000060800060003400803001700020006060000280000419005000080079'
      else '000000010400000000020000000000050407008000300001090000300400200050100000000806000' end;
    select array_agg(case when substr(board_text, i, 1) = '0' then 0
      else ((substr(board_text, i, 1)::integer - 1 + digit_offset) % 9) + 1 end order by i)
      into values_array from generate_series(1,81) i;
    insert into public.challenge_puzzles(challenge_id, givens) values(cid, values_array);
  end if;
  return cid;
end;
$$;

create or replace function public.respond_challenge(challenge_id uuid, accept_invite boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.challenges c set
    status = case when accept_invite then 'accepted' else 'declined' end,
    deadline_at = case when accept_invite then clock_timestamp() + interval '24 hours' end
    where c.id = $1 and c.opponent_id = auth.uid() and c.status = 'pending'
      and c.expires_at > clock_timestamp();
  if not found then
    if exists(select 1 from public.challenges c
        where c.id = $1 and c.opponent_id = auth.uid() and c.status = 'pending') then
      raise exception 'Lời mời đã hết hạn.';
    end if;
    raise exception 'Lời mời không còn chờ hoặc bạn không phải người nhận.';
  end if;
end;
$$;

create or replace function public.start_challenge(challenge_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.challenges; run public.challenge_runs; puzzle integer[];
begin
  select * into c from public.challenges where id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id)
     or c.game <> 'sudoku' then
    raise exception 'Thách đấu chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  if public.settle_challenge_deadline($1) then
    return jsonb_build_object('status', 'completed');
  end if;
  if c.status <> 'accepted' then
    raise exception 'Thách đấu chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  insert into public.challenge_runs(challenge_id, user_id) values($1, auth.uid()) on conflict do nothing;
  select * into run from public.challenge_runs r where r.challenge_id = $1 and r.user_id = auth.uid();
  if run.finished_at is not null then raise exception 'Bạn đã hoàn thành thách đấu này.'; end if;
  select givens into puzzle from public.challenge_puzzles p where p.challenge_id = $1;
  return jsonb_build_object('status', 'accepted', 'givens', puzzle, 'started_at', run.started_at,
    'difficulty', c.difficulty, 'deadline_at', c.deadline_at, 'server_now', clock_timestamp());
end;
$$;

create or replace function public.submit_challenge(challenge_id uuid, answer integer[], error_count integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges; run public.challenge_runs; puzzle integer[]; elapsed integer; points integer;
  a public.challenge_runs; b public.challenge_runs; winner uuid;
begin
  select * into c from public.challenges where id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id)
     or c.game <> 'sudoku' then
    raise exception 'Bạn không có quyền nộp kết quả.';
  end if;
  select * into run from public.challenge_runs r where r.challenge_id = $1 and r.user_id = auth.uid() for update;
  if not found then raise exception 'Bạn chưa bắt đầu thách đấu.'; end if;
  -- Idempotent retry after a lost network response.
  if run.finished_at is not null then return jsonb_build_object('score', run.score, 'seconds', run.seconds); end if;
  -- Too late: the deadline decides the result and this answer does not count.
  if public.settle_challenge_deadline($1) then return jsonb_build_object('expired', true); end if;
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

create or replace function public.start_caro_challenge(challenge_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.challenges; m public.caro_matches; uid uuid := auth.uid(); now_ts timestamptz;
begin
  select * into c from public.challenges ch where ch.id = $1 for update;
  if not found or uid is null or uid not in (c.challenger_id, c.opponent_id) or c.game <> 'caro' then
    raise exception 'Thách đấu Caro chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  if public.settle_challenge_deadline($1) then
    select * into c from public.challenges ch where ch.id = $1;
  end if;
  -- A finished match can still be opened to see the final board.
  if c.status = 'completed' then
    return jsonb_build_object('status', 'completed', 'end_reason', c.end_reason,
      'server_now', clock_timestamp());
  end if;
  if c.status <> 'accepted' then
    raise exception 'Thách đấu Caro chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  insert into public.caro_matches(challenge_id, x_player_id, o_player_id, turn_id)
    values($1, c.challenger_id, c.opponent_id, c.challenger_id)
    on conflict do nothing;
  now_ts := clock_timestamp();
  update public.caro_matches cm set
    x_joined_at = coalesce(cm.x_joined_at, case when uid = cm.x_player_id then now_ts end),
    o_joined_at = coalesce(cm.o_joined_at, case when uid = cm.o_player_id then now_ts end)
    where cm.challenge_id = $1
    returning * into m;
  -- The move clock starts once both players have come to the board.
  if m.status = 'playing' and m.turn_deadline is null
     and m.x_joined_at is not null and m.o_joined_at is not null then
    update public.caro_matches cm set turn_deadline = now_ts + public.caro_turn_limit()
      where cm.challenge_id = $1 returning * into m;
  end if;
  return jsonb_build_object('status', 'accepted',
    'mark', case when uid = m.x_player_id then 1 else 2 end, 'server_now', clock_timestamp());
end;
$$;

-- Same rules as 004 (Vietnamese blocked-ends rule) plus the move clock.
create or replace function public.play_caro_move(challenge_id uuid, cell_index integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.challenges; m public.caro_matches; mark integer; row_no integer; col_no integer;
  dr integer; dc integer; step_no integer; rr integer; cc integer; streak integer;
  blocked integer; cell integer;
  won boolean := false; next_player uuid;
begin
  select * into c from public.challenges ch where ch.id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id) then
    raise exception 'Bạn không có quyền chơi ván này.';
  end if;
  -- A move after the clock ran out loses instead of being played.
  if public.settle_challenge_deadline($1) then return; end if;
  select * into m from public.caro_matches cm where cm.challenge_id = $1 for update;
  if not found or auth.uid() not in (m.x_player_id, m.o_player_id) then
    raise exception 'Bạn không có quyền chơi ván này.';
  end if;
  if m.status <> 'playing' then raise exception 'Ván đấu đã kết thúc.'; end if;
  if m.turn_id <> auth.uid() then raise exception 'Chưa đến lượt của bạn.'; end if;
  if cell_index is null or cell_index < 0 or cell_index >= 225 or m.board[cell_index + 1] <> 0 then
    raise exception 'Ô cờ không hợp lệ.';
  end if;

  mark := case when auth.uid() = m.x_player_id then 1 else 2 end;
  m.board[cell_index + 1] := mark;
  row_no := cell_index / 15;
  col_no := cell_index % 15;

  -- Count both directions for horizontal, vertical and the two diagonals,
  -- remembering whether each end of the line stops at an opponent stone.
  for direction in 0..3 loop
    dr := (array[0, 1, 1, 1])[direction + 1];
    dc := (array[1, 0, 1, -1])[direction + 1];
    streak := 1;
    blocked := 0;
    for sign_value in -1..1 by 2 loop
      for step_no in 1..14 loop
        rr := row_no + dr * step_no * sign_value;
        cc := col_no + dc * step_no * sign_value;
        exit when rr < 0 or rr >= 15 or cc < 0 or cc >= 15;
        cell := m.board[rr * 15 + cc + 1];
        if cell <> mark then
          if cell <> 0 then blocked := blocked + 1; end if;
          exit;
        end if;
        streak := streak + 1;
      end loop;
    end loop;
    if streak >= 5 and blocked < 2 then won := true; exit; end if;
  end loop;

  if won then
    update public.caro_matches set board = m.board, status = 'completed', winner_id = auth.uid(),
      turn_id = null, turn_deadline = null, moves = m.moves + 1, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
    update public.challenges set status = 'completed', winner_id = auth.uid() where id = $1;
  elsif m.moves + 1 = 225 then
    update public.caro_matches set board = m.board, status = 'completed', winner_id = null,
      turn_id = null, turn_deadline = null, moves = 225, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
    update public.challenges set status = 'completed', winner_id = null where id = $1;
  else
    next_player := case when auth.uid() = m.x_player_id then m.o_player_id else m.x_player_id end;
    update public.caro_matches set board = m.board, turn_id = next_player,
      turn_deadline = case when m.x_joined_at is not null and m.o_joined_at is not null
        then clock_timestamp() + public.caro_turn_limit() end,
      moves = m.moves + 1, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
  end if;
end;
$$;

create or replace function public.resign_challenge(challenge_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.challenges; uid uuid := auth.uid(); winner uuid;
begin
  select * into c from public.challenges ch where ch.id = $1 for update;
  if not found or uid is null or uid not in (c.challenger_id, c.opponent_id) then
    raise exception 'Bạn không có quyền với thách đấu này.';
  end if;
  -- The clock may already have decided the result.
  if public.settle_challenge_deadline($1) then return; end if;
  if c.status <> 'accepted' then raise exception 'Thách đấu không còn diễn ra.'; end if;
  if c.game = 'sudoku' and exists(select 1 from public.challenge_runs r
      where r.challenge_id = $1 and r.user_id = uid and r.finished_at is not null) then
    raise exception 'Bạn đã nộp bài, hãy chờ kết quả của đối thủ.';
  end if;
  winner := case when uid = c.challenger_id then c.opponent_id else c.challenger_id end;
  update public.caro_matches cm set status = 'completed', winner_id = winner, turn_id = null,
    turn_deadline = null, end_reason = 'resign', updated_at = clock_timestamp()
    where cm.challenge_id = $1 and cm.status = 'playing';
  update public.challenges ch set status = 'completed', winner_id = winner, end_reason = 'resign'
    where ch.id = $1;
end;
$$;

create or replace function public.check_challenge_timeout(challenge_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare c public.challenges;
begin
  select * into c from public.challenges ch where ch.id = $1;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id) then
    raise exception 'Bạn không có quyền với thách đấu này.';
  end if;
  return public.settle_challenge_deadline($1);
end;
$$;

revoke all on function public.caro_turn_limit(), public.settle_challenge_deadline(uuid)
  from public, anon, authenticated;
revoke all on function public.resign_challenge(uuid), public.check_challenge_timeout(uuid)
  from public, anon;
grant execute on function public.resign_challenge(uuid), public.check_challenge_timeout(uuid)
  to authenticated;

commit;
