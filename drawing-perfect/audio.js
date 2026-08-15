const GameAudio = (() => {
  let ctx = null;
  let enabled = true;
  let musicTimer = null;
  let sfxVolume = 1;
  let musicVolume = 1;
  let activeMusicNotes = []; // { osc1, osc2, gain } for notes currently scheduled/sounding

  function ensureCtx() {
    if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }

  // a soft plucked-piano-ish tone: sine fundamental + quiet triangle overtone, quick attack,
  // exponential decay, gently low-passed so the overtone rounds out instead of sounding thin/buzzy
  function pianoNote(freq, startTime, duration, peakGain, track = false) {
    if (!enabled) return;
    const ac = ensureCtx();
    const osc1 = ac.createOscillator();
    const osc2 = ac.createOscillator();
    const overtoneGain = ac.createGain();
    const gain = ac.createGain();
    const filter = ac.createBiquadFilter();

    osc1.type = 'sine';
    osc1.frequency.value = freq;
    osc2.type = 'triangle';
    osc2.frequency.value = freq * 2;
    overtoneGain.gain.value = 0.18;

    filter.type = 'lowpass';
    filter.frequency.value = 3200;
    filter.Q.value = 0.7;

    osc2.connect(overtoneGain);
    overtoneGain.connect(gain);
    osc1.connect(gain);
    gain.connect(filter);
    filter.connect(ac.destination);

    gain.gain.setValueAtTime(0.0001, startTime);
    gain.gain.linearRampToValueAtTime(peakGain, startTime + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

    osc1.start(startTime);
    osc2.start(startTime);
    osc1.stop(startTime + duration + 0.05);
    osc2.stop(startTime + duration + 0.05);

    if (track) {
      const entry = { osc1, osc2, gain };
      activeMusicNotes.push(entry);
      osc1.onended = () => {
        const idx = activeMusicNotes.indexOf(entry);
        if (idx !== -1) activeMusicNotes.splice(idx, 1);
      };
    }
  }

  // a soft sustained bass tone underneath the melody — warm sine through a low-pass,
  // slow attack/release so it pads the harmony instead of poking out
  function bassNote(freq, startTime, duration, peakGain) {
    if (!enabled) return;
    const ac = ensureCtx();
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    const filter = ac.createBiquadFilter();

    osc.type = 'sine';
    osc.frequency.value = freq;
    filter.type = 'lowpass';
    filter.frequency.value = 900;

    osc.connect(filter);
    filter.connect(gain);
    gain.connect(ac.destination);

    gain.gain.setValueAtTime(0.0001, startTime);
    gain.gain.linearRampToValueAtTime(peakGain, startTime + 0.25);
    gain.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

    osc.start(startTime);
    osc.stop(startTime + duration + 0.1);

    const entry = { osc1: osc, osc2: osc, gain };
    activeMusicNotes.push(entry);
    osc.onended = () => {
      const idx = activeMusicNotes.indexOf(entry);
      if (idx !== -1) activeMusicNotes.splice(idx, 1);
    };
  }

  // immediately silence every currently-scheduled/sounding music note instead of
  // letting up to a full loop's worth (~8s) of already-scheduled notes play out
  function killActiveMusicNotes() {
    if (!ctx) { activeMusicNotes = []; return; }
    const now = ctx.currentTime;
    activeMusicNotes.forEach(({ osc1, osc2, gain }) => {
      try {
        gain.gain.cancelScheduledValues(now);
        gain.gain.setValueAtTime(gain.gain.value, now);
        gain.gain.linearRampToValueAtTime(0.0001, now + 0.05);
        osc1.stop(now + 0.06);
        osc2.stop(now + 0.06);
      } catch (_) { /* already stopped */ }
    });
    activeMusicNotes = [];
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

  // gentle looping menu music (light piano melody + soft bass harmony).
  // Two alternating phrases over a I-vi-IV-V / vi-IV-I-V progression so it doesn't
  // feel like the exact same 8.8s loop forever.
  const NOTE_LEN = 0.55;
  const NOTES_PER_CHORD = 4;
  const PHRASES = [
    {
      melody: [
        523.25, 659.25, 587.33, 493.88, 523.25, 392.0, 440.0, 523.25,
        659.25, 783.99, 698.46, 659.25, 587.33, 523.25, 493.88, 440.0,
      ],
      bass: [130.81, 220.0, 174.61, 196.0], // C3 - A3 - F3 - G3  (I - vi - IV - V)
    },
    {
      melody: [
        440.0, 523.25, 659.25, 587.33, 523.25, 440.0, 392.0, 440.0,
        493.88, 587.33, 698.46, 659.25, 587.33, 493.88, 440.0, 392.0,
      ],
      bass: [220.0, 174.61, 130.81, 196.0], // A3 - F3 - C3 - G3  (vi - IV - I - V)
    },
  ];
  let phraseIndex = 0;

  function scheduleMenuLoop() {
    if (!enabled) { musicTimer = null; return; }
    const ac = ensureCtx();
    const phrase = PHRASES[phraseIndex % PHRASES.length];
    phraseIndex++;
    let t = ac.currentTime + 0.1;
    phrase.melody.forEach((freq, i) => {
      if (musicVolume > 0) {
        pianoNote(freq, t, NOTE_LEN * 0.9, 0.06 * musicVolume, true);
        if (i % NOTES_PER_CHORD === 0) {
          const bassFreq = phrase.bass[i / NOTES_PER_CHORD];
          bassNote(bassFreq, t, NOTE_LEN * NOTES_PER_CHORD * 0.95, 0.045 * musicVolume);
        }
      }
      t += NOTE_LEN;
    });
    musicTimer = setTimeout(scheduleMenuLoop, phrase.melody.length * NOTE_LEN * 1000 - 60);
  }

  function startMenuMusic() {
    if (musicTimer || !enabled) return;
    ensureCtx();
    scheduleMenuLoop();
  }

  function stopMenuMusic() {
    if (musicTimer) clearTimeout(musicTimer);
    musicTimer = null;
    killActiveMusicNotes();
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
