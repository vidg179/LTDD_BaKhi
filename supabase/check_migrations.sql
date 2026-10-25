-- Paste into the Supabase SQL Editor and run. Read-only: it changes nothing.
-- One row per migration: "✅ đã chạy" or "❌ CHƯA CHẠY". Run the files in
-- supabase/migrations/ in number order from the FIRST ❌ through 010, also
-- the ones already ✅ after it: running an older file again overwrites
-- functions from newer ones, and running them all in order restores them.
-- Each check looks for what that migration leaves behind, in its latest
-- form, so an older file run after a newer one shows up as ❌ here.
with src as (
  select p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
body as (
  select
    coalesce((select string_agg(prosrc, ' ') from src where proname = 'play_caro_move'), '') as caro_move,
    coalesce((select string_agg(prosrc, ' ') from src where proname = 'create_game_challenge'), '') as create_challenge,
    coalesce((select string_agg(prosrc, ' ') from src where proname = 'min_game_moves'), '') as min_moves,
    coalesce((select string_agg(prosrc, ' ') from src where proname = 'game_score'), '') as score
)
select migration, case when applied then '✅ đã chạy' else '❌ CHƯA CHẠY' end as trang_thai, noi_dung
from body, lateral (values
  ('001_game_app.sql',
    to_regclass('public.game_results') is not null,
    'Bảng, RLS, chat, thách đấu Sudoku'),
  ('002_caro_challenges.sql',
    to_regclass('public.caro_matches') is not null,
    'Caro online'),
  ('003_revoke_anon.sql',
    to_regprocedure('public.create_game_challenge(uuid,text,text)') is not null
      and not has_function_privilege('anon',
        to_regprocedure('public.create_game_challenge(uuid,text,text)'), 'execute'),
    'Chặn người chưa đăng nhập gọi hàm thách đấu'),
  ('004_caro_vietnam_rule.sql',
    body.caro_move like '%blocked%',
    'Caro online luật chặn hai đầu'),
  ('005_verified_results.sql',
    to_regprocedure('public.submit_game_result(uuid,uuid,text,text,integer,integer,integer,text,timestamptz)') is not null
      and not exists(select 1 from pg_policies where schemaname = 'public'
        and tablename = 'game_results' and policyname = 'results_insert'),
    'Chặn gửi điểm giả'),
  ('006_challenge_deadlines.sql',
    to_regprocedure('public.check_challenge_timeout(uuid)') is not null
      and body.caro_move like '%turn_deadline%'
      and body.create_challenge like '%expires_at%',
    'Hết hạn lời mời, đầu hàng, đồng hồ lượt'),
  ('007_graded_sudoku.sql',
    to_regclass('public.challenge_templates') is not null
      and body.create_challenge like '%challenge_templates%'
      and body.min_moves like '%34%',
    'Đề Sudoku thách đấu theo độ khó mới'),
  ('008_score_formula.sql',
    body.score like '%19 / 20%',
    'Công thức điểm mới'),
  ('009_cancel_challenge.sql',
    to_regprocedure('public.cancel_challenge(uuid)') is not null,
    'Hủy lời mời'),
  ('010_leaderboard_rank.sql',
    to_regprocedure('public.my_leaderboard_rank(text,text)') is not null
      and exists(select 1 from information_schema.columns where table_schema = 'public'
        and table_name = 'leaderboard' and column_name = 'achieved_at'),
    'Xếp hạng: ai đạt trước, hạng của bạn')
) as checks(migration, applied, noi_dung)
order by migration;
