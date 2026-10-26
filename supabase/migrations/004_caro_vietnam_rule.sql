-- Run after 003_revoke_anon.sql. Safe to run again.
-- Vietnamese Caro rule for online matches: five or more in a row wins unless
-- opponent stones block both ends. The board edge does not count as a block.
-- `create or replace` keeps the grants and revokes from 002/003.
begin;

create or replace function public.play_caro_move(challenge_id uuid, cell_index integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  m public.caro_matches; mark integer; row_no integer; col_no integer;
  dr integer; dc integer; step_no integer; rr integer; cc integer; streak integer;
  blocked integer; cell integer;
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

commit;
