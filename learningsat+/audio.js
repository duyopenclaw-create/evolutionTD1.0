// ============================================================
//  LearningSAT+ Audio Engine
// ============================================================
const Audio = (() => {
  let ctx = null;
  let musicGain = null;
  let musicOsc = null;
  let musicOsc2 = null;
  let musicPlaying = false;

  function getCtx() {
    if (!ctx) {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      musicGain = ctx.createGain();
      musicGain.gain.value = 0.08;
      musicGain.connect(ctx.destination);
    }
    return ctx;
  }

  function playTone(freq, type, duration, vol, delay=0) {
    try {
      const c = getCtx();
      const osc = c.createOscillator();
      const gain = c.createGain();
      osc.connect(gain);
      gain.connect(c.destination);
      osc.type = type;
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(vol, c.currentTime + delay);
      gain.gain.exponentialRampToValueAtTime(0.001, c.currentTime + delay + duration);
      osc.start(c.currentTime + delay);
      osc.stop(c.currentTime + delay + duration);
    } catch(e) {}
  }

  function correct() {
    playTone(523, 'sine', 0.15, 0.4);
    playTone(659, 'sine', 0.15, 0.4, 0.12);
    playTone(784, 'sine', 0.25, 0.4, 0.24);
  }

  function wrong() {
    playTone(220, 'sawtooth', 0.15, 0.3);
    playTone(196, 'sawtooth', 0.2, 0.3, 0.1);
  }

  function tick() {
    playTone(800, 'square', 0.05, 0.15);
  }

  function urgentTick() {
    playTone(1000, 'square', 0.06, 0.25);
  }

  function fanfare() {
    const notes = [523, 659, 784, 1047, 784, 1047, 1175, 1047];
    notes.forEach((f, i) => playTone(f, 'sine', 0.3, 0.5, i * 0.12));
  }

  function sadEnd() {
    playTone(392, 'sine', 0.2, 0.4);
    playTone(349, 'sine', 0.2, 0.4, 0.2);
    playTone(294, 'sine', 0.4, 0.4, 0.4);
  }

  function click() {
    playTone(660, 'sine', 0.06, 0.2);
  }

  function wordReveal() {
    playTone(440, 'sine', 0.1, 0.3);
    playTone(550, 'sine', 0.12, 0.3, 0.08);
  }

  // Background music: gentle arpeggio
  const MELODY = [261, 329, 392, 523, 392, 329, 261, 329, 392, 440, 392, 329, 294, 370, 440, 587];
  let melStep = 0;
  let melTimer = null;

  function startMusic() {
    if (musicPlaying) return;
    musicPlaying = true;
    const c = getCtx();
    c.resume().then(() => {
      playMelStep();
    });
  }

  function playMelStep() {
    if (!musicPlaying) return;
    try {
      const c = getCtx();
      const freq = MELODY[melStep % MELODY.length];
      const osc = c.createOscillator();
      const gain = c.createGain();
      osc.connect(gain);
      gain.connect(musicGain);
      osc.type = 'triangle';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.6, c.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, c.currentTime + 0.45);
      osc.start(c.currentTime);
      osc.stop(c.currentTime + 0.45);
      melStep++;
    } catch(e) {}
    melTimer = setTimeout(playMelStep, 480);
  }

  function stopMusic() {
    musicPlaying = false;
    if (melTimer) clearTimeout(melTimer);
    melTimer = null;
  }

  function setMusicVolume(v) {
    try { if (musicGain) musicGain.gain.value = v; } catch(e) {}
  }

  // Speech synthesis for spelling
  function speakWord(word) {
    if (!window.speechSynthesis) return;
    window.speechSynthesis.cancel();
    const utter = new SpeechSynthesisUtterance(word);
    utter.rate = 0.85;
    utter.pitch = 1.0;
    window.speechSynthesis.speak(utter);
  }

  return { correct, wrong, tick, urgentTick, fanfare, sadEnd, click, wordReveal, startMusic, stopMusic, setMusicVolume, speakWord };
})();
