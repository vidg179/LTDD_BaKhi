import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// End-to-end check of a running BaKhi_API in Development (no SMTP): password
// reset codes are read from the API's console log.
//   API_URL=http://localhost:5080 CODE_LOG=<file with the API output> node api.mjs
const api = process.env.API_URL ?? 'http://localhost:5080';
const codeLog = process.env.CODE_LOG;
assert(codeLog, 'CODE_LOG must name the file that holds the API output');

let assertions = 0;
const check = (value, expected, label) => { assert.deepEqual(value, expected, label); assertions++; };
const ok = (value, label) => { assert(value, label); assertions++; };

async function call(method, path, body, token) {
  const response = await fetch(api + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : null };
}

async function codeFor(email, purpose) {
  const pattern = new RegExp(`${purpose} code for ${email.replace(/[.+]/g, '\\$&')}: (\\d{6})`, 'g');
  for (let i = 0; i < 50; i++) {
    const matches = [...(await readFile(codeLog, 'utf8')).matchAll(pattern)];
    if (matches.length) return matches.at(-1)[1];
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`no ${purpose} code for ${email}`);
}

const run = Date.now().toString(36);
async function newPlayer(name) {
  const email = `${name.normalize("NFD").replace(/[^A-Za-z]/g, "").toLowerCase()}.${run}@example.com`;
  const password = 'matkhau123';
  // No confirmation code: registering signs the player in.
  const session = await call('POST', '/api/auth/register', { displayName: name, email, password });
  check([session.status, session.data.user.display_name], [200, name], `${name} registers and is signed in`);
  return { email, password, token: session.data.access_token, refresh: session.data.refresh_token, id: session.data.user.id };
}

// ---------- Accounts ----------
check((await call('GET', '/api/players')).status, 401, 'player endpoints need a token');
check((await call('POST', '/api/auth/register', { displayName: 'Xấu', email: 'không-dấu@example.com', password: 'matkhau123' })).data.code,
  'email_address_invalid', 'accented email is refused');
check((await call('POST', '/api/auth/register', { displayName: 'Yếu', email: `weak.${run}@example.com`, password: 'abcdefgh' })).data.code,
  'weak_password', 'password without digits is refused');

const a = await newPlayer('An');
const b = await newPlayer('Bình');
const c = await newPlayer('Chi');
check((await call('POST', '/api/auth/register', { displayName: 'An', email: a.email, password: 'matkhau456' })).data.code,
  'user_already_exists', 'an email cannot register twice');
check((await call('POST', '/api/auth/login', { email: a.email, password: 'sai12345' })).data.code,
  'invalid_credentials', 'wrong password');
const login = await call('POST', '/api/auth/login', { email: ` ${a.email.toUpperCase()} `, password: a.password });
check(login.status, 200, 'sign in ignores case and spaces in the email');
check((await call('GET', '/api/auth/me', undefined, login.data.access_token)).data,
  { id: a.id, email: a.email, display_name: 'An' }, 'me');
const refreshed = await call('POST', '/api/auth/refresh', { refreshToken: login.data.refresh_token });
check(refreshed.status, 200, 'refresh token buys a new session');
check((await call('POST', '/api/auth/refresh', { refreshToken: login.data.refresh_token })).status, 401,
  'a refresh token works only once');
check((await call('GET', '/api/auth/me', undefined, a.token.slice(0, -2) + 'xx')).status, 401, 'forged token is refused');

const others = (await call('GET', '/api/players', undefined, b.token)).data;
ok(others.some((p) => p.id === a.id && p.display_name === 'An'), 'players list shows confirmed players');
ok(!others.some((p) => p.id === b.id), 'players list leaves out yourself');

// ---------- Realtime ----------
function listen(player) {
  const socket = new WebSocket(api.replace(/^http/, 'ws') + '/ws');
  const events = [];
  const ready = new Promise((resolve, reject) => {
    socket.onopen = () => socket.send(JSON.stringify({ access_token: player.token }));
    socket.onerror = reject;
    socket.onmessage = (m) => {
      const event = JSON.parse(m.data);
      if (event.type === 'ready') resolve();
      else events.push(event);
    };
  });
  return { socket, events, ready };
}
async function waitFor(events, predicate, label) {
  for (let i = 0; i < 50; i++) {
    const found = events.find(predicate);
    if (found) { assertions++; return found; }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`timed out: ${label}`);
}
const liveA = listen(a), liveB = listen(b), liveC = listen(c);
await Promise.all([liveA.ready, liveB.ready, liveC.ready]);
const intruder = new WebSocket(api.replace(/^http/, 'ws') + '/ws');
const closed = new Promise((resolve) => { intruder.onclose = (e) => resolve(e.code); });
intruder.onopen = () => intruder.send(JSON.stringify({ access_token: 'not-a-token' }));
check(await closed, 4001, 'socket without a valid token is closed');

// ---------- Messages ----------
const messageId = crypto.randomUUID();
const sent = await call('POST', '/api/messages', { id: messageId, recipientId: b.id, body: '  Chào Bình 👋  ' }, a.token);
check([sent.status, sent.data.body], [200, 'Chào Bình 👋'], 'message is stored trimmed');
await call('POST', '/api/messages', { id: messageId, recipientId: b.id, body: 'Chào Bình 👋' }, a.token);
const pushed = await waitFor(liveB.events, (e) => e.table === 'messages' && e.row.id === messageId, 'B is told about the message');
check([pushed.op, pushed.row.sender_id, pushed.row.recipient_id], ['INSERT', a.id, b.id], 'pushed row');
check((await call('GET', `/api/messages/${a.id}`, undefined, b.token)).data.map((m) => m.body), ['Chào Bình 👋'],
  'retried send is stored once');
check((await call('GET', `/api/messages/${b.id}`, undefined, c.token)).data, [], 'a third player sees nothing');
check((await call('POST', '/api/messages', { recipientId: b.id, body: '   ' }, a.token)).status, 400, 'blank message');

// ---------- Caro online ----------
const caro = (await call('POST', '/api/challenges', { opponentId: b.id, game: 'caro', difficulty: 'easy' }, a.token)).data;
await waitFor(liveB.events, (e) => e.table === 'challenges' && e.row.id === caro && e.op === 'INSERT', 'B is told about the invite');
check((await call('POST', `/api/challenges/${caro}/accept`, undefined, c.token)).status, 400, 'only the invited player can accept');
check((await call('POST', `/api/challenges/${caro}/accept`, undefined, b.token)).status, 204, 'B accepts');
check((await call('GET', '/api/challenges', undefined, a.token)).data.find((x) => x.id === caro).status, 'accepted',
  'A sees the accepted challenge');
check((await call('POST', `/api/caro/${caro}/start`, undefined, a.token)).data.mark, 1, 'challenger plays X');
check((await call('POST', `/api/caro/${caro}/start`, undefined, b.token)).data.mark, 2, 'opponent plays O');
check((await call('POST', `/api/caro/${caro}/moves`, { row: 7, col: 7 }, a.token)).status, 204, 'A moves');
const board = await waitFor(liveB.events, (e) => e.table === 'caro_matches' && e.row.board[112] === 1, 'B sees the move');
check(board.row.turn_id, b.id, 'turn passes to B');
const early = await call('POST', `/api/caro/${caro}/moves`, { row: 0, col: 0 }, a.token);
check([early.status, early.data.message], [400, 'Chưa đến lượt của bạn.'], 'rule errors come back in Vietnamese');
check((await call('POST', `/api/caro/${caro}/moves`, { row: 15, col: 0 }, b.token)).status, 400, 'off-board move');
check((await call('GET', `/api/caro/${caro}`, undefined, c.token)).data, [], 'a third player cannot see the board');
check((await call('POST', `/api/challenges/${caro}/check-timeout`, undefined, b.token)).data, false, 'no timeout yet');
check((await call('POST', `/api/challenges/${caro}/resign`, undefined, b.token)).status, 204, 'B resigns');
await waitFor(liveA.events, (e) => e.table === 'challenges' && e.row.id === caro && e.row.winner_id === a.id,
  'A is told they won');

// ---------- Sudoku challenge ----------
const sudoku = (await call('POST', '/api/challenges', { opponentId: a.id, game: 'sudoku', difficulty: 'medium' }, b.token)).data;
check((await call('POST', `/api/challenges/${sudoku}/cancel`, undefined, a.token)).status, 400, 'only the sender cancels');
await call('POST', `/api/challenges/${sudoku}/accept`, undefined, a.token);
const givens = (await call('POST', `/api/challenges/${sudoku}/sudoku/start`, undefined, a.token)).data.givens;
check(givens.length, 81, 'Sudoku challenge board');
check((await call('POST', `/api/challenges/${sudoku}/sudoku/submit`, { answer: Array(81).fill(1), mistakes: 0 }, a.token)).status,
  400, 'wrong answer is refused');
check((await call('GET', `/api/challenges/${sudoku}/runs`, undefined, a.token)).data.length, 1, 'own run is listed');

// ---------- Solo games and leaderboard ----------
const session = (await call('POST', '/api/games/sessions', { game: 'sudoku', difficulty: 'easy' }, a.token)).data;
ok(session.id, 'server-timed session');
const result = await call('POST', '/api/games/results', {
  resultId: crypto.randomUUID(), sessionId: session.id, game: 'sudoku', difficulty: 'easy',
  seconds: 300, mistakes: 0, moves: 45, outcome: 'win', playedAt: new Date().toISOString(),
}, a.token);
check(result.data.ranked, false, 'a result claiming more time than the session took is not ranked');
check((await call('GET', '/api/games/score?game=sudoku&difficulty=easy&seconds=600&mistakes=0', undefined, a.token)).data,
  1000, 'score formula');
ok(Array.isArray((await call('GET', '/api/leaderboard?game=sudoku&difficulty=easy', undefined, a.token)).data), 'leaderboard');
check((await call('GET', '/api/leaderboard/me?game=caro&difficulty=hard', undefined, a.token)).data, null, 'no rank yet');

// ---------- Password reset ----------
check((await call('POST', '/api/auth/forgot-password', { email: `nobody.${run}@example.com` })).status, 200,
  'unknown address gets the same answer');
await call('POST', '/api/auth/forgot-password', { email: c.email });
check((await call('POST', '/api/auth/forgot-password', { email: c.email })).data.code, 'over_email_send_rate_limit',
  'a new reset code waits one minute');
check((await call('POST', '/api/auth/verify-otp', { email: c.email, code: '000000', type: 'recovery' })).data.code,
  'otp_expired', 'wrong reset code is refused');
const recovery = await call('POST', '/api/auth/verify-otp', { email: c.email, code: await codeFor(c.email, 'recovery'), type: 'recovery' });
check(recovery.status, 200, 'reset code signs the player in');
check((await call('PUT', '/api/auth/password', { password: c.password }, recovery.data.access_token)).data.code,
  'same_password', 'new password must differ');
check((await call('PUT', '/api/auth/password', { password: 'matkhaumoi9' }, recovery.data.access_token)).status, 204,
  'new password saved');
check((await call('POST', '/api/auth/login', { email: c.email, password: 'matkhaumoi9' })).status, 200,
  'sign in with the new password');
check((await call('POST', '/api/auth/logout', { refreshToken: recovery.data.refresh_token })).status, 204, 'logout');
check((await call('POST', '/api/auth/refresh', { refreshToken: recovery.data.refresh_token })).status, 401,
  'logged-out session cannot be refreshed');

check(liveC.events.filter((e) => e.table !== 'challenges' || e.row.challenger_id !== c.id).length, 0,
  'C was never told about A and B');
for (const live of [liveA, liveB, liveC]) live.socket.close();
console.log(`BaKhi_API end-to-end: ${assertions} assertions passed against ${api}.`);
