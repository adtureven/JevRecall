import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { initialState, publicState, decide, applyAction, ACTIONS, THRESHOLDS } from './lib/game.js';
import { requestDecision, JevError } from './lib/jev.js';

const staticFiles = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/style.css', ['style.css', 'text/css; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/favicon.svg', ['favicon.svg', 'image/svg+xml']],
]);
const SESSION_TTL = 6 * 60 * 60 * 1000;

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data));
}

async function readJson(req) {
  if (!req.headers['content-type']?.startsWith('application/json')) throw new JevError('请求必须使用 application/json。', 415);
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 8192) throw new JevError('请求过长。指令最多 500 个字符。', 413);
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString());
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch { throw new JevError('无效的 JSON 请求。', 400); }
}

export function createServer({ decisionFn = requestDecision, configured = Boolean(process.env.OPENROUTER_API_KEY && process.env.OPENROUTER_API_KEY !== 'your_openrouter_api_key'), model = process.env.JEV_MODEL || '~typesafe/jev-latest' } = {}) {
  const sessions = new Map();
  let activeRequests = 0;
  const timer = setInterval(() => {
    for (const [id, session] of sessions) if (!session.busy && Date.now() - session.touched > SESSION_TTL) sessions.delete(id);
  }, 60000).unref();

  function getSession(req, res) {
    const id = req.headers.cookie?.split(';').map(s => s.trim()).find(s => s.startsWith('orbit_session='))?.slice('orbit_session='.length);
    let session = sessions.get(id);
    if (session && !session.busy && Date.now() - session.touched > SESSION_TTL) { sessions.delete(id); session = null; }
    if (!session) {
      if (sessions.size >= 500) throw new JevError('本地会话数量已达上限，请稍后重试或重启服务。', 503);
      const sessionId = randomUUID();
      session = { state: initialState(), history: [], busy: false, pending: null, version: 0, touched: Date.now(), lastRequest: 0, calls: 0, totalCost: 0 };
      sessions.set(sessionId, session);
      res.setHeader('Set-Cookie', `orbit_session=${sessionId}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL / 1000}`);
    }
    session.touched = Date.now();
    return session;
  }
  function snapshot(session) {
    if (session.pending && session.pending.expires < Date.now()) session.pending = null;
    return { state: publicState(session.state), history: session.history, calls: session.calls, totalCost: session.totalCost, pending: session.pending ? { token: session.pending.token, action: session.pending.action, message: session.pending.message } : null };
  }

  const server = http.createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    try {
      if (!/^(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/.test(req.headers.host || '')) throw new JevError('此应用仅接受本机访问。', 403);
      const pathname = new URL(req.url, `http://${req.headers.host}`).pathname;
      if (req.method === 'GET' && staticFiles.has(pathname)) {
        const [name, type] = staticFiles.get(pathname);
        const data = await readFile(new URL(`./public/${name}`, import.meta.url));
        res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' });
        return res.end(data);
      }
      if (req.method === 'GET' && pathname === '/api/session') {
        const session = getSession(req, res);
        return json(res, 200, { ...snapshot(session), configured, model, thresholds: THRESHOLDS, actions: Object.fromEntries(Object.entries(ACTIONS).map(([key, { label, command }]) => [key, { label, command }])) });
      }
      if (req.method !== 'POST' || !['/api/command', '/api/confirm', '/api/reset'].includes(pathname)) return json(res, 404, { error: '未找到该页面或接口。' });
      const origin = req.headers.origin;
      if ((origin && origin !== `http://${req.headers.host}`) || req.headers['sec-fetch-site'] === 'cross-site') throw new JevError('不接受跨站请求。', 403);
      const body = await readJson(req);
      const session = getSession(req, res);
      if (session.busy) throw new JevError('上一条指令仍在处理中，请等待结果。', 409);

      if (pathname === '/api/reset') {
        session.state = initialState(); session.history = []; session.pending = null; session.version++;
        session.calls = 0; session.totalCost = 0;
        return json(res, 200, snapshot(session));
      }
      if (pathname === '/api/confirm') {
        const pending = session.pending;
        if (!pending || pending.token !== body.token || pending.version !== session.version || pending.expires < Date.now()) throw new JevError('该确认已失效，请重新输入指令。', 409);
        if (typeof body.confirm !== 'boolean') throw new JevError('请明确选择执行或取消。', 400);
        session.pending = null;
        let result;
        if (body.confirm) {
          result = applyAction(session.state, pending.action);
          session.state = result.state;
          session.version++;
        } else result = { status: 'cancelled', message: '已取消操作，飞船状态没有改变。' };
        const record = { id: randomUUID(), command: body.confirm ? `确认执行：${ACTIONS[pending.action].label}` : '取消危险操作', action: pending.action, status: result.status, message: result.message, turn: session.state.turn, time: new Date().toISOString(), decision: null };
        session.history.push(record);
        session.history = session.history.slice(-40);
        return json(res, 200, { ...snapshot(session), result: record });
      }
      if (typeof body.command !== 'string' || !body.command.trim() || body.command.length > 500) throw new JevError('请输入 1–500 个字符的指令。', 400);
      if (session.state.outcome !== 'active') throw new JevError('任务已经结束，请重新开始。', 409);
      if (session.pending && session.pending.expires >= Date.now()) throw new JevError('请先执行或取消待确认的危险操作。', 409);
      session.pending = null;
      if (activeRequests >= 4 || Date.now() - session.lastRequest < 500) throw new JevError('指令发送过快，请稍后再试。', 429);
      session.busy = true; session.lastRequest = Date.now(); activeRequests++;
      try {
        const command = body.command.trim();
        const decision = await decisionFn(session.state, command);
        const policy = decide(session.state, decision.raw.answers);
        let result = policy;
        if (policy.status === 'execute') {
          result = { ...applyAction(session.state, policy.action), action: policy.action };
          session.state = result.state;
          session.version++;
        }
        if (policy.status === 'confirm') session.pending = { token: randomUUID(), action: policy.action, message: policy.message, expires: Date.now() + 90000, version: session.version };
        session.calls++;
        const cost = decision.raw.usage?.cost;
        if (typeof cost === 'number' && Number.isFinite(cost) && cost >= 0) session.totalCost += cost;
        const record = { id: randomUUID(), command, action: result.action, status: result.status, message: result.message, turn: session.state.turn, time: new Date().toISOString(), decision };
        session.history.push(record);
        session.history = session.history.slice(-40);
        return json(res, 200, { ...snapshot(session), result: record });
      } finally { session.busy = false; activeRequests--; }
    } catch (error) {
      if (!res.headersSent) json(res, error instanceof JevError ? error.status : 500, { error: error instanceof JevError ? error.message : '本地服务发生错误，请重试。' });
      else res.end();
    }
  });
  server.on('close', () => clearInterval(timer));
  return server;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const port = Number(process.env.PORT || 3210);
  const server = createServer();
  server.on('error', error => { console.error(error.code === 'EADDRINUSE' ? `端口 ${port} 已被占用。请更改 .env 中的 PORT。` : error.message); process.exitCode = 1; });
  server.listen(port, '127.0.0.1', () => console.log(`深空救援 · http://localhost:${port}\nJEV model: ${process.env.JEV_MODEL || '~typesafe/jev-latest'}`));
}
