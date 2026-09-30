-- Run after 001_game_app.sql to add two-player online Caro challenges.
begin;

alter table public.challenges
  add column if not exists game text not null default 'sudoku'
  check (game in ('sudoku', 'caro'));

create table if not exists public.caro_matches (
  challenge_id uuid primary key references public.challenges(id) on delete cascade,
  board integer[] not null default array_fill(0, array[225])
    check (array_length(board, 1) = 225),
  x_player_id uuid not null references public.profiles(id) on delete cascade,
  o_player_id uuid not null references public.profiles(id) on delete cascade,
  turn_id uuid references public.profiles(id) on delete set null,
  winner_id uuid references public.profiles(id) on delete set null,
  status text not null default 'playing' check (status in ('playing', 'completed')),
  moves integer not null default 0 check (moves between 0 and 225),
  updated_at timestamptz not null default now(),
  check (x_player_id <> o_player_id)
);

alter table public.caro_matches enable row level security;
create policy caro_matches_read on public.caro_matches for select to authenticated
  using ((select auth.uid()) in (x_player_id, o_player_id));
grant select on public.caro_matches to authenticated;

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
  if (select count(*) from public.challenges c where c.challenger_id = uid and c.status = 'pending') >= 20 then
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

create or replace function public.start_caro_challenge(challenge_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.challenges; m public.caro_matches;
begin
  select * into c from public.challenges where id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (c.challenger_id, c.opponent_id)
     or c.status <> 'accepted' or c.game <> 'caro' then
    raise exception 'Thách đấu Caro chưa sẵn sàng hoặc bạn không có quyền tham gia.';
  end if;
  insert into public.caro_matches(challenge_id, x_player_id, o_player_id, turn_id)
    values($1, c.challenger_id, c.opponent_id, c.challenger_id)
    on conflict do nothing;
  select * into m from public.caro_matches cm where cm.challenge_id = $1;
  return jsonb_build_object('mark', case when auth.uid() = m.x_player_id then 1 else 2 end);
end;
$$;

create or replace function public.play_caro_move(challenge_id uuid, cell_index integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.caro_matches; mark integer; row_no integer; col_no integer;
  dr integer; dc integer; step_no integer; rr integer; cc integer; streak integer;
  won boolean := false; next_player uuid;
begin
  select * into m from public.caro_matches cm where cm.challenge_id = $1 for update;
  if not found or auth.uid() is null or auth.uid() not in (m.x_player_id, m.o_player_id) then
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

  -- Count both directions for horizontal, vertical and the two diagonals.
  for direction in 0..3 loop
    dr := (array[0, 1, 1, 1])[direction + 1];
    dc := (array[1, 0, 1, -1])[direction + 1];
    streak := 1;
    for sign_value in -1..1 by 2 loop
      for step_no in 1..14 loop
        rr := row_no + dr * step_no * sign_value;
        cc := col_no + dc * step_no * sign_value;
        exit when rr < 0 or rr >= 15 or cc < 0 or cc >= 15;
        exit when m.board[rr * 15 + cc + 1] <> mark;
        streak := streak + 1;
      end loop;
    end loop;
    if streak >= 5 then won := true; exit; end if;
  end loop;

  if won then
    update public.caro_matches set board = m.board, status = 'completed', winner_id = auth.uid(),
      turn_id = null, moves = m.moves + 1, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
    update public.challenges set status = 'completed', winner_id = auth.uid() where id = $1;
  elsif m.moves + 1 = 225 then
    update public.caro_matches set board = m.board, status = 'completed', winner_id = null,
      turn_id = null, moves = 225, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
    update public.challenges set status = 'completed', winner_id = null where id = $1;
  else
    next_player := case when auth.uid() = m.x_player_id then m.o_player_id else m.x_player_id end;
    update public.caro_matches set board = m.board, turn_id = next_player,
      moves = m.moves + 1, updated_at = clock_timestamp()
      where caro_matches.challenge_id = $1;
  end if;
end;
$$;

revoke all on function public.create_game_challenge(uuid,text,text),
  public.start_caro_challenge(uuid), public.play_caro_move(uuid,integer) from public;
grant execute on function public.create_game_challenge(uuid,text,text),
  public.start_caro_challenge(uuid), public.play_caro_move(uuid,integer) to authenticated;

alter publication supabase_realtime add table public.caro_matches;
commit;
