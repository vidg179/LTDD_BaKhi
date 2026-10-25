import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Executes the real migration in an embedded PostgreSQL instance. Auth is a
// minimal fixture; hosted Supabase Auth and Realtime still require an online test.
const db = new PGlite();
await db.exec(`
  create role anon;
  create role authenticated;
  create schema auth;
  create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant usage on schema auth to authenticated, anon;
  grant execute on function auth.uid() to authenticated, anon;
  create publication supabase_realtime;
  -- Mirror hosted Supabase: new objects in public are granted to anon too.
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant execute on functions to anon, authenticated;
`);
const migration = await readFile(new URL('../../supabase/migrations/001_game_app.sql', import.meta.url), 'utf8');
await db.exec(migration);
const caroMigration = await readFile(new URL('../../supabase/migrations/002_caro_challenges.sql', import.meta.url), 'utf8');
await db.exec(caroMigration);
const revokeAnon = await readFile(new URL('../../supabase/migrations/003_revoke_anon.sql', import.meta.url), 'utf8');
await db.exec(revokeAnon);
await db.exec(revokeAnon); // idempotent
const caroRule = await readFile(new URL('../../supabase/migrations/004_caro_vietnam_rule.sql', import.meta.url), 'utf8');
await db.exec(caroRule);
await db.exec(caroRule); // idempotent
const verifiedResults = await readFile(new URL('../../supabase/migrations/005_verified_results.sql', import.meta.url), 'utf8');
await db.exec(verifiedResults);
await db.exec(verifiedResults); // idempotent
const deadlines = await readFile(new URL('../../supabase/migrations/006_challenge_deadlines.sql', import.meta.url), 'utf8');
await db.exec(deadlines);
await db.exec(deadlines); // idempotent
const graded = await readFile(new URL('../../supabase/migrations/007_graded_sudoku.sql', import.meta.url), 'utf8');
await db.exec(graded);
await db.exec(graded); // idempotent
const scoring = await readFile(new URL('../../supabase/migrations/008_score_formula.sql', import.meta.url), 'utf8');
await db.exec(scoring);
await db.exec(scoring); // idempotent
const cancelling = await readFile(new URL('../../supabase/migrations/009_cancel_challenge.sql', import.meta.url), 'utf8');
await db.exec(cancelling);
await db.exec(cancelling); // idempotent
const ranking = await readFile(new URL('../../supabase/migrations/010_leaderboard_rank.sql', import.meta.url), 'utf8');
await db.exec(ranking);
await db.exec(ranking); // idempotent
const a = '10000000-0000-4000-8000-000000000001';
const b = '10000000-0000-4000-8000-000000000002';
const c = '10000000-0000-4000-8000-000000000003';
await db.query(`insert into auth.users values ($1, '{"display_name":"An"}'), ($2, '{"display_name":"Bình"}'), ($3, '{"display_name":"Chi"}')`, [a,b,c]);
let assertions = 0;
function check(value, expected, label) { assert.deepEqual(value, expected, label); assertions++; }
async function asUser(id) { await db.exec(`reset role; set role authenticated; set request.jwt.claim.sub = '${id}';`); }
async function rejected(sql, params = []) {
  await assert.rejects(() => db.query(sql, params)); assertions++;
}
async function denied(sql, params = []) {
  await assert.rejects(() => db.query(sql, params), (e) => e.code === '42501', sql); assertions++;
}
await asUser(a);
check((await db.query('select * from public.profiles')).rows.length, 3, 'signup trigger creates profiles');
await rejected('select * from public.challenge_puzzles');
// Scores reach the leaderboard only through server-timed sessions.
await denied(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at) values(gen_random_uuid(),$1,'sudoku','hard',0,0,60,'win',now())`, [a]);
await rejected(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at) values(gen_random_uuid(),$1,'sudoku','easy',10,0,1,'win',now())`, [b]);
await rejected('select * from game_sessions');
async function startSession(game, level, minutesAgo = 0) {
  const id = (await db.query(`select start_game_session($1,$2)->>'id' id`, [game, level])).rows[0].id;
  if (minutesAgo) {
    const sub = (await db.query(`select current_setting('request.jwt.claim.sub') sub`)).rows[0].sub;
    await db.exec(`reset role; update game_sessions set started_at = now() - interval '${minutesAgo} minutes' where id = '${id}';`);
    await asUser(sub);
  }
  return id;
}
async function submit(resultId, session, game, level, seconds, mistakes, moves, outcome = 'win') {
  return (await db.query(`select submit_game_result($1,$2,$3,$4,$5,$6,$7,$8,now()) r`,
    [resultId, session, game, level, seconds, mistakes, moves, outcome])).rows[0].r;
}
const uuid = async () => (await db.query('select gen_random_uuid() id')).rows[0].id;
check((await submit(await uuid(), null, 'sudoku', 'hard', 0, 0, 60)).ranked, false, 'result without a session is never ranked');
check((await submit(await uuid(), await startSession('sudoku', 'easy'), 'sudoku', 'easy', 100, 0, 40)).ranked, false,
  'claimed time longer than the server-measured session is rejected');
const goodSession = await startSession('sudoku', 'easy', 10);
const goodResult = await uuid();
check(await submit(goodResult, goodSession, 'sudoku', 'easy', 100, 1, 40), {score: 1628, ranked: true}, 'plausible timed result is ranked');
check(await submit(goodResult, goodSession, 'sudoku', 'easy', 100, 1, 40), {score: 1628, ranked: true}, 'retry is idempotent');
check((await submit(await uuid(), goodSession, 'sudoku', 'easy', 60, 0, 40)).ranked, false, 'a session cannot be reused');
check((await submit(await uuid(), await startSession('sudoku', 'easy', 10), 'sudoku', 'easy', 150, 1, 40)).ranked, true, 'second timed result');
check((await submit(await uuid(), await startSession('puzzle', 'easy', 10), 'sudoku', 'easy', 100, 0, 40)).ranked, false, 'session of another game');
check((await submit(await uuid(), await startSession('sudoku', 'hard', 10), 'sudoku', 'hard', 10, 0, 53)).ranked, false, 'impossibly fast solve');
check((await submit(await uuid(), await startSession('sudoku', 'hard', 10), 'sudoku', 'hard', 200, 0, 5)).ranked, false, 'too few moves for Sudoku');
check((await submit(await uuid(), await startSession('rubik', 'easy', 10), 'rubik', 'easy', 10, 0, 20)).ranked, false, 'Rubik steps clicked through');
check((await submit(await uuid(), await startSession('caro', 'hard', 10), 'caro', 'hard', 60, 0, 30, 'loss')).ranked, false, 'losses are not ranked');
const foreignSession = await startSession('sudoku', 'easy', 10);
await asUser(b);
check((await submit(await uuid(), foreignSession, 'sudoku', 'easy', 100, 0, 40)).ranked, false, 'another player cannot use your session');
await rejected(`select submit_game_result($1,null,'sudoku','easy',100,0,40,'win',now())`, [goodResult]);
await asUser(a);
check((await db.query('select score from leaderboard')).rows, [{score:1628}], 'best ranked result per player and server-calculated score');
await rejected('update game_results set seconds = 0');
// Score formula (migration 008); the same cases are checked in Dart.
const score = async (...args) => (await db.query('select game_score($1,$2,$3,$4,$5) s', args)).rows[0].s;
check(await score('sudoku', 'easy', 600, 0, 'win'), 1000, 'reference time earns half the maximum');
check(await score('sudoku', 'hard', 0, 0, 'win'), 6000, 'instant solve earns the maximum');
check(await score('sudoku', 'easy', 1000, 0, 'win') > await score('sudoku', 'easy', 990, 30, 'win'), true,
  'slow solves are no longer tied: mistakes still count');
check(await score('puzzle', 'easy', 604800, 10000, 'win'), 1, 'a win is worth at least 1');
check(await score('caro', 'hard', 30, 0, 'loss'), 0, 'losses score 0');
await db.exec('reset role;');
await db.query(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at)
  values('30000000-0000-4000-8000-000000000001',$1,'sudoku','easy',600,0,40,'win',now())`, [a]);
check((await db.query(`select score from game_results where id='30000000-0000-4000-8000-000000000001'`)).rows[0].score,
  1000, 'stored score column follows the new formula');
await asUser(a);

const messageId = '20000000-0000-4000-8000-000000000001';
await db.query(`insert into messages(id,sender_id,recipient_id,body) values($1,$2,$3,'Xin chào')`,[messageId,a,b]);
await db.query(`insert into messages(id,sender_id,recipient_id,body) values($1,$2,$3,'Xin chào') on conflict do nothing`,[messageId,a,b]);
check((await db.query('select * from messages')).rows.length,1,'message retry is idempotent');
await rejected(`insert into messages values(gen_random_uuid(),$1,$2,'forged',default,default)`,[b,a]);
await rejected(`insert into messages(id,sender_id,recipient_id,body) values(gen_random_uuid(),$1,$2,'  ')`,[a,b]);
await asUser(c);
check((await db.query('select * from messages')).rows.length,0,'third party cannot read private chat');
await asUser(b);
check((await db.query('select body from messages')).rows[0].body,'Xin chào','recipient can read chat');

await asUser(a);
const challenge = (await db.query(`select create_challenge($1,'easy') id`, [b])).rows[0].id;
await rejected(`select start_challenge($1)`,[challenge]);
await rejected(`select respond_challenge($1,true)`,[challenge]);
await asUser(c);
check((await db.query('select * from challenges')).rows.length,0,'third party cannot read invitation');
await rejected(`select respond_challenge($1,true)`,[challenge]);
await rejected(`select start_challenge($1)`,[challenge]);
await asUser(b);
await db.query(`select respond_challenge($1,true)`,[challenge]);
await rejected(`update challenges set status='completed' where id=$1`,[challenge]);
const startB = (await db.query(`select start_challenge($1) data`,[challenge])).rows[0].data;
const repeatStart = (await db.query(`select start_challenge($1) data`,[challenge])).rows[0].data;
check(startB.started_at, repeatStart.started_at, 'restart cannot reset timer');
await asUser(a);
const startA = (await db.query(`select start_challenge($1) data`,[challenge])).rows[0].data;
check(startA.givens, startB.givens, 'same puzzle for both players');

function solve(board) {
  const i = board.indexOf(0);
  if (i < 0) return board;
  const r = Math.floor(i/9), c = i%9;
  for (let n=1;n<=9;n++) {
    if (board.some((v,j) => v===n && (Math.floor(j/9)===r || j%9===c || (Math.floor(j/27)===Math.floor(r/3) && Math.floor((j%9)/3)===Math.floor(c/3))))) continue;
    board[i]=n;
    if (solve(board)) return board;
  }
  board[i]=0;
  return null;
}
const solution = solve([...startA.givens]);
assert(solution); assertions++;
await rejected(`select submit_challenge($1,$2,0)`, [challenge,Array(81).fill(1)]);
await rejected(`select submit_challenge($1,$2,-1)`, [challenge,solution]);
await rejected(`select submit_challenge($1,$2,0)`, [challenge,Array(81).fill(null)]);
const result = (await db.query(`select submit_challenge($1,$2,2) data`,[challenge,solution])).rows[0].data;
const repeat = (await db.query(`select submit_challenge($1,$2,2) data`,[challenge,solution])).rows[0].data;
check(result,repeat,'submit retry does not change result');
await rejected(`update challenge_runs set seconds=0`);
await asUser(b);
await db.query(`select submit_challenge($1,$2,100)`,[challenge,solution]);
check((await db.query('select status,winner_id from challenges where id=$1',[challenge])).rows,
  [{status:'completed',winner_id:a}],'winner determined when both players finish');
await asUser(c);
check((await db.query('select * from challenge_runs')).rows.length,0,'third party cannot read results');
await rejected(`select submit_challenge($1,$2,0)`,[challenge,solution]);

await asUser(a);
const caro = (await db.query(`select create_game_challenge($1,'easy','caro') id`, [b])).rows[0].id;
await asUser(b);
await db.query(`select respond_challenge($1,true)`, [caro]);
await db.query(`select start_caro_challenge($1)`, [caro]);
await rejected(`select play_caro_move($1,0)`, [caro]);
for (let col = 0; col < 5; col++) {
  await asUser(a);
  await db.query(`select play_caro_move($1,$2)`, [caro, col]);
  if (col < 4) {
    await asUser(b);
    await db.query(`select play_caro_move($1,$2)`, [caro, 15 + col]);
  }
}
check((await db.query('select status,winner_id from challenges where id=$1',[caro])).rows,
  [{status:'completed',winner_id:a}],'five Caro marks complete the challenge');

// Vietnamese rule: X fills row 2 cols 1-5 while O holds cols 0 and 6.
await asUser(a);
const blockedCaro = (await db.query(`select create_game_challenge($1,'easy','caro') id`, [b])).rows[0].id;
await asUser(b);
await db.query(`select respond_challenge($1,true)`, [blockedCaro]);
await db.query(`select start_caro_challenge($1)`, [blockedCaro]);
const blockedMoves = [[a, 31], [b, 30], [a, 32], [b, 36], [a, 33], [b, 75], [a, 34], [b, 76], [a, 35]];
for (const [player, cell] of blockedMoves) {
  await asUser(player);
  await db.query(`select play_caro_move($1,$2)`, [blockedCaro, cell]);
}
check((await db.query('select status,winner_id,turn_id from caro_matches where challenge_id=$1',[blockedCaro])).rows,
  [{status:'playing',winner_id:null,turn_id:b}],'five blocked at both ends does not win');
check((await db.query('select status from challenges where id=$1',[blockedCaro])).rows,
  [{status:'accepted'}],'blocked five keeps the challenge running');

// Deadlines, resign and the Caro move clock (migration 006). Time passing is
// simulated by moving timestamps back as the database owner.
async function rejectedWith(sql, params, pattern) {
  await assert.rejects(() => db.query(sql, params), (e) => pattern.test(e.message), sql); assertions++;
}
async function backdate(sql, id) {
  const sub = (await db.query(`select current_setting('request.jwt.claim.sub') sub`)).rows[0].sub;
  await db.exec('reset role;');
  await db.query(sql, [id]);
  await asUser(sub);
}
const challengeRow = async (id) => (await db.query(
  'select status,winner_id,end_reason from challenges where id=$1', [id])).rows[0];
async function newChallenge(game, accept = true) {
  await asUser(a);
  const id = (await db.query(`select create_game_challenge($1,'easy',$2) id`, [b, game])).rows[0].id;
  if (accept) {
    await asUser(b);
    await db.query(`select respond_challenge($1,true)`, [id]);
  }
  return id;
}

const staleInvite = await newChallenge('sudoku', false);
await backdate(`update challenges set expires_at = now() - interval '1 minute' where id = $1`, staleInvite);
await asUser(b);
await rejectedWith(`select respond_challenge($1,true)`, [staleInvite], /hết hạn/);

// Sudoku: whoever submitted before the 24-hour deadline wins.
const lateSudoku = await newChallenge('sudoku');
await asUser(a);
const lateGivens = (await db.query(`select start_challenge($1) data`, [lateSudoku])).rows[0].data.givens;
await db.query(`select submit_challenge($1,$2,0)`, [lateSudoku, solve([...lateGivens])]);
await asUser(b);
await db.query(`select start_challenge($1)`, [lateSudoku]);
await backdate(`update challenges set deadline_at = now() - interval '1 minute' where id = $1`, lateSudoku);
check((await db.query(`select submit_challenge($1,$2,0) data`, [lateSudoku, solve([...lateGivens])])).rows[0].data,
  {expired: true}, 'answer after the deadline does not count');
check(await challengeRow(lateSudoku), {status: 'completed', winner_id: a, end_reason: 'timeout'},
  'player who submitted in time wins');

const idleSudoku = await newChallenge('sudoku');
await backdate(`update challenges set deadline_at = now() - interval '1 minute' where id = $1`, idleSudoku);
check((await db.query(`select start_challenge($1) data`, [idleSudoku])).rows[0].data, {status: 'completed'},
  'opening an expired challenge reports it finished');
check(await challengeRow(idleSudoku), {status: 'completed', winner_id: null, end_reason: 'timeout'},
  'nobody submitted: draw');

const resignSudoku = await newChallenge('sudoku');
await asUser(a);
const resignGivens = (await db.query(`select start_challenge($1) data`, [resignSudoku])).rows[0].data.givens;
await db.query(`select submit_challenge($1,$2,0)`, [resignSudoku, solve([...resignGivens])]);
await rejectedWith(`select resign_challenge($1)`, [resignSudoku], /đã nộp bài/);
await asUser(c);
await rejected(`select resign_challenge($1)`, [resignSudoku]);
await rejected(`select check_challenge_timeout($1)`, [resignSudoku]);
await asUser(b);
await db.query(`select resign_challenge($1)`, [resignSudoku]);
check(await challengeRow(resignSudoku), {status: 'completed', winner_id: a, end_reason: 'resign'},
  'resigning gives the win to the opponent');
await rejected(`select resign_challenge($1)`, [resignSudoku]);

// Caro: the clock starts once both players join; running out loses.
const timedCaro = await newChallenge('caro');
await asUser(a);
await db.query(`select start_caro_challenge($1)`, [timedCaro]);
check((await db.query('select turn_deadline from caro_matches where challenge_id=$1', [timedCaro])).rows[0].turn_deadline,
  null, 'no move clock while the opponent is away');
await asUser(b);
await db.query(`select start_caro_challenge($1)`, [timedCaro]);
check((await db.query(`select turn_deadline > now() ok from caro_matches where challenge_id=$1`, [timedCaro])).rows[0].ok,
  true, 'move clock starts when both players joined');
await asUser(a);
await db.query(`select play_caro_move($1,112)`, [timedCaro]);
await asUser(b);
check((await db.query(`select check_challenge_timeout($1) done`, [timedCaro])).rows[0].done, false,
  'no timeout while time remains');
await backdate(`update caro_matches set turn_deadline = now() - interval '1 second' where challenge_id = $1`, timedCaro);
await db.query(`select play_caro_move($1,113)`, [timedCaro]);
check((await db.query('select status,winner_id,end_reason,board[114] late from caro_matches where challenge_id=$1', [timedCaro])).rows,
  [{status: 'completed', winner_id: a, end_reason: 'timeout', late: 0}], 'a move after the clock ran out loses and is not played');
check(await challengeRow(timedCaro), {status: 'completed', winner_id: a, end_reason: 'timeout'},
  'Caro timeout completes the challenge');

const noShowCaro = await newChallenge('caro');
await asUser(b);
await db.query(`select start_caro_challenge($1)`, [noShowCaro]);
await backdate(`update challenges set deadline_at = now() - interval '1 minute' where id = $1`, noShowCaro);
check((await db.query(`select check_challenge_timeout($1) done`, [noShowCaro])).rows[0].done, true,
  'waiting player can claim the timeout');
check(await challengeRow(noShowCaro), {status: 'completed', winner_id: b, end_reason: 'timeout'},
  'player who never came to the board loses');
check((await db.query(`select start_caro_challenge($1) data`, [noShowCaro])).rows[0].data.status, 'completed',
  'a finished match can still be opened');

const resignCaro = await newChallenge('caro');
await asUser(a);
await db.query(`select start_caro_challenge($1)`, [resignCaro]);
await db.query(`select resign_challenge($1)`, [resignCaro]);
check((await db.query('select status,winner_id,end_reason,turn_id from caro_matches where challenge_id=$1', [resignCaro])).rows,
  [{status: 'completed', winner_id: b, end_reason: 'resign', turn_id: null}], 'resigning ends the Caro match');
await asUser(b);
await rejectedWith(`select play_caro_move($1,0)`, [resignCaro], /kết thúc/);
await rejected('select settle_challenge_deadline($1)', [resignCaro]);
// Challenge boards are a graded template of the same level with digits relabelled.
await db.exec('reset role;');
const templates = (await db.query('select level, givens from challenge_templates')).rows;
check(['easy', 'medium', 'hard'].map((l) => templates.filter((t) => t.level === l).length), [6, 6, 6],
  'six graded templates per level');
for (const level of ['easy', 'medium', 'hard']) {
  await asUser(a);
  const id = (await db.query(`select create_game_challenge($1,$2,'sudoku') id`, [b, level])).rows[0].id;
  await asUser(b);
  await db.query(`select respond_challenge($1,true)`, [id]);
  const givens = (await db.query(`select start_challenge($1) data`, [id])).rows[0].data.givens;
  const fromTemplate = templates.filter((t) => t.level === level).some(({givens: raw}) => {
    const labels = new Map();
    return [...raw].every((ch, i) => {
      const digit = Number(ch);
      if ((digit === 0) !== (givens[i] === 0)) return false;
      if (digit === 0) return true;
      if (!labels.has(digit)) labels.set(digit, givens[i]);
      return labels.get(digit) === givens[i];
    }) && new Set(labels.values()).size === labels.size;
  });
  check(fromTemplate, true, `${level} challenge uses a ${level} template`);
  check(solve([...givens]) !== null, true, `${level} challenge board is solvable`);
}
await asUser(a);
check((await db.query(`select create_challenge($1,'hard') id`, [b])).rows.length, 1, 'legacy create_challenge still works');

// The sender can withdraw a pending invite (migration 009).
const withdrawn = await newChallenge('sudoku', false);
await asUser(b);
await rejectedWith(`select cancel_challenge($1)`, [withdrawn], /Chỉ người gửi/);
await asUser(c);
await rejected(`select cancel_challenge($1)`, [withdrawn]);
await asUser(a);
await db.query(`select cancel_challenge($1)`, [withdrawn]);
check(await challengeRow(withdrawn), {status: 'cancelled', winner_id: null, end_reason: null}, 'sender cancels a pending invite');
await rejected(`select cancel_challenge($1)`, [withdrawn]);
await asUser(b);
await rejected(`select respond_challenge($1,true)`, [withdrawn]);
check((await db.query('select status from challenges where id=$1', [withdrawn])).rows[0].status, 'cancelled',
  'opponent sees the cancelled invite and cannot accept it');
const acceptedInvite = await newChallenge('sudoku');
await asUser(a);
await rejectedWith(`select cancel_challenge($1)`, [acceptedInvite], /Chỉ người gửi/);
check((await challengeRow(acceptedInvite)).status, 'accepted', 'an accepted challenge cannot be cancelled');

// Ties go to whoever got there first; anyone can look up their own rank (010).
await db.exec('reset role;');
await db.query(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at,ranked,created_at) values
  ('40000000-0000-4000-8000-000000000001',$1,'sudoku','easy',100,1,40,'win',now(),true,now() - interval '1 hour'),
  ('40000000-0000-4000-8000-000000000002',$2,'sudoku','easy',200,1,40,'win',now(),true,now() - interval '2 hours')`, [b, c]);
await asUser(c);
check((await db.query(`select user_id, score from leaderboard where game='sudoku' and difficulty='easy'
  order by score desc, seconds, mistakes, achieved_at`)).rows.map((r) => r.user_id), [b, a, c],
  'equal scores are ordered by who achieved them first');
const myRank = async () => (await db.query(`select my_leaderboard_rank('sudoku','easy') r`)).rows[0].r;
check(await myRank(), {rank: 3, score: 1425, seconds: 200, mistakes: 1}, 'own rank and result');
await asUser(b);
check((await myRank()).rank, 1, 'earlier equal score ranks first');
await asUser(a);
check((await myRank()).rank, 2, 'later equal score ranks second');
check((await db.query(`select my_leaderboard_rank('sudoku','hard') r`)).rows[0].r, null, 'no ranked win: no rank');

const liveCaro = await newChallenge('caro');
await rejected(`select start_challenge($1)`, [liveCaro]);
await rejected(`select submit_challenge($1,$2,0)`, [liveCaro, solve([...lateGivens])]);
check(await challengeRow(liveCaro), {status: 'accepted', winner_id: null, end_reason: null},
  'Sudoku functions cannot touch a Caro challenge');
await asUser(c);
check((await db.query('select * from caro_matches')).rows.length,0,'third party cannot read Caro board');
await db.exec(`reset role; set role anon; set request.jwt.claim.sub = '';`);
await rejected('select * from profiles');
await rejected(`select create_challenge($1,'easy')`,[b]);
// Privilege errors (42501), not the functions' own auth checks, must stop anon.
for (const sql of [
  `select create_challenge('${b}','easy')`,
  `select create_game_challenge('${b}','easy','caro')`,
  `select respond_challenge('${caro}',true)`,
  `select start_challenge('${challenge}')`,
  `select submit_challenge('${challenge}','{}'::integer[],0)`,
  `select start_caro_challenge('${caro}')`,
  `select play_caro_move('${caro}',0)`,
  'select * from caro_matches',
  `select resign_challenge('${caro}')`,
  `select cancel_challenge('${caro}')`,
  `select my_leaderboard_rank('sudoku','easy')`,
  `select check_challenge_timeout('${caro}')`,
  `select start_game_session('sudoku','easy')`,
  `select submit_game_result(gen_random_uuid(),null,'sudoku','easy',100,0,40,'win',now())`,
]) await denied(sql);
console.log(`Backend migration and ${assertions} assertions passed (embedded PostgreSQL).`);
await db.close();
