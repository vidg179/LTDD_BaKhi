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
`);
const migration = await readFile(new URL('../../supabase/migrations/001_game_app.sql', import.meta.url), 'utf8');
await db.exec(migration);
const caroMigration = await readFile(new URL('../../supabase/migrations/002_caro_challenges.sql', import.meta.url), 'utf8');
await db.exec(caroMigration);
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
await asUser(a);
check((await db.query('select * from public.profiles')).rows.length, 3, 'signup trigger creates profiles');
await rejected('select * from public.challenge_puzzles');
await rejected(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at) values(gen_random_uuid(),$1,'sudoku','easy',10,0,1,'win',now())`, [b]);
await db.query(`insert into game_results(id,user_id,game,difficulty,seconds,mistakes,moves,outcome,played_at) values(gen_random_uuid(),$1,'sudoku','easy',10,1,20,'win',now()),(gen_random_uuid(),$1,'sudoku','easy',50,1,20,'win',now())`, [a]);
check((await db.query('select score from leaderboard')).rows, [{score:1880}], 'best result per player and server-calculated score');
await rejected('update game_results set seconds = 0');

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
await asUser(c);
check((await db.query('select * from caro_matches')).rows.length,0,'third party cannot read Caro board');
await db.exec(`reset role; set role anon; set request.jwt.claim.sub = '';`);
await rejected('select * from profiles');
await rejected(`select create_challenge($1,'easy')`,[b]);
console.log(`Backend migration and ${assertions} assertions passed (embedded PostgreSQL).`);
await db.close();
