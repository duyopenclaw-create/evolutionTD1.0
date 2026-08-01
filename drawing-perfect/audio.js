const GameAudio = (() => {
  let ctx = null;
  let enabled = true;
  let musicTimer = null;
  let sfxVolume = 1;
  let musicVolume = 1;

  function ensureCtx() {
    if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }

  // a soft plucked-piano-ish tone: sine fundamental + quiet triangle overtone, quick attack, exponential decay
  function pianoNote(freq, startTime, duration, peakGain) {
    if (!enabled) return;
    const ac = ensureCtx();
    const osc1 = ac.createOscillator();
    const osc2 = ac.createOscillator();
    const overtoneGain = ac.createGain();
    const gain = ac.createGain();

    osc1.type = 'sine';
    osc1.frequency.value = freq;
    osc2.type = 'triangle';
    osc2.frequency.value = freq * 2;
    overtoneGain.gain.value = 0.18;

    osc2.connect(overtoneGain);
    overtoneGain.connect(gain);
    osc1.connect(gain);
    gain.connect(ac.destination);

    gain.gain.setValueAtTime(0.0001, startTime);
    gain.gain.linearRampToValueAtTime(peakGain, startTime + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

    osc1.start(startTime);
    osc2.start(startTime);
    osc1.stop(startTime + duration + 0.05);
    osc2.stop(startTime + duration + 0.05);
  }

  function sfx(freqs, peak = 0.15, gap = 0.09, dur = 0.16) {
    if (!enabled || sfxVolume <= 0) return;
    const ac = ensureCtx();
    freqs.forEach((f, i) => pianoNote(f, ac.currentTime + i * gap, dur, peak * sfxVolume));
  }

  const sfxClick = () => sfx([659.25], 0.1, 0, 0.1);
  const sfxPick = () => sfx([880], 0.14, 0, 0.15);
  const sfxSubmit = () => sfx([523.25, 659.25], 0.15, 0.08, 0.2);
  const sfxVote = () => sfx([784], 0.15, 0, 0.15);
  const sfxJoinLeave = () => sfx([440], 0.1, 0, 0.12);
  const sfxChat = () => sfx([1046.5], 0.05, 0, 0.08);
  const sfxWin = () => sfx([523.25, 659.25, 783.99, 1046.5], 0.18, 0.12, 0.4);

  // gentle looping menu melody (light piano)
  const MELODY = [
    523.25, 659.25, 587.33, 493.88, 523.25, 392.0, 440.0, 523.25,
    659.25, 783.99, 698.46, 659.25, 587.33, 523.25, 493.88, 440.0,
  ];
  const NOTE_LEN = 0.55;

  function scheduleMenuLoop() {
    if (!enabled) { musicTimer = null; return; }
    const ac = ensureCtx();
    let t = ac.currentTime + 0.1;
    MELODY.forEach(freq => {
      if (musicVolume > 0) pianoNote(freq, t, NOTE_LEN * 0.9, 0.06 * musicVolume);
      t += NOTE_LEN;
    });
    musicTimer = setTimeout(scheduleMenuLoop, MELODY.length * NOTE_LEN * 1000 - 60);
  }

  function startMenuMusic() {
    if (musicTimer || !enabled) return;
    ensureCtx();
    scheduleMenuLoop();
  }

  function stopMenuMusic() {
    if (musicTimer) clearTimeout(musicTimer);
    musicTimer = null;
  }

  function setEnabled(v) {
    enabled = v;
    if (!enabled) stopMenuMusic();
  }

  function isEnabled() { return enabled; }
  function isMusicPlaying() { return musicTimer !== null; }

  function setSfxVolume(v) { sfxVolume = Math.max(0, Math.min(1, v)); }
  function setMusicVolume(v) { musicVolume = Math.max(0, Math.min(1, v)); }
  function getSfxVolume() { return sfxVolume; }
  function getMusicVolume() { return musicVolume; }

  return {
    ensureCtx, sfxClick, sfxPick, sfxSubmit, sfxVote, sfxJoinLeave, sfxChat, sfxWin,
    startMenuMusic, stopMenuMusic, setEnabled, isEnabled, isMusicPlaying,
    setSfxVolume, setMusicVolume, getSfxVolume, getMusicVolume,
  };
})();
