-- Run after 002_caro_challenges.sql. Safe to run again.
-- Hosted Supabase grants new functions and tables to `anon` through default
-- privileges, which `revoke ... from public` does not remove. The functions
-- already reject callers without auth.uid(); this closes the outer door too.
begin;

revoke execute on function public.create_challenge(uuid,text), public.create_game_challenge(uuid,text,text),
  public.respond_challenge(uuid,boolean), public.start_challenge(uuid), public.submit_challenge(uuid,integer[],integer),
  public.start_caro_challenge(uuid), public.play_caro_move(uuid,integer) from anon;
revoke all on public.caro_matches from anon;

commit;
