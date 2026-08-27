// Desmos Controller+ multiplayer relay + static file server.
// Run with: node server.js   (serves the game AND the multiplayer WebSocket on one port)
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 8000;
const ROOT = __dirname;
const LEADERBOARD_FILE = path.join(ROOT, 'leaderboard.json');
const MAX_PLAYERS = 4;
const MAX_NAME_LEN = 16;
// mirrors the client's WEAPONS damage values — caps a claimed hit at the
// strongest legitimate weapon so a modified client can't spoof huge damage
const WEAPONS = { bow: 3, knife: 2, rifle: 5, machinegun: 1 };
function finiteNum(v, fallback) { return Number.isFinite(v) ? v : (Number.isFinite(fallback) ? fallback : 0); }

/* ---------------- leaderboard (simple JSON file, global/world-wide) ---------------- */
function loadLeaderboard() {
  try { return JSON.parse(fs.readFileSync(LEADERBOARD_FILE, 'utf8')); }
  catch (e) { return []; }
}
function saveLeaderboard(list) {
  try { fs.writeFileSync(LEADERBOARD_FILE, JSON.stringify(list)); } catch (e) { /* ignore disk errors */ }
}
let leaderboard = loadLeaderboard();
function submitScore(name, score) {
  name = String(name || 'Player').slice(0, MAX_NAME_LEN);
  score = Math.max(0, Math.min(1e9, Number(score) || 0));
  leaderboard.push({ name, score, ts: Date.now() });
  leaderboard.sort((a, b) => b.score - a.score);
  leaderboard = leaderboard.slice(0, 200);
  saveLeaderboard(leaderboard);
  return leaderboard.slice(0, 50);
}

/* ---------------- static file serving ---------------- */
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };
function serveStatic(req, res) {
  let reqPath = decodeURIComponent(req.url.split('?')[0]);
  if (reqPath === '/') reqPath = '/index.html';
  const filePath = path.normalize(path.join(ROOT, reqPath));
  if (!filePath.startsWith(ROOT)) { res.writeHead(403); res.end('Forbidden'); return; }
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/leaderboard')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(leaderboard.slice(0, 50)));
    return;
  }
  serveStatic(req, res);
});

/* ---------------- multiplayer rooms ---------------- */
const rooms = new Map(); // code -> room

function makeRoomCode() {
  let code;
  do { code = crypto.randomBytes(3).toString('hex').toUpperCase().slice(0, 4); } while (rooms.has(code));
  return code;
}
function roomSummary(room) {
  return {
    code: room.code,
    hostId: room.hostId,
    players: [...room.players.values()].map(p => ({ id: p.id, name: p.name, color: p.color, isHost: p.id === room.hostId })),
  };
}
function broadcast(room, msg, exceptId) {
  const raw = JSON.stringify(msg);
  for (const p of room.players.values()) {
    if (p.id !== exceptId && p.ws.readyState === WebSocket.OPEN) p.ws.send(raw);
  }
}
function send(ws, msg) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}
function closeRoom(room, reason) {
  broadcast(room, { type: 'roomClosed', reason });
  rooms.delete(room.code);
}
function removePlayer(ws) {
  const { roomCode, playerId } = ws._mp || {};
  if (!roomCode) return;
  const room = rooms.get(roomCode);
  if (!room) return;
  room.players.delete(playerId);
  if (playerId === room.hostId || room.players.size === 0) {
    closeRoom(room, playerId === room.hostId ? 'host_left' : 'empty');
  } else {
    broadcast(room, { type: 'playerLeft', playerId });
  }
}

const wss = new WebSocketServer({ server, path: '/mpws', maxPayload: 2 * 1024 * 1024 });

wss.on('connection', ws => {
  ws._mp = null;
  ws.on('message', raw => {
    let msg;
    try { msg = JSON.parse(raw); } catch (e) { return; }
    if (!msg || typeof msg.type !== 'string') return;

    if (msg.type === 'host') {
      if (ws._mp) return; // already hosting/joined on this connection — ignore to avoid an orphaned room
      const code = makeRoomCode();
      const playerId = crypto.randomUUID();
      const player = { id: playerId, ws, name: String(msg.name || 'Host').slice(0, MAX_NAME_LEN), x: 0, y: 0, z: 0, ry: 0, hp: 25, maxHp: 25, score: 0, weaponKey: 'bow', alive: true, color: msg.color || '#3d6cff' };
      const levelData = msg.levelData && typeof msg.levelData === 'object' ? msg.levelData : { name: 'Untitled', objects: [] };
      const room = { code, hostId: playerId, levelData, players: new Map([[playerId, player]]), createdAt: Date.now() };
      rooms.set(code, room);
      ws._mp = { roomCode: code, playerId };
      send(ws, { type: 'hosted', code, playerId, isHost: true, levelData: room.levelData, players: roomSummary(room).players });
      return;
    }

    if (msg.type === 'join') {
      if (ws._mp) return; // already hosting/joined on this connection
      const code = String(msg.code || '').toUpperCase();
      const room = rooms.get(code);
      if (!room) { send(ws, { type: 'error', message: 'Room not found.' }); return; }
      if (room.players.size >= MAX_PLAYERS) { send(ws, { type: 'error', message: 'Room is full (max 4 players).' }); return; }
      const playerId = crypto.randomUUID();
      const player = { id: playerId, ws, name: String(msg.name || 'Player').slice(0, MAX_NAME_LEN), x: 0, y: 0, z: 0, ry: 0, hp: 25, maxHp: 25, score: 0, weaponKey: 'bow', alive: true, color: msg.color || '#3d6cff' };
      room.players.set(playerId, player);
      ws._mp = { roomCode: code, playerId };
      send(ws, {
        type: 'joined', code, playerId, isHost: false, levelData: room.levelData,
        players: roomSummary(room).players,
      });
      broadcast(room, { type: 'playerJoined', playerId, name: player.name, color: player.color }, playerId);
      return;
    }

    // every other message type requires an established room membership
    const mp = ws._mp;
    if (!mp) return;
    const room = rooms.get(mp.roomCode);
    if (!room) return;
    const player = room.players.get(mp.playerId);
    if (!player) return;

    if (msg.type === 'state') {
      const x = finiteNum(msg.x, player.x), y = finiteNum(msg.y, player.y), z = finiteNum(msg.z, player.z), ry = finiteNum(msg.ry, player.ry);
      const hp = finiteNum(msg.hp, player.hp), maxHp = finiteNum(msg.maxHp, player.maxHp), score = finiteNum(msg.score, player.score);
      const weaponKey = WEAPONS[msg.weaponKey] ? msg.weaponKey : player.weaponKey;
      const alive = msg.alive !== false;
      player.x = x; player.y = y; player.z = z; player.ry = ry;
      player.hp = hp; player.maxHp = maxHp; player.score = score;
      player.weaponKey = weaponKey; player.alive = alive;
      broadcast(room, { type: 'playerState', playerId: player.id, x, y, z, ry, hp, maxHp, score, weaponKey, alive }, player.id);
    } else if (msg.type === 'shootHit') {
      const target = room.players.get(msg.targetId);
      const maxDamage = WEAPONS[player.weaponKey] || 5;
      if (target) send(target.ws, { type: 'hit', fromId: player.id, fromName: player.name, damage: Math.max(0, Math.min(maxDamage, Number(msg.damage) || 0)) });
    } else if (msg.type === 'chat') {
      const text = String(msg.text || '').slice(0, 240);
      if (text.trim()) broadcast(room, { type: 'chat', playerId: player.id, name: player.name, text });
    } else if (msg.type === 'submitScore') {
      send(ws, { type: 'leaderboard', list: submitScore(msg.name || player.name, msg.score) });
    } else if (msg.type === 'getLeaderboard') {
      send(ws, { type: 'leaderboard', list: leaderboard.slice(0, 50) });
    } else if (msg.type === 'start') {
      if (player.id === room.hostId) broadcast(room, { type: 'gameStarted' });
    }
  });

  ws.on('close', () => removePlayer(ws));
  ws.on('error', () => {});
});

server.listen(PORT, () => {
  console.log(`Desmos Controller+ server running on http://localhost:${PORT}`);
  console.log(`Multiplayer WebSocket at ws://localhost:${PORT}/mpws`);
});
