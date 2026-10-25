-- Run after 007_graded_sudoku.sql. Safe to run again.
-- Replaces max(100, base × level − 2 × seconds − 100 × mistakes), whose
-- 100-point floor tied every slow solve and then ranked them by time alone,
-- ignoring mistakes. Same formula as calculateScore in
-- lib/games/game_models.dart, integer-only so both always agree:
--   points = base × level × ref / (ref + seconds), ref = reference time of
--   the game and level; each mistake then takes 5% of what is left
--   (× 19 / 20, rounded down); a win is worth at least 1, a loss or draw 0.
begin;

create or replace function public.game_score(game text, difficulty text, seconds integer, mistakes integer, outcome text)
returns integer language plpgsql immutable set search_path = '' as $$
declare level integer; ref integer; points bigint;
begin
  if outcome <> 'win' then return 0; end if;
  level := case difficulty when 'hard' then 3 when 'medium' then 2 else 1 end;
  ref := case game
    when 'sudoku' then (array[600, 900, 1500])[level]
    when 'puzzle' then (array[60, 240, 600])[level]
    when 'caro' then (array[120, 240, 360])[level]
    else 180 end;
  points := (case game when 'sudoku' then 2000 when 'puzzle' then 1500 else 1000 end)::bigint
    * level * ref / (ref + greatest(seconds, 0));
  for i in 1..least(greatest(mistakes, 0), 10000) loop
    exit when points = 0;
    points := points * 19 / 20;
  end loop;
  return greatest(1, points)::integer;
end;
$$;

-- The stored score column is generated from game_score; touching each row
-- recomputes it, so the leaderboard uses the new formula right away.
-- Finished challenge runs keep the scores their winners were decided on.
update public.game_results set seconds = seconds;

commit;
