-- Run after 008_score_formula.sql. Safe to run again.
-- The sender can withdraw an invite while it is still pending. The row is
-- kept with status 'cancelled' so both players see it change in Realtime.
begin;

-- Drop the status check whatever it is called (001 left it to Postgres to
-- name), then add the one that allows 'cancelled'.
do $$
declare con record;
begin
  for con in select conname from pg_constraint
      where conrelid = 'public.challenges'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) like '%status%'
  loop
    execute format('alter table public.challenges drop constraint %I', con.conname);
  end loop;
end;
$$;
alter table public.challenges add constraint challenges_status_check
  check (status in ('pending', 'accepted', 'declined', 'completed', 'cancelled'));

create or replace function public.cancel_challenge(challenge_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  -- Same row lock as respond_challenge: if the opponent accepts at the same
  -- moment, only the first of the two changes goes through.
  update public.challenges c set status = 'cancelled'
    where c.id = $1 and c.challenger_id = auth.uid() and c.status = 'pending';
  if not found then
    raise exception 'Chỉ người gửi mới hủy được lời mời, và chỉ khi lời mời còn đang chờ.';
  end if;
end;
$$;

revoke all on function public.cancel_challenge(uuid) from public, anon;
grant execute on function public.cancel_challenge(uuid) to authenticated;

commit;
