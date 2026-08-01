(() => {
  const SWATCH_COLORS = ['#111111', '#e63946', '#f4a300', '#2a9d8f', '#3a86ff', '#7b2cbf', '#ffffff'];
  const NAME_COLORS = ['#e63946', '#f4a300', '#2a9d8f', '#3a86ff', '#7b2cbf', '#ff6b9d', '#06923e', '#c44536', '#5e548e', '#fb8500', '#118ab2', '#8338ec'];

  function colorForPlayer(id) {
    return NAME_COLORS[id % NAME_COLORS.length];
  }

  function getDeviceId() {
    try {
      let id = localStorage.getItem('dp_device_id');
      if (!id) {
        id = crypto.randomUUID ? crypto.randomUUID() : ('dev-' + Math.random().toString(36).slice(2) + Date.now());
        localStorage.setItem('dp_device_id', id);
      }
      return id;
    } catch (_) {
      return 'dev-' + Math.random().toString(36).slice(2);
    }
  }
  const deviceId = getDeviceId();

  // ---------- state ----------
  let ws = null;
  let me = null;               // { id, name }
  let roomCode = '';
  let hostId = null;
  let phase = 'lobby';
  let settings = { wordsPerPlayer: 5, drawSeconds: 300 };
  let players = new Map();     // id -> { id, name, connected, doneDrawing, wordsCompleted, hasVoted }

  let usedWords = new Set();
  let wordsCompleted = 0;
  let currentWord = null;
  let wordEndAt = 0;
  let timerHandle = null;
  let guessEndAt = 0;
  let guessTimerHandle = null;

  let gallery = [];
  let votedFor = null;
  let connectedVotedCount = { voted: 0, total: 0 };

  let guessGallery = [];
  let guessInputs = new Map(); // drawingId -> input element
  let guessSubmittedByMe = false;
  let guessProgress = { submitted: 0, total: 0 };

  let brushColor = SWATCH_COLORS[0];
  let brushSize = 5;
  let eraserOn = false;
  let bucketOn = false;
  let drawingActive = false;
  let strokeDrew = false;
  let lastPoint = null;
  let ctx = null;

  let undoStack = [];
  let redoStack = [];
  const MAX_HISTORY = 30;
  let strokesUsed = 0;
  let referenceShown = false;
  let referenceRequestToken = 0;
  const referenceCache = new Map();
  let inAdditiveTask = false;
  let myBodyPartLabel = '';

  let wallet = { coins: 0, ownedIcons: [], equippedIcon: null };
  let iconCatalog = [];

  // ---------- dom ----------
  const $ = id => document.getElementById(id);
  const screenJoin = $('screen-join');
  const screenRoom = $('screen-room');

  const inputName = $('input-name');
  const inputCode = $('input-code');
  const btnJoin = $('btn-join');
  const joinError = $('join-error');

  const lobbyCode = $('lobby-code');
  const btnCopyCode = $('btn-copy-code');
  const btnPlayersHere = $('btn-players-here');
  const playersHereCountEl = $('players-here-count');
  const playersHerePopoverEl = $('players-here-popover');
  const btnOpenShop = $('btn-open-shop');
  const shopModal = $('shop-modal');
  const btnCloseShop = $('btn-close-shop');
  const shopCoinBalanceEl = $('shop-coin-balance');
  const coinBalanceEl = $('coin-balance');
  const shopErrorEl = $('shop-error');
  const shopGridEl = $('shop-grid');
  const roster = $('roster');
  const hostSettings = $('host-settings');
  const settingMode = $('setting-mode');
  const modeDescription = $('mode-description');
  const challengeSettings = $('challenge-settings');
  const settingMaxStrokes = $('setting-max-strokes');
  const settingWords = $('setting-words');
  const settingSeconds = $('setting-seconds');
  const settingGuessSeconds = $('setting-guess-seconds');
  const btnStart = $('btn-start');
  const nonHostMsg = $('non-host-msg');
  const suggestHint = $('suggest-hint');

  const progressCount = $('progress-count');
  const progressTotal = $('progress-total');
  const bodyPartBanner = $('body-part-banner');
  const cardSearch = $('card-search');
  const cardGrid = $('card-grid');
  const customWordSection = $('custom-word-section');
  const inputCustomWord = $('input-custom-word');
  const btnSubmitCustomWord = $('btn-submit-custom-word');
  const customWordError = $('custom-word-error');

  const currentWordEl = $('current-word');
  const wordTimerEl = $('word-timer');
  const strokesLeftEl = $('strokes-left');
  const fogOverlay = $('fog-overlay');
  const btnPeek = $('btn-peek');
  const btnReference = $('btn-reference');
  const referenceOverlay = $('reference-overlay');
  const referenceImg = $('reference-img');
  const referenceLoading = $('reference-loading');
  const referenceMissing = $('reference-missing');
  const swatchesEl = $('swatches');
  const colorPicker = $('color-picker');
  const brushSizeInput = $('brush-size');
  const brushSizeLabel = $('brush-size-label');
  const sizePresets = $('size-presets');
  const btnUndo = $('btn-undo');
  const btnRedo = $('btn-redo');
  const btnBucket = $('btn-bucket');
  const btnEraser = $('btn-eraser');
  const btnClear = $('btn-clear');
  const btnSubmit = $('btn-submit');
  const paper = $('paper');

  const btnForceEnd = $('btn-force-end');
  const waitingHeading = $('waiting-heading');
  const waitingHint = $('waiting-hint');

  const guessingGalleryEl = $('guessing-gallery');
  const guessTimerEl = $('guess-timer');
  const btnSubmitGuesses = $('btn-submit-guesses');
  const btnForceEndGuessing = $('btn-force-end-guessing');

  const galleryEl = $('gallery');
  const btnForceEndVoting = $('btn-force-end-voting');

  const winnerBanner = $('winner-banner');
  const resultsList = $('results-list');
  const bodyComposite = $('body-composite');
  const bodyCompositeParts = $('body-composite-parts');
  const btnPlayAgain = $('btn-play-again');
  const resultsNonHostMsg = $('results-non-host-msg');

  const chatLog = $('chat-log');
  const chatForm = $('chat-form');
  const chatInput = $('chat-input');
  const btnEmoji = $('btn-emoji');
  const emojiPanel = $('emoji-panel');
  const btnToggleTts = $('btn-toggle-tts');

  const views = ['view-lobby', 'view-card-picker', 'view-canvas', 'view-waiting', 'view-guessing', 'view-voting', 'view-results']
    .map(id => $(id));

  function showView(id) {
    views.forEach(v => v.classList.toggle('hidden', v.id !== id));
  }

  // ---------- connection ----------
  function connect(name, code) {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(`${proto}//${location.host}`);

    const connectTimeout = setTimeout(() => {
      if (ws.readyState !== WebSocket.OPEN) {
        ws.close();
        if (screenRoom.classList.contains('active')) {
          showReconnectBanner();
        } else {
          failToJoin("Couldn't reach the server. Check your connection and try again.");
        }
      }
    }, 8000);

    ws.addEventListener('open', () => {
      clearTimeout(connectTimeout);
      ws.send(JSON.stringify({ type: 'join', name, code, deviceId }));
    });
    ws.addEventListener('message', e => handleMessage(JSON.parse(e.data)));
    ws.addEventListener('error', () => clearTimeout(connectTimeout));
    ws.addEventListener('close', () => {
      clearTimeout(connectTimeout);
      if (screenRoom.classList.contains('active')) {
        appendSystemMessage('Disconnected from server.');
        showReconnectBanner();
      } else if (!me) {
        failToJoin('Lost connection before joining. Please try again.');
      }
    });
  }

  function failToJoin(message) {
    joinError.textContent = message;
    btnJoin.disabled = false;
  }

  btnJoin.addEventListener('click', () => {
    GameAudio.ensureCtx();
    GameAudio.sfxClick();
    const name = inputName.value.trim();
    if (!name) { joinError.textContent = 'Please enter your name.'; return; }
    joinError.textContent = '';
    btnJoin.disabled = true;
    connect(name, inputCode.value);
  });

  // ---------- reconnection ----------
  const reconnectBanner = $('reconnect-banner');
  const btnReconnect = $('btn-reconnect');

  function showReconnectBanner() {
    reconnectBanner.classList.remove('hidden');
    btnReconnect.disabled = false;
    btnReconnect.textContent = 'Reconnect';
  }
  function hideReconnectBanner() {
    reconnectBanner.classList.add('hidden');
  }

  btnReconnect.addEventListener('click', () => {
    if (!me || !roomCode) return;
    btnReconnect.disabled = true;
    btnReconnect.textContent = 'Reconnecting…';
    connect(me.name, roomCode);
  });

  // ---------- audio ----------
  const btnToggleMusic = $('btn-toggle-music');
  document.addEventListener('pointerdown', function unlockAudioOnce() {
    GameAudio.ensureCtx();
    GameAudio.startMenuMusic();
    document.removeEventListener('pointerdown', unlockAudioOnce);
  }, { once: true });

  btnToggleMusic.addEventListener('click', () => {
    const next = !GameAudio.isEnabled();
    GameAudio.setEnabled(next);
    btnToggleMusic.textContent = next ? '🔊 Music: On' : '🔇 Music: Off';
    if (next) GameAudio.startMenuMusic();
  });

  // ---------- settings modal (sfx/music volume, contrast) ----------
  const settingsModal = $('settings-modal');
  const btnCloseSettings = $('btn-close-settings');
  const settingSfxVolume = $('setting-sfx-volume');
  const settingMusicVolume = $('setting-music-volume');
  const settingContrast = $('setting-contrast');

  function loadNumberSetting(key, fallback) {
    try {
      const v = parseInt(localStorage.getItem(key), 10);
      return isNaN(v) ? fallback : v;
    } catch (_) {
      return fallback;
    }
  }

  let sfxVolPct = loadNumberSetting('dp_sfx_volume', 100);
  let musicVolPct = loadNumberSetting('dp_music_volume', 100);
  let contrastLevel = loadNumberSetting('dp_contrast', 1);

  GameAudio.setSfxVolume(sfxVolPct / 100);
  GameAudio.setMusicVolume(musicVolPct / 100);
  document.body.dataset.contrast = String(contrastLevel);
  settingSfxVolume.value = sfxVolPct;
  settingMusicVolume.value = musicVolPct;
  settingContrast.value = contrastLevel;

  settingSfxVolume.addEventListener('input', () => {
    sfxVolPct = parseInt(settingSfxVolume.value, 10);
    GameAudio.setSfxVolume(sfxVolPct / 100);
    try { localStorage.setItem('dp_sfx_volume', String(sfxVolPct)); } catch (_) {}
  });
  settingMusicVolume.addEventListener('input', () => {
    musicVolPct = parseInt(settingMusicVolume.value, 10);
    GameAudio.setMusicVolume(musicVolPct / 100);
    try { localStorage.setItem('dp_music_volume', String(musicVolPct)); } catch (_) {}
  });
  settingContrast.addEventListener('input', () => {
    contrastLevel = parseInt(settingContrast.value, 10);
    document.body.dataset.contrast = String(contrastLevel);
    try { localStorage.setItem('dp_contrast', String(contrastLevel)); } catch (_) {}
  });

  function openSettingsModal() { settingsModal.classList.remove('hidden'); }
  function closeSettingsModal() { settingsModal.classList.add('hidden'); }
  $('btn-open-settings-join').addEventListener('click', openSettingsModal);
  $('btn-open-settings-room').addEventListener('click', openSettingsModal);
  btnCloseSettings.addEventListener('click', closeSettingsModal);
  settingsModal.addEventListener('click', e => { if (e.target === settingsModal) closeSettingsModal(); });

  // ---------- about modal ----------
  const aboutModal = $('about-modal');
  const btnCloseAbout = $('btn-close-about');
  function openAboutModal() { aboutModal.classList.remove('hidden'); }
  function closeAboutModal() { aboutModal.classList.add('hidden'); }
  $('btn-open-about-join').addEventListener('click', openAboutModal);
  $('btn-open-about-room').addEventListener('click', openAboutModal);
  btnCloseAbout.addEventListener('click', closeAboutModal);
  aboutModal.addEventListener('click', e => { if (e.target === aboutModal) closeAboutModal(); });

  // ---------- shop modal ----------
  function updateCoinDisplay() {
    coinBalanceEl.textContent = wallet.coins;
    shopCoinBalanceEl.textContent = wallet.coins;
  }

  function renderShop() {
    shopGridEl.innerHTML = '';
    iconCatalog.forEach(item => {
      const owned = wallet.ownedIcons.includes(item.id);
      const equipped = wallet.equippedIcon === item.id;
      const div = document.createElement('div');
      div.className = 'shop-item' + (owned ? ' owned' : '') + (equipped ? ' equipped' : '');

      const emoji = document.createElement('div');
      emoji.className = 'shop-item-emoji';
      emoji.textContent = item.emoji;
      div.appendChild(emoji);

      const name = document.createElement('div');
      name.className = 'shop-item-name';
      name.textContent = item.name;
      div.appendChild(name);

      const price = document.createElement('div');
      price.className = 'shop-item-price';
      price.textContent = owned ? 'Owned' : `🪙 ${item.price}`;
      div.appendChild(price);

      const btn = document.createElement('button');
      if (equipped) {
        btn.className = 'btn-equip';
        btn.textContent = 'Equipped';
        btn.disabled = true;
      } else if (owned) {
        btn.className = 'btn-equip';
        btn.textContent = 'Equip';
        btn.addEventListener('click', () => {
          shopErrorEl.textContent = '';
          ws.send(JSON.stringify({ type: 'equipIcon', iconId: item.id }));
        });
      } else {
        btn.textContent = 'Buy';
        btn.disabled = wallet.coins < item.price;
        btn.addEventListener('click', () => {
          shopErrorEl.textContent = '';
          ws.send(JSON.stringify({ type: 'buyIcon', iconId: item.id }));
        });
      }
      div.appendChild(btn);
      shopGridEl.appendChild(div);
    });
    if (wallet.equippedIcon) {
      const unequip = document.createElement('div');
      unequip.className = 'shop-item';
      const btn = document.createElement('button');
      btn.textContent = 'Unequip icon';
      btn.addEventListener('click', () => {
        shopErrorEl.textContent = '';
        ws.send(JSON.stringify({ type: 'equipIcon', iconId: null }));
      });
      unequip.appendChild(btn);
      shopGridEl.appendChild(unequip);
    }
  }

  function openShopModal() {
    shopErrorEl.textContent = '';
    updateCoinDisplay();
    renderShop();
    shopModal.classList.remove('hidden');
  }
  function closeShopModal() { shopModal.classList.add('hidden'); }
  btnOpenShop.addEventListener('click', openShopModal);
  btnCloseShop.addEventListener('click', closeShopModal);
  shopModal.addEventListener('click', e => { if (e.target === shopModal) closeShopModal(); });

  function handleMessage(msg) {
    switch (msg.type) {
      case 'joined': {
        me = msg.you;
        roomCode = msg.roomCode;
        hostId = msg.hostId;
        phase = msg.phase;
        settings = msg.settings;
        updatePlayers(msg.players);
        lobbyCode.textContent = roomCode;
        chatLog.innerHTML = '';
        msg.chat.forEach(appendChatEntry);
        screenJoin.classList.remove('active');
        screenRoom.classList.add('active');
        wallet = msg.wallet || wallet;
        iconCatalog = msg.iconCatalog || iconCatalog;
        updateCoinDisplay();
        renderRoster();
        renderLobby();
        applySettingsPreview(msg.settingsPreview);
        hideReconnectBanner();
        if (msg.resume) {
          applyResumeState(msg.resume);
        } else {
          showView('view-lobby');
        }
        break;
      }
      case 'error': {
        if (screenRoom.classList.contains('active')) {
          appendSystemMessage(msg.message);
          btnReconnect.disabled = false;
          btnReconnect.textContent = 'Reconnect';
        } else {
          joinError.textContent = msg.message;
          btnJoin.disabled = false;
        }
        break;
      }
      case 'playerList': {
        hostId = msg.hostId;
        updatePlayers(msg.players);
        renderRoster();
        if (phase === 'lobby') renderLobby();
        break;
      }
      case 'system': {
        appendSystemMessage(msg.text);
        break;
      }
      case 'chat': {
        appendChatEntry(msg);
        break;
      }
      case 'playerStatus': {
        const p = players.get(msg.id);
        if (p) { p.wordsCompleted = msg.wordsCompleted; p.doneDrawing = msg.doneDrawing; }
        break;
      }
      case 'voteStatus': {
        connectedVotedCount.voted = msg.votedIds.length;
        renderVoteProgress();
        break;
      }
      case 'guessStatus': {
        guessProgress.submitted = msg.submittedIds.length;
        renderGuessProgress();
        break;
      }
      case 'lobbySettingsPreview': {
        applySettingsPreview(msg.settings);
        break;
      }
      case 'phaseChange': {
        handlePhaseChange(msg);
        break;
      }
      case 'timedOut': {
        appendSystemMessage(`You were timed out from chat for ${Math.ceil((msg.mutedUntil - Date.now()) / 1000)}s.`);
        break;
      }
      case 'chatBlocked': {
        appendSystemMessage(msg.message);
        break;
      }
      case 'kicked': {
        alert('You were kicked from the room.');
        location.reload();
        break;
      }
      case 'banned': {
        alert('You were banned from this room.');
        location.reload();
        break;
      }
      case 'wallet': {
        wallet = { coins: msg.coins, ownedIcons: msg.ownedIcons, equippedIcon: msg.equippedIcon };
        updateCoinDisplay();
        if (!shopModal.classList.contains('hidden')) renderShop();
        break;
      }
      case 'shopError': {
        shopErrorEl.textContent = msg.message;
        break;
      }
    }
  }

  function currentWordViewActive() {
    return !$('view-canvas').classList.contains('hidden');
  }

  function updatePlayers(list) {
    const map = new Map();
    list.forEach(p => map.set(p.id, p));
    players = map;
    updatePlayersHereCount();
  }

  function updatePlayersHereCount() {
    const count = [...players.values()].filter(p => p.connected).length;
    playersHereCountEl.textContent = count;
  }

  function renderPlayersHerePopover() {
    playersHerePopoverEl.innerHTML = '';
    players.forEach(p => {
      const row = document.createElement('div');
      row.className = 'players-here-row';
      const dot = document.createElement('span');
      dot.className = 'dot role-' + (p.role || 'normal') + (p.connected ? '' : ' offline-dot');
      const name = document.createElement('span');
      name.style.color = colorForPlayer(p.id);
      name.textContent = (p.icon ? p.icon + ' ' : '') + p.name + (me && p.id === me.id ? ' (you)' : '');
      row.appendChild(dot);
      row.appendChild(name);
      if (!p.connected) {
        const away = document.createElement('span');
        away.className = 'away-tag';
        away.textContent = 'away';
        row.appendChild(away);
      }
      playersHerePopoverEl.appendChild(row);
    });
  }

  // ---------- lobby ----------
  function renderLobby() {
    const isHost = me && me.id === hostId;
    hostSettings.classList.remove('hidden');
    hostSettings.classList.toggle('suggest-mode', !isHost);
    suggestHint.classList.toggle('hidden', isHost);
    btnStart.classList.toggle('hidden', !isHost);
    nonHostMsg.classList.toggle('hidden', isHost);
    const enoughPlayers = players.size >= 2;
    btnStart.disabled = !enoughPlayers;
    btnStart.textContent = enoughPlayers ? 'Start Game' : `Need ${2 - players.size} more player${players.size === 1 ? '' : 's'}`;
  }

  // ---------- roster (persistent player list + moderation) ----------
  function renderRoster() {
    roster.innerHTML = '';
    players.forEach(p => roster.appendChild(rosterRow(p)));
  }

  function rosterRow(p) {
    const row = document.createElement('div');
    row.className = 'roster-row';

    const dot = document.createElement('span');
    dot.className = 'dot role-' + (p.role || 'normal');
    row.appendChild(dot);

    const nameSpan = document.createElement('span');
    nameSpan.className = 'rname' + (p.connected ? '' : ' offline');
    nameSpan.style.color = colorForPlayer(p.id);
    nameSpan.textContent = (p.icon ? p.icon + ' ' : '') + p.name + (me && p.id === me.id ? ' (you)' : '');
    row.appendChild(nameSpan);

    if (p.role === 'admin' || p.role === 'mod') {
      const badge = document.createElement('span');
      badge.className = 'badge';
      badge.textContent = p.role === 'admin' ? 'ADMIN' : 'MOD';
      row.appendChild(badge);
    }

    if (p.mutedUntil && p.mutedUntil > Date.now()) {
      const m = document.createElement('span');
      m.className = 'muted-badge';
      m.textContent = `muted ${Math.ceil((p.mutedUntil - Date.now()) / 1000)}s`;
      row.appendChild(m);
    }

    const isSelf = me && p.id === me.id;
    const iAmAdmin = me && me.id === hostId;
    const myRole = me ? (players.get(me.id) || {}).role : null;
    const iAmMod = myRole === 'mod';

    if (!isSelf && (iAmAdmin || iAmMod)) {
      const actions = document.createElement('div');
      actions.className = 'roster-actions';

      if (iAmAdmin || (iAmMod && p.role !== 'admin')) {
        const toBtn = document.createElement('button');
        toBtn.textContent = 'Timeout';
        toBtn.addEventListener('click', () => {
          const input = prompt(`Timeout ${p.name} for how many minutes? (0.02–60, e.g. 0.5 = 30 sec, 60 = 1 hour)`, '1');
          if (input === null) return;
          const mins = parseFloat(input);
          if (isNaN(mins) || mins <= 0) return;
          const seconds = Math.min(3600, Math.max(1, Math.round(mins * 60)));
          ws.send(JSON.stringify({ type: 'timeoutPlayer', targetId: p.id, seconds }));
        });
        actions.appendChild(toBtn);
      }

      if (iAmAdmin) {
        const modBtn = document.createElement('button');
        modBtn.textContent = p.role === 'mod' ? 'Un-mod' : 'Make Mod';
        modBtn.addEventListener('click', () => ws.send(JSON.stringify({
          type: p.role === 'mod' ? 'demoteMod' : 'promoteMod',
          targetId: p.id,
        })));
        actions.appendChild(modBtn);

        const kickBtn = document.createElement('button');
        kickBtn.className = 'btn-danger';
        kickBtn.textContent = 'Kick';
        kickBtn.addEventListener('click', () => {
          if (confirm(`Kick ${p.name}?`)) ws.send(JSON.stringify({ type: 'kickPlayer', targetId: p.id }));
        });
        actions.appendChild(kickBtn);

        const banBtn = document.createElement('button');
        banBtn.className = 'btn-danger';
        banBtn.textContent = 'Ban';
        banBtn.addEventListener('click', () => {
          if (confirm(`Ban ${p.name}? They won't be able to rejoin this room.`)) ws.send(JSON.stringify({ type: 'banPlayer', targetId: p.id }));
        });
        actions.appendChild(banBtn);
      }

      row.appendChild(actions);
    }

    return row;
  }

  setInterval(() => {
    if (screenRoom.classList.contains('active')) renderRoster();
  }, 3000);

  btnCopyCode.addEventListener('click', () => {
    navigator.clipboard?.writeText(roomCode).catch(() => {});
    btnCopyCode.textContent = 'Copied!';
    setTimeout(() => (btnCopyCode.textContent = 'Copy'), 1200);
  });

  btnPlayersHere.addEventListener('click', () => {
    renderPlayersHerePopover();
    playersHerePopoverEl.classList.toggle('hidden');
  });
  document.addEventListener('click', e => {
    if (!playersHerePopoverEl.classList.contains('hidden')
      && !playersHerePopoverEl.contains(e.target)
      && e.target !== btnPlayersHere) {
      playersHerePopoverEl.classList.add('hidden');
    }
  });

  const MODE_DESCRIPTIONS = {
    normal: 'Draw your word, get guessed, get voted on.',
    challenge: 'You only get a limited number of pen strokes per drawing — make them count.',
    perfectionist: 'Much harder, more abstract words. You get at least 10 minutes to nail it.',
    foggy: "A fog covers your canvas while you draw — you're mostly drawing blind. Hold Peek to sneak a look.",
    additive: 'After you finish a drawing, it gets handed to a different player to add more to it before guessing.',
    humanbody: "Everyone's assigned a body part based on player count. Draw your own words as usual — at the end, everyone's parts combine into one goofy human.",
    copyit: 'A real photo of your word loads up. Toggle "Reference" to cover your canvas with it and study it, then toggle again to hide it and draw. No guessing — you get a % match score instead, shown next to your drawing.',
    custom: 'No card grid — type your own word to draw. Keep it specific, not super abstract (no "Color", "Time", etc.).',
  };

  function updateModeUI() {
    const mode = settingMode.value;
    modeDescription.textContent = MODE_DESCRIPTIONS[mode] || '';
    challengeSettings.classList.toggle('hidden', mode !== 'challenge');
    if (mode === 'perfectionist') {
      settingSeconds.value = Math.max(600, parseInt(settingSeconds.value, 10) || 600);
      settingSeconds.min = 600;
    } else {
      settingSeconds.min = 5;
    }
  }

  function sendLobbySettingsPreview() {
    if (!me || me.id !== hostId) return;
    ws.send(JSON.stringify({
      type: 'updateLobbySettings',
      settings: {
        mode: settingMode.value,
        wordsPerPlayer: parseInt(settingWords.value, 10) || 5,
        drawSeconds: parseInt(settingSeconds.value, 10) || 300,
        guessSeconds: parseInt(settingGuessSeconds.value, 10) || 60,
        maxStrokes: parseInt(settingMaxStrokes.value, 10) || 3,
      },
    }));
  }

  function applySettingsPreview(preview) {
    if (!preview || (me && me.id === hostId)) return;
    settingMode.value = preview.mode;
    settingWords.value = preview.wordsPerPlayer;
    settingSeconds.value = preview.drawSeconds;
    settingGuessSeconds.value = preview.guessSeconds;
    settingMaxStrokes.value = preview.maxStrokes;
    updateModeUI();
  }

  function promptSuggestion(label) {
    if (!confirm(`Only the host can change "${label}". Want to suggest a change in chat instead?`)) return;
    const suggestion = prompt(`Suggest a value for "${label}":`, '');
    if (suggestion && suggestion.trim()) {
      ws.send(JSON.stringify({ type: 'chat', text: `💡 Suggestion for ${label}: ${suggestion.trim()}` }));
    }
  }

  settingMode.addEventListener('change', updateModeUI);
  updateModeUI();

  [settingMode, settingWords, settingSeconds, settingGuessSeconds, settingMaxStrokes].forEach(el => {
    el.addEventListener('mousedown', e => {
      if (me && me.id === hostId) return;
      e.preventDefault();
      promptSuggestion(el.dataset.suggestLabel || 'this setting');
    });
    el.addEventListener('keydown', e => {
      if (!(me && me.id === hostId)) e.preventDefault();
    });
    el.addEventListener('change', sendLobbySettingsPreview);
    el.addEventListener('input', sendLobbySettingsPreview);
  });

  btnStart.addEventListener('click', () => {
    ws.send(JSON.stringify({
      type: 'startGame',
      settings: {
        wordsPerPlayer: parseInt(settingWords.value, 10) || 5,
        drawSeconds: parseInt(settingSeconds.value, 10) || 300,
        guessSeconds: parseInt(settingGuessSeconds.value, 10) || 60,
        mode: settingMode.value,
        maxStrokes: parseInt(settingMaxStrokes.value, 10) || 3,
      },
    }));
  });

  // ---------- phase transitions ----------
  function handlePhaseChange(msg) {
    phase = msg.phase;
    if (phase === 'drawing') {
      settings = msg.settings;
      usedWords = new Set();
      wordsCompleted = 0;
      currentWord = null;
      inAdditiveTask = false;
      waitingHeading.textContent = 'Nice work! 🎉';
      waitingHint.textContent = 'Waiting for other players to finish drawing…';
      btnForceEnd.textContent = settings.mode === 'copyit'
        ? 'Skip waiting & move to voting (host)'
        : 'Skip waiting & start guessing (host)';
      progressTotal.textContent = settings.wordsPerPlayer;
      progressCount.textContent = '0';

      if (settings.mode === 'humanbody' && Array.isArray(msg.bodyParts)) {
        const mine = msg.bodyParts.find(bp => me && bp.id === me.id);
        myBodyPartLabel = mine ? mine.label : '';
        bodyPartBanner.textContent = `🧍 Your body part: ${myBodyPartLabel}`;
        bodyPartBanner.classList.remove('hidden');
      } else {
        bodyPartBanner.classList.add('hidden');
      }

      buildCardGrid();
      showView('view-card-picker');
    } else if (phase === 'additive') {
      stopWordTimer();
      inAdditiveTask = true;
      currentWord = msg.assignment.word;
      currentWordEl.textContent = msg.assignment.word;
      setupModeUI();
      loadImageOntoCanvas(msg.assignment.image, () => {
        undoStack = [];
        redoStack = [];
        pushHistory();
      });
      wordEndAt = Date.now() + msg.drawSeconds * 1000;
      startWordTimer();
      const isHost = me && me.id === hostId;
      btnForceEnd.classList.toggle('hidden', !isHost);
      showView('view-canvas');
    } else if (phase === 'guessing') {
      stopWordTimer();
      guessGallery = msg.gallery;
      guessSubmittedByMe = false;
      guessProgress = { submitted: 0, total: [...players.values()].filter(p => p.connected).length };
      renderGuessingGallery();
      const isHost = me && me.id === hostId;
      btnForceEndGuessing.classList.toggle('hidden', !isHost);
      guessEndAt = msg.guessEndAt;
      startGuessTimer();
      showView('view-guessing');
    } else if (phase === 'voting') {
      stopWordTimer();
      stopGuessTimer();
      gallery = msg.gallery;
      votedFor = null;
      connectedVotedCount = { voted: 0, total: [...players.values()].filter(p => p.connected).length };
      renderGallery();
      const isHost = me && me.id === hostId;
      btnForceEndVoting.classList.toggle('hidden', !isHost);
      showView('view-voting');
    } else if (phase === 'results') {
      GameAudio.sfxWin();
      renderResults(msg.results, msg.winnerIds);
      renderBodyComposite(msg.bodyComposite);
      showView('view-results');
    } else if (phase === 'lobby') {
      hostId = msg.hostId;
      updatePlayers(msg.players);
      renderRoster();
      renderLobby();
      showView('view-lobby');
    }
  }

  function applyResumeState(resume) {
    const isHost = me && me.id === hostId;
    if (resume.phase === 'drawing') {
      usedWords = new Set(resume.usedWords);
      wordsCompleted = resume.wordsCompleted;
      currentWord = null;
      progressTotal.textContent = settings.wordsPerPlayer;
      progressCount.textContent = String(wordsCompleted);
      waitingHeading.textContent = 'Nice work! 🎉';
      waitingHint.textContent = 'Waiting for other players to finish drawing…';
      buildCardGrid();
      markUsedCards();
      if (resume.doneDrawing) {
        btnForceEnd.classList.toggle('hidden', !isHost);
        showView('view-waiting');
      } else {
        showView('view-card-picker');
      }
    } else if (resume.phase === 'additive') {
      if (resume.alreadySubmitted || !resume.assignment) {
        waitingHeading.textContent = 'Nice touch! 🎉';
        waitingHint.textContent = 'Waiting for everyone to finish adding to their assigned drawing…';
        btnForceEnd.classList.toggle('hidden', !isHost);
        showView('view-waiting');
      } else {
        inAdditiveTask = true;
        currentWord = resume.assignment.word;
        currentWordEl.textContent = resume.assignment.word;
        setupModeUI();
        loadImageOntoCanvas(resume.assignment.image, () => {
          undoStack = [];
          redoStack = [];
          pushHistory();
        });
        wordEndAt = Date.now() + resume.drawSeconds * 1000;
        startWordTimer();
        btnForceEnd.classList.toggle('hidden', !isHost);
        showView('view-canvas');
      }
    } else if (resume.phase === 'guessing') {
      guessGallery = resume.gallery;
      guessSubmittedByMe = resume.alreadySubmitted;
      guessProgress = { submitted: 0, total: [...players.values()].filter(p => p.connected).length };
      renderGuessingGallery();
      if (resume.alreadySubmitted) {
        guessInputs.forEach(input => { input.disabled = true; });
        btnSubmitGuesses.disabled = true;
        btnSubmitGuesses.textContent = 'Waiting for others…';
      }
      btnForceEndGuessing.classList.toggle('hidden', !isHost);
      guessEndAt = resume.guessEndAt;
      startGuessTimer();
      showView('view-guessing');
    } else if (resume.phase === 'voting') {
      stopGuessTimer();
      gallery = resume.gallery;
      votedFor = resume.alreadyVoted ? -1 : null;
      renderGallery();
      if (resume.alreadyVoted) {
        [...galleryEl.querySelectorAll('.btn-vote')].forEach(b => (b.disabled = true));
      }
      btnForceEndVoting.classList.toggle('hidden', !isHost);
      showView('view-voting');
    } else if (resume.phase === 'results') {
      renderResults(resume.results, resume.winnerIds);
      renderBodyComposite(resume.bodyComposite);
      showView('view-results');
    } else {
      showView('view-lobby');
    }
  }

  // ---------- card picker ----------
  function buildCardGrid() {
    const isCustom = settings.mode === 'custom';
    cardSearch.classList.toggle('hidden', isCustom);
    cardGrid.classList.toggle('hidden', isCustom);
    customWordSection.classList.toggle('hidden', !isCustom);
    if (isCustom) {
      inputCustomWord.value = '';
      customWordError.textContent = '';
      return;
    }

    cardGrid.innerHTML = '';
    const wordList = settings.mode === 'perfectionist' ? HARD_WORDS : WORDS;
    wordList.forEach(word => {
      const div = document.createElement('div');
      div.className = 'word-card';
      div.textContent = word;
      div.dataset.word = word;
      div.addEventListener('click', () => pickWord(word));
      cardGrid.appendChild(div);
    });
    cardSearch.value = '';
  }

  const GENERIC_ABSTRACT_WORDS = [
    'color', 'colour', 'animal', 'food', 'shape', 'emotion', 'feeling', 'object', 'thing',
    'idea', 'concept', 'sound', 'smell', 'taste', 'texture', 'number', 'letter', 'word',
    'place', 'weather', 'direction', 'quality', 'quantity', 'style', 'type', 'kind',
    'category', 'size', 'speed', 'distance', 'weight', 'sense', 'thought', 'memory',
    'opinion', 'belief', 'value', 'meaning', 'energy', 'motion', 'action', 'mood', 'plant',
  ];

  function normalizeForAbstractCheck(word) {
    let w = word.toLowerCase().trim();
    if (w.endsWith('s') && w.length > 3) w = w.slice(0, -1);
    return w;
  }

  function isTooAbstract(word) {
    const normalized = normalizeForAbstractCheck(word);
    if (GENERIC_ABSTRACT_WORDS.includes(normalized)) return true;
    return HARD_WORDS.some(hw => normalizeForAbstractCheck(hw) === normalized);
  }

  btnSubmitCustomWord.addEventListener('click', () => {
    const word = inputCustomWord.value.trim();
    if (!word) { customWordError.textContent = 'Type something to draw.'; return; }
    if (isTooAbstract(word)) {
      customWordError.textContent = `"${word}" is too abstract — try something more specific!`;
      return;
    }
    customWordError.textContent = '';
    pickWord(word);
  });

  inputCustomWord.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); btnSubmitCustomWord.click(); }
  });

  cardSearch.addEventListener('input', () => {
    const term = cardSearch.value.trim().toLowerCase();
    [...cardGrid.children].forEach(card => {
      card.style.display = card.dataset.word.toLowerCase().includes(term) ? '' : 'none';
    });
  });

  function pickWord(word) {
    if (usedWords.has(word)) return;
    GameAudio.sfxPick();
    currentWord = word;
    currentWordEl.textContent = word;
    clearCanvas();
    undoStack = [];
    redoStack = [];
    pushHistory();
    wordEndAt = Date.now() + settings.drawSeconds * 1000;
    startWordTimer();
    setupModeUI();
    if (settings.mode === 'copyit') loadReferencePhoto(word);
    showView('view-canvas');
  }

  function setupModeUI() {
    strokesUsed = 0;
    const isChallenge = settings.mode === 'challenge';
    strokesLeftEl.classList.toggle('hidden', !isChallenge);
    updateStrokesLeftDisplay();

    const isFoggy = settings.mode === 'foggy';
    fogOverlay.classList.toggle('hidden', !isFoggy);
    fogOverlay.classList.remove('peeking');
    btnPeek.classList.toggle('hidden', !isFoggy);

    const isCopyIt = settings.mode === 'copyit';
    btnReference.classList.toggle('hidden', !isCopyIt);
    referenceShown = false;
    referenceOverlay.classList.add('hidden');
    btnReference.classList.remove('active');
    btnReference.textContent = '📷 Reference';
  }

  function updateStrokesLeftDisplay() {
    if (settings.mode !== 'challenge') return;
    const remaining = Math.max(0, settings.maxStrokes - strokesUsed);
    strokesLeftEl.textContent = `${remaining} stroke${remaining === 1 ? '' : 's'} left`;
    strokesLeftEl.classList.toggle('low', remaining <= 1);
  }

  function strokesExhausted() {
    return settings.mode === 'challenge' && strokesUsed >= settings.maxStrokes;
  }

  function consumeStroke() {
    if (settings.mode !== 'challenge') return;
    strokesUsed++;
    updateStrokesLeftDisplay();
  }

  // ---------- copy it (reference photo) ----------
  function loadReferencePhoto(word) {
    const token = ++referenceRequestToken;
    referenceImg.removeAttribute('src');
    referenceLoading.classList.remove('hidden');
    referenceMissing.classList.add('hidden');

    const apply = url => {
      if (token !== referenceRequestToken) return;
      referenceLoading.classList.add('hidden');
      if (url) {
        referenceImg.crossOrigin = 'anonymous';
        referenceImg.src = url;
        referenceMissing.classList.add('hidden');
      } else {
        referenceImg.removeAttribute('src');
        referenceMissing.classList.remove('hidden');
      }
    };

    if (referenceCache.has(word)) { apply(referenceCache.get(word)); return; }

    fetch(`https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(word)}`)
      .then(r => (r.ok ? r.json() : null))
      .then(data => {
        const url = data && data.thumbnail && data.thumbnail.source ? data.thumbnail.source : null;
        referenceCache.set(word, url);
        apply(url);
      })
      .catch(() => { referenceCache.set(word, null); apply(null); });
  }

  btnReference.addEventListener('click', () => {
    referenceShown = !referenceShown;
    referenceOverlay.classList.toggle('hidden', !referenceShown);
    btnReference.classList.toggle('active', referenceShown);
    btnReference.textContent = referenceShown ? '✏️ Back to Drawing' : '📷 Reference';
  });

  function computeMatchPercent() {
    if (!referenceImg.src || !referenceMissing.classList.contains('hidden')) return null;
    try {
      const SIZE = 40;
      const refCanvas = document.createElement('canvas');
      refCanvas.width = SIZE;
      refCanvas.height = SIZE;
      const refCtx = refCanvas.getContext('2d');
      refCtx.drawImage(referenceImg, 0, 0, SIZE, SIZE);
      const refData = refCtx.getImageData(0, 0, SIZE, SIZE).data;

      const drawCanvas = document.createElement('canvas');
      drawCanvas.width = SIZE;
      drawCanvas.height = SIZE;
      const drawCtx = drawCanvas.getContext('2d');
      drawCtx.fillStyle = '#fffdf7';
      drawCtx.fillRect(0, 0, SIZE, SIZE);
      drawCtx.drawImage(paper, 0, 0, SIZE, SIZE);
      const drawData = drawCtx.getImageData(0, 0, SIZE, SIZE).data;

      // "% match" = how much of the reference photo's structure (dark/subject pixels)
      // got covered by ink in the player's drawing. A blank canvas scores 0, not
      // a coincidentally-high score from matching bright background pixels.
      let refInkCount = 0;
      let coveredCount = 0;
      const total = SIZE * SIZE;
      for (let i = 0; i < total; i++) {
        const idx = i * 4;
        const refGray = (refData[idx] + refData[idx + 1] + refData[idx + 2]) / 3;
        const refInk = refGray < 140;
        if (!refInk) continue;
        refInkCount++;
        const drawGray = (drawData[idx] + drawData[idx + 1] + drawData[idx + 2]) / 3;
        if (drawGray < 200) coveredCount++;
      }
      return refInkCount > 0 ? Math.round((coveredCount / refInkCount) * 100) : 0;
    } catch (e) {
      return null;
    }
  }

  // ---------- timer ----------
  function startWordTimer() {
    stopWordTimer();
    updateTimerDisplay();
    timerHandle = setInterval(() => {
      const remaining = wordEndAt - Date.now();
      if (remaining <= 0) {
        stopWordTimer();
        submitDrawing();
        return;
      }
      updateTimerDisplay();
    }, 250);
  }

  function stopWordTimer() {
    if (timerHandle) clearInterval(timerHandle);
    timerHandle = null;
  }

  function updateTimerDisplay() {
    const remaining = Math.max(0, wordEndAt - Date.now());
    const s = Math.ceil(remaining / 1000);
    const m = Math.floor(s / 60);
    const sec = String(s % 60).padStart(2, '0');
    wordTimerEl.textContent = `${m}:${sec}`;
    wordTimerEl.classList.toggle('low', s <= 30);
  }

  function startGuessTimer() {
    stopGuessTimer();
    updateGuessTimerDisplay();
    guessTimerHandle = setInterval(() => {
      if (Date.now() >= guessEndAt) { stopGuessTimer(); return; }
      updateGuessTimerDisplay();
    }, 250);
  }

  function stopGuessTimer() {
    if (guessTimerHandle) clearInterval(guessTimerHandle);
    guessTimerHandle = null;
  }

  function updateGuessTimerDisplay() {
    const remaining = Math.max(0, guessEndAt - Date.now());
    const s = Math.ceil(remaining / 1000);
    const m = Math.floor(s / 60);
    const sec = String(s % 60).padStart(2, '0');
    guessTimerEl.textContent = `${m}:${sec}`;
    guessTimerEl.classList.toggle('low', s <= 15);
  }

  // ---------- canvas ----------
  function initCanvas() {
    ctx = paper.getContext('2d');
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    clearCanvas();

    SWATCH_COLORS.forEach((color, i) => {
      const sw = document.createElement('div');
      sw.className = 'swatch' + (i === 0 ? ' active' : '');
      sw.style.background = color;
      sw.addEventListener('click', () => {
        brushColor = color;
        eraserOn = false;
        btnEraser.classList.remove('active');
        [...swatchesEl.children].forEach(c => c.classList.remove('active'));
        sw.classList.add('active');
      });
      swatchesEl.appendChild(sw);
    });

    colorPicker.addEventListener('input', () => {
      brushColor = colorPicker.value;
      eraserOn = false;
      btnEraser.classList.remove('active');
      [...swatchesEl.children].forEach(c => c.classList.remove('active'));
    });

    function updateSizeLabel() {
      brushSizeLabel.textContent = `${brushSize}px`;
      [...sizePresets.children].forEach(b => b.classList.toggle('active', parseInt(b.dataset.size, 10) === brushSize));
    }

    brushSizeInput.addEventListener('input', () => {
      brushSize = parseInt(brushSizeInput.value, 10);
      updateSizeLabel();
    });

    sizePresets.addEventListener('click', e => {
      const btn = e.target.closest('.size-preset-btn');
      if (!btn) return;
      brushSize = parseInt(btn.dataset.size, 10);
      brushSizeInput.value = brushSize;
      updateSizeLabel();
    });

    btnEraser.addEventListener('click', () => {
      eraserOn = !eraserOn;
      btnEraser.classList.toggle('active', eraserOn);
      if (eraserOn) { bucketOn = false; btnBucket.classList.remove('active'); }
    });

    btnBucket.addEventListener('click', () => {
      bucketOn = !bucketOn;
      btnBucket.classList.toggle('active', bucketOn);
      if (bucketOn) { eraserOn = false; btnEraser.classList.remove('active'); }
    });

    btnClear.addEventListener('click', () => { clearCanvas(); pushHistory(); });
    btnSubmit.addEventListener('click', () => submitDrawing());
    btnUndo.addEventListener('click', undo);
    btnRedo.addEventListener('click', redo);

    const startPeek = () => fogOverlay.classList.add('peeking');
    const endPeek = () => fogOverlay.classList.remove('peeking');
    btnPeek.addEventListener('pointerdown', startPeek);
    btnPeek.addEventListener('pointerup', endPeek);
    btnPeek.addEventListener('pointerleave', endPeek);
    btnPeek.addEventListener('pointercancel', endPeek);

    paper.addEventListener('pointerdown', e => {
      if (strokesExhausted()) return;
      const p = canvasPoint(e);
      if (bucketOn) {
        if (floodFill(Math.floor(p.x), Math.floor(p.y), brushColor)) {
          pushHistory();
          consumeStroke();
        }
        return;
      }
      drawingActive = true;
      strokeDrew = false;
      paper.setPointerCapture(e.pointerId);
      lastPoint = p;
    });
    paper.addEventListener('pointermove', e => {
      if (!drawingActive) return;
      const p = canvasPoint(e);
      drawLine(lastPoint, p);
      lastPoint = p;
      strokeDrew = true;
    });
    const endStroke = () => {
      if (drawingActive && strokeDrew) {
        pushHistory();
        consumeStroke();
      }
      drawingActive = false;
      lastPoint = null;
    };
    paper.addEventListener('pointerup', endStroke);
    paper.addEventListener('pointerleave', endStroke);
    paper.addEventListener('pointercancel', endStroke);

    updateUndoRedoButtons();
  }

  function canvasPoint(e) {
    const rect = paper.getBoundingClientRect();
    const scaleX = paper.width / rect.width;
    const scaleY = paper.height / rect.height;
    return { x: (e.clientX - rect.left) * scaleX, y: (e.clientY - rect.top) * scaleY };
  }

  function drawLine(from, to) {
    ctx.strokeStyle = eraserOn ? '#fffdf7' : brushColor;
    ctx.lineWidth = eraserOn ? brushSize * 2.2 : brushSize;
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  }

  function clearCanvas() {
    ctx.fillStyle = '#fffdf7';
    ctx.fillRect(0, 0, paper.width, paper.height);
  }

  function loadImageOntoCanvas(dataUrl, callback) {
    const img = new Image();
    img.onload = () => {
      ctx.fillStyle = '#fffdf7';
      ctx.fillRect(0, 0, paper.width, paper.height);
      ctx.drawImage(img, 0, 0, paper.width, paper.height);
      if (callback) callback();
    };
    img.src = dataUrl;
  }

  function hexToRgb(hex) {
    const v = hex.replace('#', '');
    const full = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
    const n = parseInt(full, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  function colorsClose(r1, g1, b1, a1, r2, g2, b2, a2, tol) {
    return Math.abs(r1 - r2) <= tol && Math.abs(g1 - g2) <= tol
      && Math.abs(b1 - b2) <= tol && Math.abs(a1 - a2) <= tol;
  }

  function floodFill(startX, startY, fillHex) {
    const w = paper.width, h = paper.height;
    if (startX < 0 || startX >= w || startY < 0 || startY >= h) return false;

    const imgData = ctx.getImageData(0, 0, w, h);
    const data = imgData.data;
    const startIdx = (startY * w + startX) * 4;
    const targetR = data[startIdx], targetG = data[startIdx + 1], targetB = data[startIdx + 2], targetA = data[startIdx + 3];
    const fill = hexToRgb(fillHex);
    const TOLERANCE = 32;

    if (colorsClose(targetR, targetG, targetB, targetA, fill.r, fill.g, fill.b, 255, 4)) return false;

    const visited = new Uint8Array(w * h);
    const stack = [startX, startY];

    while (stack.length) {
      const y = stack.pop();
      const x = stack.pop();
      if (x < 0 || x >= w || y < 0 || y >= h) continue;
      const vIdx = y * w + x;
      if (visited[vIdx]) continue;
      const idx = vIdx * 4;
      if (!colorsClose(data[idx], data[idx + 1], data[idx + 2], data[idx + 3], targetR, targetG, targetB, targetA, TOLERANCE)) continue;
      visited[vIdx] = 1;
      data[idx] = fill.r; data[idx + 1] = fill.g; data[idx + 2] = fill.b; data[idx + 3] = 255;
      stack.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
    }

    ctx.putImageData(imgData, 0, 0);
    return true;
  }

  // ---------- undo / redo ----------
  function pushHistory() {
    const snapshot = ctx.getImageData(0, 0, paper.width, paper.height);
    undoStack.push(snapshot);
    if (undoStack.length > MAX_HISTORY) undoStack.shift();
    redoStack = [];
    updateUndoRedoButtons();
  }

  function undo() {
    if (undoStack.length <= 1) return;
    const current = undoStack.pop();
    redoStack.push(current);
    ctx.putImageData(undoStack[undoStack.length - 1], 0, 0);
    updateUndoRedoButtons();
  }

  function redo() {
    if (redoStack.length === 0) return;
    const next = redoStack.pop();
    undoStack.push(next);
    ctx.putImageData(next, 0, 0);
    updateUndoRedoButtons();
  }

  function updateUndoRedoButtons() {
    btnUndo.disabled = undoStack.length <= 1;
    btnRedo.disabled = redoStack.length === 0;
  }

  document.addEventListener('keydown', e => {
    const tag = document.activeElement && document.activeElement.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (!currentWordViewActive()) return;

    if (e.key === 'Enter') { submitDrawing(); return; }

    const cmdOrCtrl = e.metaKey || e.ctrlKey;
    if (cmdOrCtrl && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) redo(); else undo();
    } else if (cmdOrCtrl && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      redo();
    }
  });

  function submitDrawing() {
    if (!currentWord) return;
    GameAudio.sfxSubmit();
    stopWordTimer();
    const image = paper.toDataURL('image/png');

    if (inAdditiveTask) {
      ws.send(JSON.stringify({ type: 'submitAdditive', image }));
      inAdditiveTask = false;
      currentWord = null;
      waitingHeading.textContent = 'Nice touch! 🎉';
      waitingHint.textContent = 'Waiting for everyone to finish adding to their assigned drawing…';
      const isHost = me && me.id === hostId;
      btnForceEnd.classList.toggle('hidden', !isHost);
      showView('view-waiting');
      return;
    }

    const matchPercent = settings.mode === 'copyit' ? computeMatchPercent() : null;
    ws.send(JSON.stringify({ type: 'submitDrawing', word: currentWord, image, matchPercent }));
    usedWords.add(currentWord);
    wordsCompleted++;
    progressCount.textContent = String(wordsCompleted);
    currentWord = null;

    if (wordsCompleted >= settings.wordsPerPlayer) {
      const isHost = me && me.id === hostId;
      btnForceEnd.classList.toggle('hidden', !isHost);
      showView('view-waiting');
    } else {
      markUsedCards();
      if (settings.mode === 'custom') {
        inputCustomWord.value = '';
        customWordError.textContent = '';
      }
      showView('view-card-picker');
    }
  }

  function markUsedCards() {
    [...cardGrid.children].forEach(card => {
      card.classList.toggle('used', usedWords.has(card.dataset.word));
    });
  }

  btnForceEnd.addEventListener('click', () => {
    ws.send(JSON.stringify({ type: phase === 'additive' ? 'forceEndAdditive' : 'forceEndDrawing' }));
  });

  // ---------- guessing ----------
  function renderGuessingGallery() {
    guessingGalleryEl.innerHTML = '';
    guessInputs = new Map();
    btnSubmitGuesses.disabled = false;
    btnSubmitGuesses.textContent = 'Submit Guesses';

    const progressLine = document.createElement('p');
    progressLine.className = 'hint';
    progressLine.id = 'guess-progress-line';
    guessingGalleryEl.appendChild(progressLine);

    guessGallery.forEach(entry => {
      const div = document.createElement('div');
      div.className = 'gallery-entry';

      const header = document.createElement('div');
      header.className = 'gallery-entry-header';
      const h3 = document.createElement('h3');
      h3.textContent = entry.name + (entry.id === me.id ? ' (you)' : '');
      header.appendChild(h3);
      div.appendChild(header);

      const thumbs = document.createElement('div');
      thumbs.className = 'gallery-thumbs';
      entry.portfolio.forEach(item => {
        const t = document.createElement('div');
        t.className = 'gallery-thumb';
        const img = document.createElement('img');
        img.src = item.image;
        img.alt = 'drawing';
        t.appendChild(img);

        if (entry.id === me.id) {
          const label = document.createElement('div');
          label.className = 'own-label';
          label.textContent = "Your drawing";
          t.appendChild(label);
        } else {
          const input = document.createElement('input');
          input.className = 'guess-input';
          input.maxLength = 60;
          input.placeholder = 'Your guess…';
          input.autocomplete = 'off';
          guessInputs.set(item.drawingId, input);
          t.appendChild(input);
        }

        thumbs.appendChild(t);
      });
      div.appendChild(thumbs);

      guessingGalleryEl.appendChild(div);
    });
    renderGuessProgress();
  }

  function renderGuessProgress() {
    const line = $('guess-progress-line');
    if (line) line.textContent = `${guessProgress.submitted} of ${guessProgress.total} players have submitted guesses.`;
  }

  btnSubmitGuesses.addEventListener('click', () => {
    if (guessSubmittedByMe) return;
    guessSubmittedByMe = true;
    GameAudio.sfxSubmit();
    const guesses = {};
    guessInputs.forEach((input, drawingId) => { guesses[drawingId] = input.value; });
    ws.send(JSON.stringify({ type: 'submitGuesses', guesses }));
    guessInputs.forEach(input => { input.disabled = true; });
    btnSubmitGuesses.disabled = true;
    btnSubmitGuesses.textContent = 'Waiting for others…';
  });

  btnForceEndGuessing.addEventListener('click', () => ws.send(JSON.stringify({ type: 'forceEndGuessing' })));

  // ---------- voting ----------
  function renderGallery() {
    galleryEl.innerHTML = '';
    const progressLine = document.createElement('p');
    progressLine.className = 'hint';
    progressLine.id = 'vote-progress-line';
    galleryEl.appendChild(progressLine);

    gallery.forEach(entry => {
      const div = document.createElement('div');
      div.className = 'gallery-entry';

      const header = document.createElement('div');
      header.className = 'gallery-entry-header';
      const h3 = document.createElement('h3');
      h3.textContent = entry.name + (entry.id === me.id ? ' (you)' : '');
      header.appendChild(h3);

      if (entry.id !== me.id) {
        const btn = document.createElement('button');
        btn.className = 'btn-vote';
        btn.textContent = 'Vote for ' + entry.name;
        btn.addEventListener('click', () => castVote(entry.id, btn));
        header.appendChild(btn);
      }
      div.appendChild(header);

      const thumbs = document.createElement('div');
      thumbs.className = 'gallery-thumbs';
      entry.portfolio.forEach(item => {
        const t = document.createElement('div');
        t.className = 'gallery-thumb';
        const img = document.createElement('img');
        img.src = item.image;
        img.alt = item.word;
        const label = document.createElement('div');
        label.className = 'word-label';
        label.textContent = item.word;
        t.appendChild(img);
        t.appendChild(label);
        if (typeof item.matchPercent === 'number') {
          const match = document.createElement('div');
          match.className = 'match-badge';
          match.textContent = `${item.matchPercent}% match`;
          t.appendChild(match);
        }
        thumbs.appendChild(t);
      });
      div.appendChild(thumbs);

      galleryEl.appendChild(div);
    });
    renderVoteProgress();
  }

  function renderVoteProgress() {
    const line = $('vote-progress-line');
    if (line) line.textContent = `${connectedVotedCount.voted} of ${connectedVotedCount.total} players have voted.`;
  }

  function castVote(targetId, btn) {
    if (votedFor !== null) return;
    GameAudio.sfxVote();
    votedFor = targetId;
    ws.send(JSON.stringify({ type: 'vote', targetId }));
    [...galleryEl.querySelectorAll('.btn-vote')].forEach(b => (b.disabled = true));
    btn.classList.add('voted-for');
    btn.textContent = 'Voted!';
  }

  btnForceEndVoting.addEventListener('click', () => ws.send(JSON.stringify({ type: 'forceEndVoting' })));

  // ---------- results ----------
  function renderResults(results, winnerIds) {
    const topScore = results.length ? results[0].totalScore : 0;
    if (winnerIds.length === 0) {
      winnerBanner.textContent = 'No points were scored.';
    } else {
      const names = winnerIds.map(id => (results.find(r => r.id === id) || {}).name).filter(Boolean);
      winnerBanner.textContent = `🏆 ${names.join(' & ')} won with ${topScore} point${topScore === 1 ? '' : 's'}!`;
    }
    resultsList.innerHTML = '';
    results.forEach((r, i) => {
      const row = document.createElement('div');
      row.className = 'result-row' + (winnerIds.includes(r.id) ? ' winner' : '');
      const breakdown = `${r.guessPoints} guessed + ${r.votes} vote${r.votes === 1 ? '' : 's'}×2`;
      const coinsTag = r.coinsWon ? ` <span class="hint">+🪙 ${r.coinsWon}</span>` : '';
      row.innerHTML = `<span class="rank">#${i + 1}</span><span class="rname">${escapeHtml(r.name)}</span><span class="rvotes">${r.totalScore} pt${r.totalScore === 1 ? '' : 's'} <span class="hint">(${breakdown})</span>${coinsTag}</span>`;
      resultsList.appendChild(row);
    });
    const isHost = me && me.id === hostId;
    btnPlayAgain.classList.toggle('hidden', !isHost);
    resultsNonHostMsg.classList.toggle('hidden', isHost);
  }

  function renderBodyComposite(parts) {
    if (!parts || !parts.length) {
      bodyComposite.classList.add('hidden');
      return;
    }
    bodyCompositeParts.innerHTML = '';
    parts.forEach(part => {
      const div = document.createElement('div');
      div.className = 'body-composite-part';
      const img = document.createElement('img');
      img.src = part.image;
      img.alt = part.label;
      const label = document.createElement('div');
      label.className = 'part-label';
      label.textContent = `${part.label} — by ${part.name}`;
      div.appendChild(img);
      div.appendChild(label);
      bodyCompositeParts.appendChild(div);
    });
    bodyComposite.classList.remove('hidden');
  }

  btnPlayAgain.addEventListener('click', () => ws.send(JSON.stringify({ type: 'playAgain' })));

  // ---------- chat ----------
  chatForm.addEventListener('submit', e => {
    e.preventDefault();
    const text = chatInput.value.trim();
    if (!text) return;
    ws.send(JSON.stringify({ type: 'chat', text }));
    chatInput.value = '';
  });

  // ---------- emoji picker ----------
  const EMOJIS = [
    '😀','😂','😅','😉','😊','😍','😘','😜','🤔','😎',
    '😭','😱','😡','🥳','😴','🤗','🙄','😬','🤯','🥺',
    '👍','👎','👏','🙌','🙏','💪','👋','🤝','✌️','🤞',
    '❤️','💔','💯','🔥','⭐','✨','🎉','🎨','🖌️','🏆',
    '🐶','🐱','🐸','🦄','🐢','🍕','🍔','🍩','☕','🍿',
    '⏰','💡','❓','❗','✅','❌','🤷','😅','🫠','🤡',
  ];
  let emojiPanelBuilt = false;
  function buildEmojiPanel() {
    if (emojiPanelBuilt) return;
    emojiPanelBuilt = true;
    EMOJIS.forEach(em => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.textContent = em;
      btn.addEventListener('click', () => insertEmoji(em));
      emojiPanel.appendChild(btn);
    });
  }
  function insertEmoji(em) {
    const start = chatInput.selectionStart ?? chatInput.value.length;
    const end = chatInput.selectionEnd ?? chatInput.value.length;
    chatInput.value = chatInput.value.slice(0, start) + em + chatInput.value.slice(end);
    const cursor = start + em.length;
    chatInput.focus();
    chatInput.setSelectionRange(cursor, cursor);
  }
  btnEmoji.addEventListener('click', () => {
    buildEmojiPanel();
    emojiPanel.classList.toggle('hidden');
  });
  document.addEventListener('click', e => {
    if (!emojiPanel.classList.contains('hidden') && !emojiPanel.contains(e.target) && e.target !== btnEmoji) {
      emojiPanel.classList.add('hidden');
    }
  });

  // ---------- text-to-speech ----------
  let ttsEnabled = false;
  btnToggleTts.addEventListener('click', () => {
    ttsEnabled = !ttsEnabled;
    btnToggleTts.classList.toggle('active', ttsEnabled);
    btnToggleTts.textContent = ttsEnabled ? '🔊 Voice: On' : '🔈 Voice: Off';
    if (!ttsEnabled && window.speechSynthesis) window.speechSynthesis.cancel();
  });
  function speak(text) {
    if (!ttsEnabled || !window.speechSynthesis) return;
    const utter = new SpeechSynthesisUtterance(text);
    utter.rate = 1.05;
    utter.volume = 0.8;
    window.speechSynthesis.speak(utter);
  }

  function appendChatEntry(entry) {
    GameAudio.sfxChat();
    speak(`${entry.name} says: ${entry.text}`);
    const div = document.createElement('div');
    div.className = 'chat-msg';
    const color = entry.id != null ? colorForPlayer(entry.id) : 'var(--accent2)';
    const iconPrefix = entry.icon ? `<span class="who-icon">${entry.icon}</span>` : '';
    div.innerHTML = `<span class="who" style="color:${color}">${iconPrefix}${escapeHtml(entry.name)}:</span> ${escapeHtml(entry.text)}`;
    chatLog.appendChild(div);
    chatLog.scrollTop = chatLog.scrollHeight;
  }

  function appendSystemMessage(text) {
    GameAudio.sfxJoinLeave();
    const div = document.createElement('div');
    div.className = 'chat-msg system';
    div.textContent = text;
    chatLog.appendChild(div);
    chatLog.scrollTop = chatLog.scrollHeight;
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  // ---------- lobby doodle pad (personal, local-only scratch space) ----------
  function initLobbyDoodle() {
    const canvas = $('lobby-paper');
    const dctx = canvas.getContext('2d');
    dctx.lineCap = 'round';
    dctx.lineJoin = 'round';

    function clearDoodle() {
      dctx.fillStyle = '#fffdf7';
      dctx.fillRect(0, 0, canvas.width, canvas.height);
    }
    clearDoodle();

    let drawingDoodle = false;
    let lastDoodlePoint = null;

    function doodlePoint(e) {
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      return { x: (e.clientX - rect.left) * scaleX, y: (e.clientY - rect.top) * scaleY };
    }

    canvas.addEventListener('pointerdown', e => {
      drawingDoodle = true;
      canvas.setPointerCapture(e.pointerId);
      lastDoodlePoint = doodlePoint(e);
    });
    canvas.addEventListener('pointermove', e => {
      if (!drawingDoodle) return;
      const p = doodlePoint(e);
      dctx.strokeStyle = '#2a2540';
      dctx.lineWidth = 3;
      dctx.beginPath();
      dctx.moveTo(lastDoodlePoint.x, lastDoodlePoint.y);
      dctx.lineTo(p.x, p.y);
      dctx.stroke();
      lastDoodlePoint = p;
    });
    const endDoodleStroke = () => { drawingDoodle = false; lastDoodlePoint = null; };
    canvas.addEventListener('pointerup', endDoodleStroke);
    canvas.addEventListener('pointerleave', endDoodleStroke);
    canvas.addEventListener('pointercancel', endDoodleStroke);

    $('btn-lobby-clear').addEventListener('click', clearDoodle);
  }

  // ---------- friends system (separate connection, self-contained) ----------
  let friendsWs = null;
  let myUsername = null;
  try { myUsername = localStorage.getItem('dp_username'); } catch (_) { myUsername = null; }
  let lastFriendsSnapshot = { friends: [], incoming: [], outgoing: [] };

  const friendsModal = $('friends-modal');
  const btnCloseFriends = $('btn-close-friends');
  const friendsClaimSection = $('friends-claim-section');
  const inputClaimUsername = $('input-claim-username');
  const btnClaimUsername = $('btn-claim-username');
  const claimError = $('claim-error');
  const friendsMainSection = $('friends-main-section');
  const myUsernameDisplay = $('my-username-display');
  const btnRenameUsername = $('btn-rename-username');
  const renameRow = $('rename-row');
  const inputRenameUsername = $('input-rename-username');
  const btnConfirmRename = $('btn-confirm-rename');
  const renameError = $('rename-error');
  const inputAddFriend = $('input-add-friend');
  const btnSendFriendRequest = $('btn-send-friend-request');
  const friendRequestError = $('friend-request-error');
  const incomingRequestsSection = $('incoming-requests-section');
  const incomingRequestsList = $('incoming-requests-list');
  const outgoingRequestsSection = $('outgoing-requests-section');
  const outgoingRequestsList = $('outgoing-requests-list');
  const friendsListEl = $('friends-list');
  const noFriendsMsg = $('no-friends-msg');

  function ensureFriendsSocket() {
    if (friendsWs && (friendsWs.readyState === WebSocket.OPEN || friendsWs.readyState === WebSocket.CONNECTING)) return;
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    friendsWs = new WebSocket(`${proto}//${location.host}`);
    friendsWs.addEventListener('open', () => {
      friendsWs.send(JSON.stringify({ type: 'identify', userId: deviceId, username: myUsername || undefined }));
    });
    friendsWs.addEventListener('message', e => handleFriendsMessage(JSON.parse(e.data)));
  }

  function handleFriendsMessage(msg) {
    switch (msg.type) {
      case 'identified': {
        if (msg.username) {
          myUsername = msg.username;
          try { localStorage.setItem('dp_username', myUsername); } catch (_) {}
          friendsClaimSection.classList.add('hidden');
          friendsMainSection.classList.remove('hidden');
          myUsernameDisplay.textContent = myUsername;
          renameRow.classList.add('hidden');
          renameError.textContent = '';
          inputRenameUsername.value = '';
        } else {
          friendsClaimSection.classList.remove('hidden');
          friendsMainSection.classList.add('hidden');
        }
        renderFriendsLists(msg.friends || [], msg.incomingRequests || [], msg.outgoingRequests || []);
        break;
      }
      case 'usernameTaken': {
        claimError.textContent = msg.message;
        renameError.textContent = msg.message;
        break;
      }
      case 'friendsUpdate': {
        renderFriendsLists(msg.friends || [], msg.incomingRequests || [], msg.outgoingRequests || []);
        break;
      }
      case 'friendRequestError': {
        friendRequestError.textContent = msg.message;
        break;
      }
      case 'gameInvite': {
        const wantsToJoin = confirm(`${msg.fromUsername} invited you to their game! Join room ${msg.roomCode} now?`);
        if (wantsToJoin && !screenRoom.classList.contains('active')) {
          inputCode.value = msg.roomCode;
          closeFriendsModal();
          if (!inputName.value.trim() && myUsername) inputName.value = myUsername;
        } else if (wantsToJoin) {
          alert(`You're already in a game. Leave your current room, then use room code ${msg.roomCode} to join.`);
        }
        break;
      }
    }
  }

  function renderFriendsLists(friends, incoming, outgoing) {
    lastFriendsSnapshot = { friends, incoming, outgoing };
    incomingRequestsSection.classList.toggle('hidden', incoming.length === 0);
    incomingRequestsList.innerHTML = '';
    incoming.forEach(req => {
      const row = document.createElement('div');
      row.className = 'friend-row';
      row.innerHTML = `<span class="friend-name">${escapeHtml(req.fromUsername)}</span>`;
      const actions = document.createElement('div');
      actions.className = 'friend-actions';
      const acceptBtn = document.createElement('button');
      acceptBtn.className = 'btn-accept';
      acceptBtn.textContent = 'Accept';
      acceptBtn.addEventListener('click', () => friendsWs.send(JSON.stringify({ type: 'respondFriendRequest', fromUserId: req.fromUserId, accept: true })));
      const declineBtn = document.createElement('button');
      declineBtn.className = 'btn-danger';
      declineBtn.textContent = 'Decline';
      declineBtn.addEventListener('click', () => friendsWs.send(JSON.stringify({ type: 'respondFriendRequest', fromUserId: req.fromUserId, accept: false })));
      actions.appendChild(acceptBtn);
      actions.appendChild(declineBtn);
      row.appendChild(actions);
      incomingRequestsList.appendChild(row);
    });

    outgoingRequestsSection.classList.toggle('hidden', outgoing.length === 0);
    outgoingRequestsList.innerHTML = '';
    outgoing.forEach(req => {
      const row = document.createElement('div');
      row.className = 'friend-row';
      row.innerHTML = `<span class="friend-name">${escapeHtml(req.toUsername)}</span><span class="hint">Pending…</span>`;
      outgoingRequestsList.appendChild(row);
    });

    noFriendsMsg.classList.toggle('hidden', friends.length > 0);
    friendsListEl.innerHTML = '';
    friends.forEach(f => {
      const row = document.createElement('div');
      row.className = 'friend-row';
      const dot = document.createElement('span');
      dot.className = 'friend-dot' + (f.online ? ' online' : '');
      const name = document.createElement('span');
      name.className = 'friend-name';
      name.textContent = f.username;
      row.appendChild(dot);
      row.appendChild(name);

      const actions = document.createElement('div');
      actions.className = 'friend-actions';
      if (roomCode && screenRoom.classList.contains('active')) {
        const inviteBtn = document.createElement('button');
        inviteBtn.textContent = 'Invite';
        inviteBtn.disabled = !f.online;
        inviteBtn.addEventListener('click', () => friendsWs.send(JSON.stringify({ type: 'inviteFriend', friendUserId: f.userId })));
        actions.appendChild(inviteBtn);
      }
      const unfriendBtn = document.createElement('button');
      unfriendBtn.className = 'btn-danger';
      unfriendBtn.textContent = 'Unfriend';
      unfriendBtn.addEventListener('click', () => {
        if (confirm(`Unfriend ${f.username}?`)) friendsWs.send(JSON.stringify({ type: 'unfriend', friendUserId: f.userId }));
      });
      actions.appendChild(unfriendBtn);
      row.appendChild(actions);
      friendsListEl.appendChild(row);
    });
  }

  function openFriendsModal() {
    friendsModal.classList.remove('hidden');
    claimError.textContent = '';
    friendRequestError.textContent = '';
    if (myUsername) {
      renderFriendsLists(lastFriendsSnapshot.friends, lastFriendsSnapshot.incoming, lastFriendsSnapshot.outgoing);
    }
    ensureFriendsSocket();
  }
  function closeFriendsModal() {
    friendsModal.classList.add('hidden');
  }

  $('btn-open-friends-join').addEventListener('click', openFriendsModal);
  $('btn-open-friends-room').addEventListener('click', openFriendsModal);
  btnCloseFriends.addEventListener('click', closeFriendsModal);
  friendsModal.addEventListener('click', e => { if (e.target === friendsModal) closeFriendsModal(); });

  btnClaimUsername.addEventListener('click', () => {
    const name = inputClaimUsername.value.trim();
    if (!name) { claimError.textContent = 'Please enter a username.'; return; }
    claimError.textContent = '';
    ensureFriendsSocket();
    if (friendsWs.readyState === WebSocket.OPEN) {
      friendsWs.send(JSON.stringify({ type: 'claimUsername', username: name }));
    } else {
      friendsWs.addEventListener('open', () => {
        friendsWs.send(JSON.stringify({ type: 'claimUsername', username: name }));
      }, { once: true });
    }
  });

  btnRenameUsername.addEventListener('click', () => {
    renameRow.classList.toggle('hidden');
    renameError.textContent = '';
    if (!renameRow.classList.contains('hidden')) {
      inputRenameUsername.value = myUsername || '';
      inputRenameUsername.focus();
    }
  });

  btnConfirmRename.addEventListener('click', () => {
    const name = inputRenameUsername.value.trim();
    if (!name) { renameError.textContent = 'Please enter a username.'; return; }
    renameError.textContent = '';
    friendsWs.send(JSON.stringify({ type: 'claimUsername', username: name }));
  });

  btnSendFriendRequest.addEventListener('click', () => {
    const toUsername = inputAddFriend.value.trim();
    if (!toUsername) return;
    friendRequestError.textContent = '';
    friendsWs.send(JSON.stringify({ type: 'sendFriendRequest', toUsername }));
    inputAddFriend.value = '';
  });

  // ---------- init ----------
  initCanvas();
  initLobbyDoodle();
})();
