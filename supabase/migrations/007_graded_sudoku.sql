-- Run after 006_challenge_deadlines.sql. Safe to run again.
-- Sudoku challenges use the same difficulty scale as solo play: every
-- template below was generated and graded by gradeSudoku in
-- lib/games/sudoku_engine.dart (easy = singles only; medium = also locked
-- candidates, naked pairs/triples, hidden pairs; hard = those are not
-- enough). test/game_engines_test.dart re-grades this file.
-- Each invite picks one template of its level at random and relabels the
-- digits with a random permutation, which keeps the solution unique and the
-- grade unchanged.
begin;

create table if not exists public.challenge_templates (
  givens text primary key check (givens ~ '^[0-9]{81}$'),
  level text not null check (level in ('easy', 'medium', 'hard'))
);
-- Never readable by clients.
alter table public.challenge_templates enable row level security;
revoke all on public.challenge_templates from anon, authenticated;

insert into public.challenge_templates(level, givens) values
  ('easy', '500240091400009035981700260700030000050892000810006040095007020640320070200000456'),
  ('easy', '001000796597800431006791080700014060000980000068305102000030600610008003304050008'),
  ('easy', '968007000024006310073005896006000100049201708700830960401600209002040500830000000'),
  ('easy', '249000500000050209703002060427190003100800096908030410094005000002460975070200004'),
  ('easy', '021740030703069040000035009007090002630400070400000953308520096005006300006387004'),
  ('easy', '758060902006054000010000605067000890549600001820030006094300000075901480180700050'),
  ('medium', '800000051003045027705001038506200193000509200900013005007156000600400000250000000'),
  ('medium', '005086900000009006000000502000500004603074000700000300807060050090040710000000009'),
  ('medium', '050007000020100000004000060098001600000832000510900080000204810740000050200000304'),
  ('medium', '900001003060900100080356070008509010000108000020000930050700300010080005006000000'),
  ('medium', '900300000200000004004920001420030070060570043300600020000010087000700000607409005'),
  ('medium', '600800037000907500070000100008002050206090000040730001007540208000200000090073000'),
  ('hard', '070006031000003000000050764400070010005000900002935608207401300061300002003000170'),
  ('hard', '000061082060000003002380170138400000400000000500600000780500090000823005000000030'),
  ('hard', '000000409007000000600008000105700040070980050002500001036029100040010520000004006'),
  ('hard', '050000007200000000003010860004000053010009000000025000400090526100006080006287010'),
  ('hard', '760000000030068004008007060000049578087032040490000000041070600000001493000600007'),
  ('hard', '000700056007000400086000007000806090620000001400050000002087000075600008000002300')
on conflict (givens) do nothing;

create or replace function public.create_game_challenge(
  opponent_id uuid,
  level text,
  game_name text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid(); cid uuid; board_text text; values_array integer[]; digits integer[];
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
    select t.givens into board_text from public.challenge_templates t
      where t.level = $2 order by random() limit 1;
    if board_text is null then raise exception 'Chưa có đề Sudoku cho mức này.'; end if;
    -- digits[n] is the new label of digit n.
    select array_agg(d order by random()) into digits from generate_series(1, 9) d;
    select array_agg(case when substr(board_text, i, 1) = '0' then 0
      else digits[substr(board_text, i, 1)::integer] end order by i)
      into values_array from generate_series(1, 81) i;
    insert into public.challenge_puzzles(challenge_id, givens) values(cid, values_array);
  end if;
  return cid;
end;
$$;

-- The original Sudoku-only entry point now shares the templates above.
create or replace function public.create_challenge(opponent_id uuid, level text) returns uuid
language sql security definer set search_path = '' as $$
  select public.create_game_challenge($1, $2, 'sudoku');
$$;

-- A solve fills every empty cell at least once. Over 1000 generated boards
-- per level the most clues were 38 (easy), 41 (medium) and 44 (hard), so at
-- least 43/40/37 cells are empty; the minimums below leave a small margin.
create or replace function public.min_game_moves(game text, difficulty text)
returns integer language sql immutable set search_path = '' as $$
  select case game
    when 'sudoku' then case difficulty when 'hard' then 34 when 'medium' then 36 else 40 end
    when 'caro' then 9
    else 1 end;
$$;

commit;
