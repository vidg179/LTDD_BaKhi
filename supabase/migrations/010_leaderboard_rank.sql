-- Run after 009_cancel_challenge.sql. Safe to run again.
-- Equal score, time and mistakes are now ordered by who got there first
-- (achieved_at = when the server stored the result) instead of by user id,
-- and a player outside the top 50 can look up their own rank.
begin;

-- Same rows as 005; achieved_at is appended, which create or replace allows.
create or replace view public.leaderboard with (security_invoker = true) as
  select distinct on (r.game, r.difficulty, r.user_id)
    r.user_id, p.display_name, r.game, r.difficulty, r.score, r.seconds, r.mistakes,
    r.created_at as achieved_at
  from public.game_results r join public.profiles p on p.id = r.user_id
  where r.outcome = 'win' and r.ranked
  order by r.game, r.difficulty, r.user_id, r.score desc, r.seconds, r.mistakes, r.created_at;

-- The caller's position with the same ordering as the leaderboard screen;
-- null when they have no ranked win for this game and level.
create or replace function public.my_leaderboard_rank(game_name text, level text)
returns jsonb language sql stable set search_path = '' as $$
  select to_jsonb(ranked) - 'user_id' from (
    select row_number() over (
        order by l.score desc, l.seconds, l.mistakes, l.achieved_at, l.user_id) as rank,
      l.user_id, l.score, l.seconds, l.mistakes
    from public.leaderboard l
    where l.game = game_name and l.difficulty = level
  ) ranked
  where ranked.user_id = auth.uid();
$$;

revoke all on function public.my_leaderboard_rank(text, text) from public, anon;
grant execute on function public.my_leaderboard_rank(text, text) to authenticated;

commit;
