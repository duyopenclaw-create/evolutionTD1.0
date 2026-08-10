const http = require('http');
const fs   = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const { ACHIEVEMENTS, SECRET_ICONS } = require('./achievements');
const ACHIEVEMENTS_BY_ID = new Map(ACHIEVEMENTS.map(a => [a.id, a]));

const PORT = process.env.PORT || 8080;
const MIN_PLAYERS_TO_START = 2;
const MAX_PLAYERS_PER_ROOM = 8;
const MAX_CHAT_HISTORY = 200;
const MAX_TIMEOUT_SECONDS = 3600;
const DEFAULT_TIMEOUT_SECONDS = 60;
const RECONNECT_GRACE_MS = 120_000;
const HEARTBEAT_INTERVAL_MS = 30_000;
const GAME_MODES = ['normal', 'challenge', 'perfectionist', 'foggy', 'additive', 'humanbody', 'copyit', 'custom', 'solo'];
const BODY_SLOTS = ['Head', 'Torso', 'Left Arm', 'Right Arm', 'Hips', 'Left Leg', 'Right Leg', 'Feet'];
const RANK_COINS = [100, 75, 50, 25, 10, 5, 2, 1];
const ICON_CATALOG = [
  { id: 'star', emoji: '⭐', name: 'Star', price: 50 },
  { id: 'fire', emoji: '🔥', name: 'Fire', price: 75 },
  { id: 'heart', emoji: '❤️', name: 'Heart', price: 100 },
  { id: 'paint', emoji: '🎨', name: 'Painter', price: 150 },
  { id: 'sparkles', emoji: '✨', name: 'Sparkles', price: 200 },
  { id: 'trophy', emoji: '🏆', name: 'Trophy', price: 300 },
  { id: 'rocket', emoji: '🚀', name: 'Rocket', price: 400 },
  { id: 'gem', emoji: '💎', name: 'Gem', price: 500 },
  { id: 'crown', emoji: '👑', name: 'Crown', price: 650 },
  { id: 'wizard', emoji: '🧙', name: 'Wizard', price: 800 },
  { id: 'unicorn', emoji: '🦄', name: 'Unicorn', price: 900 },
  { id: 'dragon', emoji: '🐉', name: 'Dragon', price: 1000 },
];
const MOD_PRICE = 2500; // coins to buy mod status for the current room

// ── Persistent social data (friends) — plain JSON file, survives restarts ──
const SOCIAL_DATA_FILE = path.join(__dirname, 'social-data.json');

function loadSocialData() {
  try {
    const raw = fs.readFileSync(SOCIAL_DATA_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      users: parsed.users || {},
      usernameIndex: parsed.usernameIndex || {},
      friendships: parsed.friendships || {},
      friendRequests: parsed.friendRequests || {},
      wallets: parsed.wallets || {},
    };
  } catch (_) {
    return { users: {}, usernameIndex: {}, friendships: {}, friendRequests: {}, wallets: {} };
  }
}

let socialData = loadSocialData();

function saveSocialData() {
  try {
    fs.writeFileSync(SOCIAL_DATA_FILE, JSON.stringify(socialData, null, 2));
  } catch (err) {
    console.error('Failed to save social-data.json:', err.message);
  }
}

const STARTING_COINS = 100;

function blankWallet() {
  return { coins: STARTING_COINS, ownedIcons: [], equippedIcon: null, stats: {}, modesPlayedSet: {}, unlockedAchievements: [] };
}

function normalizeWallet(w) {
  if (!w.stats) w.stats = {};
  if (!w.modesPlayedSet) w.modesPlayedSet = {};
  if (!w.unlockedAchievements) w.unlockedAchievements = [];
  return w;
}

function getWallet(deviceId) {
  if (!deviceId || !socialData.wallets[deviceId]) return blankWallet();
  return normalizeWallet(socialData.wallets[deviceId]);
}

function ensureWallet(deviceId) {
  if (!socialData.wallets[deviceId]) socialData.wallets[deviceId] = blankWallet();
  return normalizeWallet(socialData.wallets[deviceId]);
}

// ---------- achievements ----------
function walletPayload(wallet) {
  return {
    coins: wallet.coins,
    ownedIcons: wallet.ownedIcons,
    equippedIcon: wallet.equippedIcon,
    unlockedAchievements: wallet.unlockedAchievements,
    stats: wallet.stats,
  };
}

function grantAchievement(deviceId, wallet, achId, player, room) {
  const ach = ACHIEVEMENTS_BY_ID.get(achId);
  if (!ach || wallet.unlockedAchievements.includes(achId)) return;
  wallet.unlockedAchievements.push(achId);
  if (ach.reward) {
    if (ach.reward.coins) wallet.coins += ach.reward.coins;
    if (ach.reward.icon && !wallet.ownedIcons.includes(ach.reward.icon)) {
      wallet.ownedIcons.push(ach.reward.icon);
      wallet.stats.iconsOwned = wallet.ownedIcons.length;
    }
  }
  saveSocialData();
  if (player) {
    // private — only the player who earned it sees the pop-up
    sendTo(player, {
      type: 'achievementUnlocked',
      achievement: { id: ach.id, name: ach.name, description: ach.description, reward: ach.reward || null },
      playerId: player.id,
      playerName: player.name,
    });
    sendTo(player, { type: 'wallet', ...walletPayload(wallet) });
  }
  checkAchievements(deviceId, wallet, player, room);
}

function checkAchievements(deviceId, wallet, player, room) {
  ACHIEVEMENTS.forEach(ach => {
    if (ach.secret || wallet.unlockedAchievements.includes(ach.id)) return;
    if ((wallet.stats[ach.statKey] || 0) >= ach.threshold) grantAchievement(deviceId, wallet, ach.id, player, room);
  });
}

function bumpStat(deviceId, key, amount, player, room) {
  if (!deviceId) return;
  const wallet = ensureWallet(deviceId);
  wallet.stats[key] = (wallet.stats[key] || 0) + amount;
  saveSocialData();
  checkAchievements(deviceId, wallet, player, room);
}

function markModePlayed(deviceId, mode, player, room) {
  if (!deviceId) return;
  const wallet = ensureWallet(deviceId);
  if (wallet.modesPlayedSet[mode]) return;
  wallet.modesPlayedSet[mode] = true;
  wallet.stats.modesPlayed = Object.keys(wallet.modesPlayedSet).length;
  saveSocialData();
  checkAchievements(deviceId, wallet, player, room);
}

const onlineUsers = new Map();   // userId -> ws (friends connection)
const wsIdentity = new Map();    // ws -> userId
const activeRoomByUser = new Map(); // userId -> current room code (for invites)

function getUsername(userId) {
  const u = socialData.users[userId];
  return u ? u.username : null;
}

function getFriendsSnapshot(userId) {
  const friendIds = socialData.friendships[userId] || [];
  const friends = friendIds.map(fid => ({
    userId: fid,
    username: getUsername(fid) || 'Unknown',
    online: onlineUsers.has(fid),
  }));
  const incoming = (socialData.friendRequests[userId] || []).map(r => ({ fromUserId: r.from, fromUsername: r.fromUsername }));
  const outgoing = [];
  Object.entries(socialData.friendRequests).forEach(([toId, reqs]) => {
    reqs.forEach(r => { if (r.from === userId) outgoing.push({ toUserId: toId, toUsername: getUsername(toId) || 'Unknown' }); });
  });
  return { friends, incoming, outgoing };
}

function sendIdentifiedSnapshot(ws, userId) {
  const username = getUsername(userId);
  const snap = getFriendsSnapshot(userId);
  ws.send(JSON.stringify({
    type: 'identified',
    userId,
    username,
    friends: snap.friends,
    incomingRequests: snap.incoming,
    outgoingRequests: snap.outgoing,
  }));
}

function sendFriendsUpdate(userId) {
  const ws = onlineUsers.get(userId);
  if (!ws || ws.readyState !== 1) return;
  const snap = getFriendsSnapshot(userId);
  ws.send(JSON.stringify({ type: 'friendsUpdate', friends: snap.friends, incomingRequests: snap.incoming, outgoingRequests: snap.outgoing }));
}

function tryClaimUsername(ws, userId, desiredUsername) {
  const clean = String(desiredUsername || '').trim().slice(0, 20);
  if (!clean) { ws.send(JSON.stringify({ type: 'usernameTaken', message: 'Please enter a username.' })); return; }
  const key = clean.toLowerCase();
  if (socialData.usernameIndex[key] && socialData.usernameIndex[key] !== userId) {
    ws.send(JSON.stringify({ type: 'usernameTaken', message: `"${clean}" is already taken.` }));
    return;
  }
  const existing = socialData.users[userId];
  if (existing && existing.username.toLowerCase() !== key) {
    delete socialData.usernameIndex[existing.username.toLowerCase()];
  }
  socialData.users[userId] = { username: clean, createdAt: existing ? existing.createdAt : Date.now() };
  socialData.usernameIndex[key] = userId;
  saveSocialData();
  sendIdentifiedSnapshot(ws, userId);
  (socialData.friendships[userId] || []).forEach(fid => sendFriendsUpdate(fid));
}

function handleIdentify(ws, msg) {
  const userId = String(msg.userId || '').slice(0, 100);
  if (!userId) return;
  wsIdentity.set(ws, userId);
  onlineUsers.set(userId, ws);

  if (!socialData.users[userId] && msg.username) {
    tryClaimUsername(ws, userId, msg.username);
  } else {
    sendIdentifiedSnapshot(ws, userId);
  }

  (socialData.friendships[userId] || []).forEach(fid => sendFriendsUpdate(fid));
}

function handleClaimUsername(ws, msg) {
  const userId = wsIdentity.get(ws);
  if (!userId) return;
  tryClaimUsername(ws, userId, msg.username);
}

function handleSendFriendRequest(ws, msg) {
  const userId = wsIdentity.get(ws);
  if (!userId || !socialData.users[userId]) return;
  const toUsername = String(msg.toUsername || '').trim();
  const toUserId = socialData.usernameIndex[toUsername.toLowerCase()];
  if (!toUserId) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: `No user found with username "${toUsername}".` }));
    return;
  }
  if (toUserId === userId) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: "You can't friend yourself." }));
    return;
  }
  if ((socialData.friendships[userId] || []).includes(toUserId)) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: `You're already friends with ${toUsername}.` }));
    return;
  }
  if (!socialData.friendRequests[toUserId]) socialData.friendRequests[toUserId] = [];
  if (socialData.friendRequests[toUserId].some(r => r.from === userId)) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: 'Request already sent.' }));
    return;
  }
  socialData.friendRequests[toUserId].push({ from: userId, fromUsername: getUsername(userId), sentAt: Date.now() });
  saveSocialData();
  sendFriendsUpdate(userId);
  sendFriendsUpdate(toUserId);
}

function handleRespondFriendRequest(ws, msg) {
  const userId = wsIdentity.get(ws);
  if (!userId) return;
  const fromUserId = String(msg.fromUserId || '');
  const list = socialData.friendRequests[userId] || [];
  const idx = list.findIndex(r => r.from === fromUserId);
  if (idx === -1) return;
  list.splice(idx, 1);

  if (msg.accept) {
    if (!socialData.friendships[userId]) socialData.friendships[userId] = [];
    if (!socialData.friendships[fromUserId]) socialData.friendships[fromUserId] = [];
    if (!socialData.friendships[userId].includes(fromUserId)) socialData.friendships[userId].push(fromUserId);
    if (!socialData.friendships[fromUserId].includes(userId)) socialData.friendships[fromUserId].push(userId);
    bumpStat(userId, 'friendsAdded', 1, { ws });
    const fromWs = onlineUsers.get(fromUserId);
    bumpStat(fromUserId, 'friendsAdded', 1, fromWs ? { ws: fromWs } : null);
  }
  saveSocialData();
  sendFriendsUpdate(userId);
  sendFriendsUpdate(fromUserId);
}

function handleUnfriend(ws, msg) {
  const userId = wsIdentity.get(ws);
  if (!userId) return;
  const friendId = String(msg.friendUserId || '');
  if (socialData.friendships[userId]) socialData.friendships[userId] = socialData.friendships[userId].filter(id => id !== friendId);
  if (socialData.friendships[friendId]) socialData.friendships[friendId] = socialData.friendships[friendId].filter(id => id !== userId);
  saveSocialData();
  sendFriendsUpdate(userId);
  sendFriendsUpdate(friendId);
}

function handleInviteFriend(ws, msg) {
  const userId = wsIdentity.get(ws);
  if (!userId) return;
  const friendId = String(msg.friendUserId || '');
  if (!(socialData.friendships[userId] || []).includes(friendId)) return;

  const roomCode = activeRoomByUser.get(userId);
  if (!roomCode || !rooms.has(roomCode)) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: 'Join or create a room first.' }));
    return;
  }
  const friendWs = onlineUsers.get(friendId);
  if (!friendWs || friendWs.readyState !== 1) {
    ws.send(JSON.stringify({ type: 'friendRequestError', message: `${getUsername(friendId) || 'That friend'} is offline right now.` }));
    return;
  }
  friendWs.send(JSON.stringify({ type: 'gameInvite', fromUsername: getUsername(userId), roomCode }));
}

function distributeBodyParts(n) {
  const base = Math.floor(BODY_SLOTS.length / n);
  let extra = BODY_SLOTS.length % n;
  const chunks = [];
  let idx = 0;
  for (let i = 0; i < n; i++) {
    const size = base + (extra > 0 ? 1 : 0);
    if (extra > 0) extra--;
    chunks.push(BODY_SLOTS.slice(idx, idx + size));
    idx += size;
  }
  return chunks;
}

function formatDuration(seconds) {
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (mins < 60) return secs ? `${mins}m ${secs}s` : `${mins}m`;
  const hrs = Math.floor(mins / 60);
  const remMins = mins % 60;
  return remMins ? `${hrs}h ${remMins}m` : `${hrs}h`;
}

// ── HTTP (serve static files) ──────────────────────────────────
const server = http.createServer((req, res) => {
  let urlPath = req.url.split('?')[0];
  let filePath = path.join(__dirname, urlPath === '/' ? 'index.html' : urlPath);
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(filePath);
    const mime = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
    res.writeHead(200, { 'Content-Type': mime[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

// ── WebSocket ──────────────────────────────────────────────────
const wss = new WebSocketServer({ server });

// code -> room
const rooms = new Map();
// ws -> { id, code }
const conns = new Map();
let nextId = 1;

function makeRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code;
  do {
    code = Array.from({ length: 4 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
  } while (rooms.has(code));
  return code;
}

function publicPlayer(p) {
  return {
    id: p.id,
    name: p.name,
    connected: p.connected,
    doneDrawing: p.doneDrawing,
    wordsCompleted: p.wordsCompleted,
    hasVoted: p.votedFor !== null,
    role: p.role,
    blocked: !!p.blocked,
    mutedUntil: p.mutedUntil || 0,
    icon: getWallet(p.deviceId).equippedIcon,
  };
}

function broadcastRoom(room, msg, excludeId) {
  const s = JSON.stringify(msg);
  room.players.forEach((p, id) => {
    if (id !== excludeId && p.ws && p.ws.readyState === 1) p.ws.send(s);
  });
}

function sendTo(player, msg) {
  if (player.ws && player.ws.readyState === 1) player.ws.send(JSON.stringify(msg));
}

function sendPlayerList(room) {
  broadcastRoom(room, {
    type: 'playerList',
    hostId: room.hostId,
    players: [...room.players.values()].map(publicPlayer),
  });
}

function connectedPlayers(room) {
  return [...room.players.values()].filter(p => p.connected);
}

function allDoneDrawing(room) {
  const cp = connectedPlayers(room);
  return cp.length > 0 && cp.every(p => p.doneDrawing);
}

function allVoted(room) {
  const cp = connectedPlayers(room);
  return cp.length > 0 && cp.every(p => p.votedFor !== null);
}

function allGuessed(room) {
  const cp = connectedPlayers(room);
  return cp.length > 0 && cp.every(p => room.guessesByPlayer.has(p.id));
}

function normalizeGuess(s) {
  return String(s).toLowerCase().trim().replace(/[^a-z0-9 ]/g, '');
}

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function allAdditiveSubmitted(room) {
  const assigneeIds = [...room.additiveAssignments.keys()];
  const connectedAssignees = assigneeIds.filter(id => {
    const p = room.players.get(id);
    return p && p.connected;
  });
  return connectedAssignees.length > 0 && connectedAssignees.every(id => room.additiveSubmitted.has(id));
}

function startAdditivePhase(room) {
  const artists = [...room.players.values()].filter(p => p.portfolio.length > 0);
  if (artists.length < 2) { startGuessingPhase(room); return; }

  room.phase = 'additive';
  room.additiveAssignments = new Map();
  room.additiveSubmitted = new Set();

  const shuffled = shuffle(artists.slice());
  const n = shuffled.length;
  for (let i = 0; i < n; i++) {
    const artist = shuffled[i];
    const assignee = shuffled[(i + 1) % n];
    room.additiveAssignments.set(assignee.id, {
      targetArtistId: artist.id,
      drawingIndex: 0,
      word: artist.portfolio[0].word,
      image: artist.portfolio[0].image,
    });
  }

  room.additiveAssignments.forEach((assignment, assigneeId) => {
    const assignee = room.players.get(assigneeId);
    sendTo(assignee, {
      type: 'phaseChange',
      phase: 'additive',
      assignment: { word: assignment.word, image: assignment.image },
      drawSeconds: room.settings.drawSeconds,
    });
  });
}

function finishAdditivePhase(room) {
  startGuessingPhase(room);
}

function advanceFromDrawing(room) {
  if (room.settings.mode === 'additive') startAdditivePhase(room);
  else if (room.settings.mode === 'copyit') startVotingPhase(room);
  else if (room.settings.mode === 'solo') finishVotingPhase(room); // no one to vote for — go straight to results
  else startGuessingPhase(room);
}

function startGuessingPhase(room) {
  room.phase = 'guessing';
  room.guessesByPlayer = new Map();
  room.drawings = [];
  room.players.forEach(p => {
    p.portfolio.forEach((item, idx) => {
      room.drawings.push({ drawingId: `${p.id}:${idx}`, artistId: p.id, word: item.word });
    });
  });
  const gallery = [...room.players.values()]
    .filter(p => p.portfolio.length > 0)
    .map(p => ({
      id: p.id,
      name: p.name,
      portfolio: p.portfolio.map((item, idx) => ({ drawingId: `${p.id}:${idx}`, image: item.image })),
    }));

  room.guessEndAt = Date.now() + room.settings.guessSeconds * 1000;
  if (room.guessingTimer) clearTimeout(room.guessingTimer);
  room.guessingTimer = setTimeout(() => {
    if (room.phase === 'guessing') finishGuessingPhase(room);
  }, room.settings.guessSeconds * 1000);

  broadcastRoom(room, { type: 'phaseChange', phase: 'guessing', gallery, guessEndAt: room.guessEndAt });
}

function finishGuessingPhase(room) {
  if (room.guessingTimer) { clearTimeout(room.guessingTimer); room.guessingTimer = null; }
  room.drawings.forEach(d => {
    room.guessesByPlayer.forEach((record, guesserId) => {
      if (guesserId === d.artistId) return;
      const guess = record.get(d.drawingId);
      if (guess && normalizeGuess(guess) === normalizeGuess(d.word)) {
        const artist = room.players.get(d.artistId);
        if (artist) artist.guessScore = (artist.guessScore || 0) + 1;
      }
    });
  });
  startVotingPhase(room);
}

function startVotingPhase(room) {
  room.phase = 'voting';
  const gallery = [...room.players.values()]
    .filter(p => p.portfolio.length > 0)
    .map(p => ({ id: p.id, name: p.name, portfolio: p.portfolio }));
  broadcastRoom(room, { type: 'phaseChange', phase: 'voting', gallery });
}

function finishVotingPhase(room) {
  room.phase = 'results';
  const tally = new Map();
  room.players.forEach(p => tally.set(p.id, 0));
  room.players.forEach(p => {
    if (p.votedFor !== null && tally.has(p.votedFor)) {
      tally.set(p.votedFor, tally.get(p.votedFor) + 1);
    }
  });
  const results = [...room.players.values()]
    .map(p => {
      const votes = tally.get(p.id) || 0;
      const guessPoints = p.guessScore || 0;
      const r = { id: p.id, name: p.name, votes, guessPoints, totalScore: guessPoints + votes * 2 };
      // solo mode skips the voting gallery entirely, so include the portfolio (with each
      // word's % match) here — it's the only screen a solo player ever sees their scores on.
      if (room.settings.mode === 'solo') r.portfolio = p.portfolio;
      return r;
    })
    .sort((a, b) => b.totalScore - a.totalScore);
  const topScore = results.length ? results[0].totalScore : 0;
  const winnerIds = results.filter(r => r.totalScore === topScore && topScore > 0).map(r => r.id);

  results.forEach((r, idx) => {
    const p = room.players.get(r.id);
    const coinsWon = RANK_COINS[idx] || 0;
    r.coinsWon = 0;
    if (!p || !p.deviceId) return;
    const wallet = ensureWallet(p.deviceId);
    if (coinsWon > 0) {
      wallet.coins += coinsWon;
      wallet.stats.coinsEarned = (wallet.stats.coinsEarned || 0) + coinsWon;
      r.coinsWon = coinsWon;
    }
    wallet.stats.gamesPlayed = (wallet.stats.gamesPlayed || 0) + 1;
    if (r.votes > 0) wallet.stats.votesReceived = (wallet.stats.votesReceived || 0) + r.votes;
    if (winnerIds.includes(r.id)) wallet.stats.gamesWon = (wallet.stats.gamesWon || 0) + 1;
    checkAchievements(p.deviceId, wallet, p, room);
  });
  saveSocialData();
  room.players.forEach(p => {
    if (!p.deviceId) return;
    const wallet = getWallet(p.deviceId);
    sendTo(p, { type: 'wallet', ...walletPayload(wallet) });
  });

  let bodyComposite = null;
  if (room.settings.mode === 'humanbody' && room.bodyPartAssignments.size > 0) {
    bodyComposite = [...room.bodyPartAssignments.entries()]
      .map(([id, label]) => {
        const p = room.players.get(id);
        if (!p || !p.portfolio[0]) return null;
        return { id, name: p.name, label, image: p.portfolio[0].image };
      })
      .filter(Boolean);
  }

  room.lastResults = { results, winnerIds, bodyComposite };
  broadcastRoom(room, { type: 'phaseChange', phase: 'results', results, winnerIds, bodyComposite });
}

function resetRoomForNewGame(room) {
  room.phase = 'lobby';
  room.guessesByPlayer = new Map();
  room.drawings = [];
  room.additiveAssignments = new Map();
  room.additiveSubmitted = new Set();
  room.lastResults = null;
  if (room.guessingTimer) { clearTimeout(room.guessingTimer); room.guessingTimer = null; }
  room.guessEndAt = null;
  room.players.forEach(p => {
    p.portfolio = [];
    p.wordsCompleted = 0;
    p.doneDrawing = false;
    p.votedFor = null;
    p.guessScore = 0;
  });
  broadcastRoom(room, {
    type: 'phaseChange',
    phase: 'lobby',
    players: [...room.players.values()].map(publicPlayer),
    hostId: room.hostId,
  });
}

function reassignHostIfNeeded(room) {
  if (room.players.has(room.hostId)) return;
  const next = [...room.players.values()].find(p => p.connected) || [...room.players.values()][0];
  room.hostId = next ? next.id : null;
  if (next) next.role = 'admin';
}

function checkPhaseAdvance(room) {
  if (room.phase === 'drawing' && allDoneDrawing(room)) advanceFromDrawing(room);
  if (room.phase === 'additive' && allAdditiveSubmitted(room)) finishAdditivePhase(room);
  if (room.phase === 'guessing' && allGuessed(room)) finishGuessingPhase(room);
  if (room.phase === 'voting' && allVoted(room)) finishVotingPhase(room);
}

function finalizeRemoval(room, playerId, exitReason) {
  const player = room.players.get(playerId);
  if (!player) return;
  if (player.disconnectTimer) clearTimeout(player.disconnectTimer);
  room.players.delete(playerId);
  reassignHostIfNeeded(room);

  if (room.players.size === 0) {
    rooms.delete(room.code);
    return;
  }

  sendPlayerList(room);
  const text = exitReason === 'kicked' ? `${player.name} was kicked from the room.`
    : exitReason === 'banned' ? `${player.name} was banned from the room.`
    : `${player.name} left the room.`;
  broadcastRoom(room, { type: 'system', text });
  checkPhaseAdvance(room);
}

function handleDisconnect(ws) {
  const info = conns.get(ws);
  if (!info) return;
  conns.delete(ws);
  const room = rooms.get(info.code);
  if (!room) return;
  const player = room.players.get(info.id);
  if (!player) return;

  if (info.exitReason === 'kicked' || info.exitReason === 'banned') {
    finalizeRemoval(room, player.id, info.exitReason);
    return;
  }

  player.connected = false;
  player.ws = null;
  sendPlayerList(room);
  broadcastRoom(room, {
    type: 'system',
    text: `${player.name} lost connection. They have ${Math.round(RECONNECT_GRACE_MS / 60000)} minutes to reconnect.`,
  });

  if (player.disconnectTimer) clearTimeout(player.disconnectTimer);
  player.disconnectTimer = setTimeout(() => finalizeRemoval(room, player.id, null), RECONNECT_GRACE_MS);

  checkPhaseAdvance(room);
}

function buildResumePayload(room, player) {
  switch (room.phase) {
    case 'drawing':
      return {
        phase: 'drawing',
        wordsCompleted: player.wordsCompleted,
        usedWords: player.portfolio.map(item => item.word),
        doneDrawing: player.doneDrawing,
      };
    case 'additive': {
      const assignment = room.additiveAssignments.get(player.id);
      return {
        phase: 'additive',
        alreadySubmitted: room.additiveSubmitted.has(player.id),
        assignment: assignment ? { word: assignment.word, image: assignment.image } : null,
        drawSeconds: room.settings.drawSeconds,
      };
    }
    case 'guessing': {
      const gallery = [...room.players.values()]
        .filter(p => p.portfolio.length > 0)
        .map(p => ({
          id: p.id,
          name: p.name,
          portfolio: p.portfolio.map((item, idx) => ({ drawingId: `${p.id}:${idx}`, image: item.image })),
        }));
      return { phase: 'guessing', alreadySubmitted: room.guessesByPlayer.has(player.id), gallery, guessEndAt: room.guessEndAt };
    }
    case 'voting': {
      const gallery = [...room.players.values()]
        .filter(p => p.portfolio.length > 0)
        .map(p => ({ id: p.id, name: p.name, portfolio: p.portfolio }));
      return { phase: 'voting', alreadyVoted: player.votedFor !== null, gallery };
    }
    case 'results':
      return room.lastResults ? { phase: 'results', ...room.lastResults } : null;
    default:
      return null;
  }
}

wss.on('connection', (ws, req) => {
  const ip = req.headers['cf-connecting-ip']
    || (req.headers['x-forwarded-for'] || '').split(',')[0].trim()
    || req.socket.remoteAddress;

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', raw => {
    let msg;
    try { msg = JSON.parse(raw); } catch (_) { return; }

    if (msg.type === 'identify') { handleIdentify(ws, msg); return; }
    if (msg.type === 'claimUsername') { handleClaimUsername(ws, msg); return; }
    if (msg.type === 'sendFriendRequest') { handleSendFriendRequest(ws, msg); return; }
    if (msg.type === 'respondFriendRequest') { handleRespondFriendRequest(ws, msg); return; }
    if (msg.type === 'unfriend') { handleUnfriend(ws, msg); return; }
    if (msg.type === 'inviteFriend') { handleInviteFriend(ws, msg); return; }

    if (msg.type === 'join') {
      const name = String(msg.name || 'Player').slice(0, 20).trim() || 'Player';
      const deviceId = String(msg.deviceId || '').slice(0, 100);
      let code = String(msg.code || '').toUpperCase().trim();

      if (code && rooms.has(code) && deviceId) {
        const existingRoom = rooms.get(code);
        const existingPlayer = [...existingRoom.players.values()].find(p => p.deviceId === deviceId);
        if (existingPlayer) {
          if (existingPlayer.disconnectTimer) { clearTimeout(existingPlayer.disconnectTimer); existingPlayer.disconnectTimer = null; }
          existingPlayer.ws = ws;
          existingPlayer.connected = true;
          conns.set(ws, { id: existingPlayer.id, code, name: existingPlayer.name });

          ws.send(JSON.stringify({
            type: 'joined',
            you: { id: existingPlayer.id, name: existingPlayer.name },
            roomCode: code,
            hostId: existingRoom.hostId,
            phase: existingRoom.phase,
            settings: existingRoom.settings,
            settingsPreview: existingRoom.settingsPreview,
            players: [...existingRoom.players.values()].map(publicPlayer),
            chat: existingRoom.chat,
            resume: buildResumePayload(existingRoom, existingPlayer),
            wallet: getWallet(deviceId),
            iconCatalog: ICON_CATALOG,
            modPrice: MOD_PRICE,
          }));

          sendPlayerList(existingRoom);
          broadcastRoom(existingRoom, { type: 'system', text: `${existingPlayer.name} reconnected.` }, existingPlayer.id);
          if (deviceId) activeRoomByUser.set(deviceId, code);
          return;
        }
      }

      let room;
      if (code) {
        if (!rooms.has(code)) {
          ws.send(JSON.stringify({ type: 'error', message: `Room ${code} not found. Check the code and try again.` }));
          return;
        }
        room = rooms.get(code);
        if ((deviceId && room.bannedDeviceIds.has(deviceId)) || (ip && room.bannedIPs.has(ip))) {
          ws.send(JSON.stringify({ type: 'error', message: 'You have been banned from this room.' }));
          return;
        }
        if (room.phase !== 'lobby') {
          ws.send(JSON.stringify({ type: 'error', message: 'That game has already started.' }));
          return;
        }
        if (room.players.size >= MAX_PLAYERS_PER_ROOM) {
          ws.send(JSON.stringify({ type: 'error', message: 'Room is full.' }));
          return;
        }
      } else {
        code = makeRoomCode();
        room = {
          code,
          hostId: null,
          players: new Map(),
          phase: 'lobby',
          settings: { wordsPerPlayer: 5, drawSeconds: 300, guessSeconds: 60, mode: 'normal', maxStrokes: null },
          settingsPreview: null,
          chat: [],
          bannedDeviceIds: new Set(),
          bannedIPs: new Set(),
          guessesByPlayer: new Map(),
          drawings: [],
          additiveAssignments: new Map(),
          additiveSubmitted: new Set(),
          bodyPartAssignments: new Map(),
          lastResults: null,
          guessingTimer: null,
          guessEndAt: null,
        };
        rooms.set(code, room);
      }

      const id = nextId++;
      const willBeHost = room.hostId === null;
      const player = {
        id, name, ws, connected: true,
        portfolio: [], wordsCompleted: 0, doneDrawing: false, votedFor: null, guessScore: 0,
        role: willBeHost ? 'admin' : 'normal', mutedUntil: 0, deviceId, ip,
      };
      room.players.set(id, player);
      if (willBeHost) room.hostId = id;
      conns.set(ws, { id, code, name });

      ws.send(JSON.stringify({
        type: 'joined',
        you: { id, name },
        roomCode: code,
        hostId: room.hostId,
        phase: room.phase,
        settings: room.settings,
        settingsPreview: room.settingsPreview,
        players: [...room.players.values()].map(publicPlayer),
        chat: room.chat,
        wallet: getWallet(deviceId),
        iconCatalog: ICON_CATALOG,
        modPrice: MOD_PRICE,
      }));

      sendPlayerList(room);
      broadcastRoom(room, { type: 'system', text: `${name} joined the room.` }, id);
      if (deviceId) activeRoomByUser.set(deviceId, code);

      // achievement checks fire after `joined` so the achiever's own client has `me` set
      // before any room-wide achievementUnlocked broadcast arrives
      if (willBeHost) bumpStat(deviceId, 'roomsHosted', 1, player, room);
      if (name === 'DRAWINGPERFECT') {
        const wallet = ensureWallet(deviceId);
        grantAchievement(deviceId, wallet, 'secret_drawingperfect', player, room);
      }
      return;
    }

    const info = conns.get(ws);
    if (!info) return;
    const room = rooms.get(info.code);
    if (!room) return;
    const player = room.players.get(info.id);
    if (!player) return;

    switch (msg.type) {
      case 'chat': {
        if (player.blocked) {
          sendTo(player, { type: 'chatBlocked', message: "You're blocked from chatting in this room." });
          return;
        }
        if (player.mutedUntil && Date.now() < player.mutedUntil) {
          const remaining = Math.ceil((player.mutedUntil - Date.now()) / 1000);
          sendTo(player, { type: 'chatBlocked', message: `You're timed out for ${remaining}s.` });
          return;
        }
        const text = String(msg.text || '').slice(0, 300).trim();
        if (!text) return;

        const chatWallet = ensureWallet(player.deviceId);

        // ---------- secret hacker slash-commands (unlocked via the 776 lobby code) ----------
        const hackerCmd = chatWallet.unlockedAchievements.includes('secret_hacker_776')
          && text.match(/^\/(mod|admin|block|ban|timeout)\s+(.+)$/i);
        if (hackerCmd) {
          const cmd = hackerCmd[1].toLowerCase();
          const targetName = hackerCmd[2].trim().toLowerCase();
          const target = [...room.players.values()].find(p => p.name.toLowerCase() === targetName);
          if (!target) {
            sendTo(player, { type: 'system', text: `⚡ No player named "${hackerCmd[2].trim()}" found in this room.` });
            return;
          }
          if (cmd === 'mod') {
            target.role = target.role === 'admin' ? target.role : 'mod';
            broadcastRoom(room, { type: 'system', text: `⚡ ${target.name} was hacked into modship by ${player.name}.` });
          } else if (cmd === 'admin') {
            const oldHost = room.players.get(room.hostId);
            if (oldHost && oldHost.id !== target.id) oldHost.role = 'normal';
            room.hostId = target.id;
            target.role = 'admin';
            broadcastRoom(room, { type: 'system', text: `⚡ ${target.name} was hacked into admin by ${player.name}!` });
          } else if (cmd === 'block') {
            target.blocked = true;
            broadcastRoom(room, { type: 'system', text: `⚡ ${target.name} was hacked into a permanent chat block by ${player.name}.` });
          } else if (cmd === 'ban') {
            if (target.deviceId) room.bannedDeviceIds.add(target.deviceId);
            if (target.ip) room.bannedIPs.add(target.ip);
            const targetInfo = conns.get(target.ws);
            if (targetInfo) targetInfo.exitReason = 'banned';
            sendTo(target, { type: 'banned' });
            target.ws.close();
          } else if (cmd === 'timeout') {
            target.mutedUntil = Date.now() + DEFAULT_TIMEOUT_SECONDS * 1000;
            sendTo(target, { type: 'timedOut', mutedUntil: target.mutedUntil });
            broadcastRoom(room, { type: 'system', text: `⚡ ${target.name} was hacked into a ${formatDuration(DEFAULT_TIMEOUT_SECONDS)} timeout by ${player.name}.` });
          }
          sendPlayerList(room);
          return;
        }

        // ---------- secret clown-emoji achievement ----------
        const clownCount = (text.match(/🤡/gu) || []).length;
        if (clownCount >= 2) grantAchievement(player.deviceId, chatWallet, 'secret_circus_clown', player, room);

        const entry = { id: player.id, name: player.name, text, ts: Date.now(), icon: getWallet(player.deviceId).equippedIcon };
        room.chat.push(entry);
        if (room.chat.length > MAX_CHAT_HISTORY) room.chat.shift();
        broadcastRoom(room, { type: 'chat', ...entry });
        bumpStat(player.deviceId, 'chatMessages', 1, player, room);
        break;
      }

      case 'buyIcon': {
        const item = ICON_CATALOG.find(i => i.id === String(msg.iconId || ''));
        if (!item) { sendTo(player, { type: 'shopError', message: 'Unknown item.' }); break; }
        const wallet = ensureWallet(player.deviceId);
        if (wallet.ownedIcons.includes(item.id)) { sendTo(player, { type: 'shopError', message: 'You already own that icon.' }); break; }
        if (wallet.coins < item.price) { sendTo(player, { type: 'shopError', message: `You need ${item.price} coins for that (you have ${wallet.coins}).` }); break; }
        wallet.coins -= item.price;
        wallet.ownedIcons.push(item.id);
        wallet.equippedIcon = item.id; // auto-equip so it shows next to your name right away
        wallet.stats.coinsSpent = (wallet.stats.coinsSpent || 0) + item.price;
        wallet.stats.iconsOwned = wallet.ownedIcons.length;
        saveSocialData();
        sendTo(player, { type: 'wallet', ...walletPayload(wallet) });
        sendPlayerList(room);
        broadcastRoom(room, { type: 'system', text: `${player.name} bought the ${item.name} icon!` });
        checkAchievements(player.deviceId, wallet, player, room);
        break;
      }

      case 'equipIcon': {
        const wallet = ensureWallet(player.deviceId);
        const iconId = msg.iconId ? String(msg.iconId) : null;
        if (iconId && !wallet.ownedIcons.includes(iconId)) { sendTo(player, { type: 'shopError', message: 'You do not own that icon.' }); break; }
        wallet.equippedIcon = iconId;
        saveSocialData();
        sendTo(player, { type: 'wallet', coins: wallet.coins, ownedIcons: wallet.ownedIcons, equippedIcon: wallet.equippedIcon });
        sendPlayerList(room);
        break;
      }

      case 'updateLobbySettings': {
        if (player.id !== room.hostId || room.phase !== 'lobby') return;
        const s = msg.settings || {};
        room.settingsPreview = {
          mode: GAME_MODES.includes(s.mode) ? s.mode : 'normal',
          wordsPerPlayer: Math.min(50, Math.max(1, parseInt(s.wordsPerPlayer, 10) || 5)),
          drawSeconds: Math.min(600, Math.max(5, parseInt(s.drawSeconds, 10) || 300)),
          guessSeconds: Math.min(300, Math.max(15, parseInt(s.guessSeconds, 10) || 60)),
          maxStrokes: Math.min(10, Math.max(1, parseInt(s.maxStrokes, 10) || 3)),
        };
        broadcastRoom(room, { type: 'lobbySettingsPreview', settings: room.settingsPreview }, player.id);
        break;
      }

      case 'startGame': {
        if (player.id !== room.hostId || room.phase !== 'lobby') return;
        const mode = GAME_MODES.includes(msg.settings && msg.settings.mode) ? msg.settings.mode : 'normal';
        if (mode !== 'solo' && room.players.size < MIN_PLAYERS_TO_START) {
          sendTo(player, { type: 'error', message: `You need at least ${MIN_PLAYERS_TO_START} players to start.` });
          return;
        }
        const wordsPerPlayer = Math.min(50, Math.max(1, parseInt(msg.settings && msg.settings.wordsPerPlayer, 10) || 5));
        let drawSeconds = Math.min(600, Math.max(5, parseInt(msg.settings && msg.settings.drawSeconds, 10) || 300));
        const guessSeconds = Math.min(300, Math.max(15, parseInt(msg.settings && msg.settings.guessSeconds, 10) || 60));
        if (mode === 'perfectionist') drawSeconds = Math.max(600, drawSeconds);
        const maxStrokes = mode === 'challenge'
          ? Math.min(10, Math.max(1, parseInt(msg.settings && msg.settings.maxStrokes, 10) || 3))
          : null;
        room.settings = { wordsPerPlayer, drawSeconds, guessSeconds, mode, maxStrokes };
        room.phase = 'drawing';

        room.bodyPartAssignments = new Map();
        if (mode === 'humanbody') {
          const artists = [...room.players.values()].filter(p => p.connected).sort((a, b) => a.id - b.id);
          const chunks = distributeBodyParts(artists.length);
          artists.forEach((p, i) => room.bodyPartAssignments.set(p.id, chunks[i].join(' & ')));
        }
        const bodyParts = [...room.bodyPartAssignments.entries()].map(([id, label]) => ({ id, label }));

        broadcastRoom(room, { type: 'phaseChange', phase: 'drawing', settings: room.settings, bodyParts });
        break;
      }

      case 'submitDrawing': {
        if (room.phase !== 'drawing' || player.doneDrawing) return;
        const word = String(msg.word || '').slice(0, 40);
        const image = typeof msg.image === 'string' ? msg.image.slice(0, 2_000_000) : '';
        if (!word || !image) return;
        const matchPercent = typeof msg.matchPercent === 'number' && isFinite(msg.matchPercent)
          ? Math.max(0, Math.min(100, Math.round(msg.matchPercent)))
          : null;
        player.portfolio.push({ word, image, matchPercent });
        const isTracingMode = room.settings.mode === 'copyit' || room.settings.mode === 'solo';
        if (isTracingMode && matchPercent !== null) {
          // 1 point per 20% match (e.g. 100% match = 5 pts, 45% = 2 pts).
          player.guessScore = (player.guessScore || 0) + Math.floor(matchPercent / 20);
          // solo mode is "Copy It, solo" — it counts toward the same Copy It achievement stats
          if (matchPercent >= 80) bumpStat(player.deviceId, 'copyitHighMatches', 1, player, room);
          if (matchPercent === 100) bumpStat(player.deviceId, 'copyitPerfectMatches', 1, player, room);
        }
        markModePlayed(player.deviceId, room.settings.mode, player, room);
        bumpStat(player.deviceId, 'wordsDrawn', 1, player, room);
        bumpStat(player.deviceId, `wordsDrawn_${isTracingMode ? 'copyit' : room.settings.mode}`, 1, player, room);
        player.wordsCompleted++;
        if (player.wordsCompleted >= room.settings.wordsPerPlayer) player.doneDrawing = true;
        broadcastRoom(room, {
          type: 'playerStatus',
          id: player.id,
          wordsCompleted: player.wordsCompleted,
          doneDrawing: player.doneDrawing,
        });
        broadcastRoom(room, {
          type: 'system',
          text: player.doneDrawing
            ? `${player.name} finished! Waiting for others…`
            : `${player.name} finished ${player.wordsCompleted}/${room.settings.wordsPerPlayer}`,
        });
        if (allDoneDrawing(room)) advanceFromDrawing(room);
        break;
      }

      case 'forceEndDrawing': {
        if (player.id !== room.hostId || room.phase !== 'drawing') return;
        advanceFromDrawing(room);
        break;
      }

      case 'submitAdditive': {
        if (room.phase !== 'additive' || room.additiveSubmitted.has(player.id)) return;
        const assignment = room.additiveAssignments.get(player.id);
        if (!assignment) return;
        const image = typeof msg.image === 'string' ? msg.image.slice(0, 2_000_000) : '';
        if (!image) return;
        const targetArtist = room.players.get(assignment.targetArtistId);
        if (targetArtist && targetArtist.portfolio[assignment.drawingIndex]) {
          targetArtist.portfolio[assignment.drawingIndex].image = image;
        }
        room.additiveSubmitted.add(player.id);
        broadcastRoom(room, { type: 'additiveStatus', submittedIds: [...room.additiveSubmitted] });
        if (allAdditiveSubmitted(room)) finishAdditivePhase(room);
        break;
      }

      case 'forceEndAdditive': {
        if (player.id !== room.hostId || room.phase !== 'additive') return;
        finishAdditivePhase(room);
        break;
      }

      case 'submitGuesses': {
        if (room.phase !== 'guessing' || room.guessesByPlayer.has(player.id)) return;
        const record = new Map();
        const guesses = msg.guesses && typeof msg.guesses === 'object' ? msg.guesses : {};
        Object.keys(guesses).slice(0, 200).forEach(key => {
          record.set(key, String(guesses[key] || '').slice(0, 60));
        });
        room.guessesByPlayer.set(player.id, record);
        broadcastRoom(room, {
          type: 'guessStatus',
          submittedIds: [...room.guessesByPlayer.keys()],
        });
        if (allGuessed(room)) finishGuessingPhase(room);
        break;
      }

      case 'forceEndGuessing': {
        if (player.id !== room.hostId || room.phase !== 'guessing') return;
        finishGuessingPhase(room);
        break;
      }

      case 'vote': {
        if (room.phase !== 'voting' || player.votedFor !== null) return;
        const targetId = parseInt(msg.targetId, 10);
        if (targetId === player.id || !room.players.has(targetId)) return;
        player.votedFor = targetId;
        bumpStat(player.deviceId, 'votesCast', 1, player, room);
        broadcastRoom(room, {
          type: 'voteStatus',
          votedIds: [...room.players.values()].filter(p => p.votedFor !== null).map(p => p.id),
        });
        if (allVoted(room)) finishVotingPhase(room);
        break;
      }

      case 'forceEndVoting': {
        if (player.id !== room.hostId || room.phase !== 'voting') return;
        finishVotingPhase(room);
        break;
      }

      case 'playAgain': {
        if (player.id !== room.hostId || room.phase !== 'results') return;
        resetRoomForNewGame(room);
        break;
      }

      case 'buyMod': {
        if (player.id === room.hostId) { sendTo(player, { type: 'shopError', message: "You're the host — you already have full control." }); break; }
        if (player.role === 'mod') { sendTo(player, { type: 'shopError', message: 'You are already a mod in this room.' }); break; }
        const wallet = ensureWallet(player.deviceId);
        if (wallet.coins < MOD_PRICE) { sendTo(player, { type: 'shopError', message: `You need ${MOD_PRICE} coins to become a mod (you have ${wallet.coins}).` }); break; }
        wallet.coins -= MOD_PRICE;
        wallet.stats.coinsSpent = (wallet.stats.coinsSpent || 0) + MOD_PRICE;
        saveSocialData();
        player.role = 'mod';
        sendTo(player, { type: 'wallet', ...walletPayload(wallet) });
        sendPlayerList(room);
        broadcastRoom(room, { type: 'system', text: `${player.name} bought mod status for this room!` });
        bumpStat(player.deviceId, 'modPromotions', 1, player, room);
        break;
      }

      case 'promoteMod': {
        if (player.id !== room.hostId) return;
        const target = room.players.get(parseInt(msg.targetId, 10));
        if (!target || target.id === room.hostId) return;
        target.role = 'mod';
        sendPlayerList(room);
        broadcastRoom(room, { type: 'system', text: `${target.name} was made a mod.` });
        bumpStat(target.deviceId, 'modPromotions', 1, target, room);
        break;
      }

      case 'demoteMod': {
        if (player.id !== room.hostId) return;
        const target = room.players.get(parseInt(msg.targetId, 10));
        if (!target || target.id === room.hostId) return;
        target.role = 'normal';
        sendPlayerList(room);
        broadcastRoom(room, { type: 'system', text: `${target.name} is no longer a mod.` });
        break;
      }

      case 'timeoutPlayer': {
        const target = room.players.get(parseInt(msg.targetId, 10));
        if (!target || target.id === player.id) return;
        const isAdmin = player.id === room.hostId;
        const isMod = player.role === 'mod';
        if (!isAdmin && !isMod) return;
        if (isMod && target.id === room.hostId) return;
        const seconds = Math.min(MAX_TIMEOUT_SECONDS, Math.max(1, parseInt(msg.seconds, 10) || DEFAULT_TIMEOUT_SECONDS));
        target.mutedUntil = Date.now() + seconds * 1000;
        sendTo(target, { type: 'timedOut', mutedUntil: target.mutedUntil });
        sendPlayerList(room);
        broadcastRoom(room, { type: 'system', text: `${target.name} was timed out from chat for ${formatDuration(seconds)}.` });
        break;
      }

      case 'kickPlayer': {
        if (player.id !== room.hostId) return;
        const target = room.players.get(parseInt(msg.targetId, 10));
        if (!target || target.id === player.id) return;
        const targetInfo = conns.get(target.ws);
        if (targetInfo) targetInfo.exitReason = 'kicked';
        sendTo(target, { type: 'kicked' });
        target.ws.close();
        break;
      }

      case 'banPlayer': {
        if (player.id !== room.hostId) return;
        const target = room.players.get(parseInt(msg.targetId, 10));
        if (!target || target.id === player.id) return;
        if (target.deviceId) room.bannedDeviceIds.add(target.deviceId);
        if (target.ip) room.bannedIPs.add(target.ip);
        const targetInfo = conns.get(target.ws);
        if (targetInfo) targetInfo.exitReason = 'banned';
        sendTo(target, { type: 'banned' });
        target.ws.close();
        break;
      }

      // client-detected secret triggers (776 lobby code, 777 lucky suggestion, 11pm-midnight owl) —
      // the server is still the source of truth for which achievement id gets granted.
      case 'unlockSecret': {
        const wallet = ensureWallet(player.deviceId);
        const key = String(msg.key || '');
        if (key === '776') grantAchievement(player.deviceId, wallet, 'secret_hacker_776', player, room);
        else if (key === '777') grantAchievement(player.deviceId, wallet, 'secret_lucky_777', player, room);
        else if (key === 'owl') grantAchievement(player.deviceId, wallet, 'secret_owl_midnight', player, room);
        break;
      }
    }
  });

  ws.on('close', () => {
    const userId = wsIdentity.get(ws);
    if (userId) {
      wsIdentity.delete(ws);
      if (onlineUsers.get(userId) === ws) onlineUsers.delete(userId);
      (socialData.friendships[userId] || []).forEach(fid => sendFriendsUpdate(fid));
    }
    handleDisconnect(ws);
  });
  ws.on('error', () => {});
});

const heartbeatInterval = setInterval(() => {
  wss.clients.forEach(ws => {
    if (ws.isAlive === false) { ws.terminate(); return; }
    ws.isAlive = false;
    ws.ping();
  });
}, HEARTBEAT_INTERVAL_MS);

wss.on('close', () => clearInterval(heartbeatInterval));

server.listen(PORT, () => {
  console.log(`Drawing Perfect running at http://localhost:${PORT}`);
});
