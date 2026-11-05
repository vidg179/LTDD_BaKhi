-- Run after 010_leaderboard_rank.sql. Safe to run again.
-- 1. A player appears in public.profiles only once their email is confirmed.
-- 2. Changes to chat, challenges and Caro boards are announced on channel
--    bakhi_changes. BaKhi_API listens (LISTEN), reads the row and pushes it
--    over WebSocket to the two players involved.
begin;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values (new.id,
    case when char_length(trim(coalesce(new.raw_user_meta_data->>'display_name', ''))) >= 2
      then left(trim(new.raw_user_meta_data->>'display_name'), 40) else 'Người chơi' end)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email_confirmed_at on auth.users
  for each row when (new.email_confirmed_at is not null)
  execute function public.handle_new_user();

-- The payload names the row, not its content: a chat message can be longer
-- than the 8000 bytes a notification may carry.
create or replace function public.announce_change() returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r jsonb := to_jsonb(new);
  row_key text := r->>'id';
  players jsonb;
begin
  case tg_table_name
    when 'messages' then
      players := jsonb_build_array(r->'sender_id', r->'recipient_id');
    when 'challenges' then
      players := jsonb_build_array(r->'challenger_id', r->'opponent_id');
    when 'caro_matches' then
      players := jsonb_build_array(r->'x_player_id', r->'o_player_id');
      row_key := r->>'challenge_id';
    when 'challenge_runs' then
      select jsonb_build_array(c.challenger_id, c.opponent_id) into players
      from public.challenges c where c.id = (r->>'challenge_id')::uuid;
  end case;
  perform pg_notify('bakhi_changes', jsonb_build_object(
    'table', tg_table_name, 'op', tg_op, 'key', row_key, 'users', players)::text);
  return null;
end;
$$;
revoke all on function public.announce_change() from public, anon, authenticated;

drop trigger if exists announce_change on public.messages;
create trigger announce_change after insert or update on public.messages
  for each row execute function public.announce_change();
drop trigger if exists announce_change on public.challenges;
create trigger announce_change after insert or update on public.challenges
  for each row execute function public.announce_change();
drop trigger if exists announce_change on public.caro_matches;
create trigger announce_change after insert or update on public.caro_matches
  for each row execute function public.announce_change();
drop trigger if exists announce_change on public.challenge_runs;
create trigger announce_change after insert or update on public.challenge_runs
  for each row execute function public.announce_change();

commit;
