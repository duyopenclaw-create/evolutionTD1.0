// ============================================================
//  LearningSAT+ App Logic
// ============================================================
const App = (() => {
  let state = {};

  function resetState() {
    state = {
      grade: null,
      subject: null,
      mode: null,
      timeLimit: 1800,
      wordTimeLimit: 30,
      questions: [],
      currentQ: 0,
      score: 0,
      timer: null,
      wordTimer: null,
      timeLeft: 0,
      wordTimeLeft: 0,
      passage: null,
      passages: null,
      readingPhase: 'reading',
      passageIdx: 0,
      questionOffset: 0,
      writingStart: null,
      spellingWords: [],
      spellingIdx: 0,
      spellingCorrect: 0,
      pendingMode: null,
      pendingTime: null,
      autosavedScore: 0,
      autosavedTotal: 0,
      starsAwarded: false,
    };
  }

  resetState();

  // ─── Screen Management ───────────────────────────────────
  function showScreen(id) {
    document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
    const el = document.getElementById(id);
    if (el) el.classList.add('active');
  }

  function showWelcome() {
    Audio.stopMusic();
    resetState();
    createStars();
    showScreen('screen-welcome');
    Audio.startMusic();
    updateStarDisplays();
    renderGreeting();
    // Prompt for name on very first visit
    if (!getName()) setTimeout(() => promptName(false), 800);
  }

  function showGradeSelect() {
    showScreen('screen-grade');
    const grid = document.getElementById('grade-grid');
    grid.innerHTML = '';
    const grades = ['K','1','2','3','4','5','6','7','8','9','10','11','12','SAT'];
    const labels = { K:'Kindergarten', SAT:'SAT Prep' };
    grades.forEach(g => {
      const btn = document.createElement('button');
      btn.className = 'grade-btn';
      btn.innerHTML = `<span class="grade-num">${g}</span><span class="grade-label">${labels[g] || `Grade ${g}`}</span>`;
      btn.onclick = () => { Audio.click(); selectGrade(g); };
      grid.appendChild(btn);
    });
  }

  function selectGrade(grade) {
    state.grade = grade;
    showSubjectSelect();
  }

  function showSubjectSelect() {
    stopAllTimers();
    showScreen('screen-subject');
    const badge = document.getElementById('grade-badge-sub');
    badge.textContent = state.grade === 'K' ? 'Kindergarten' : state.grade === 'SAT' ? 'SAT Prep' : `Grade ${state.grade}`;
  }

  function selectSubject(subject) {
    Audio.click();
    state.subject = subject;
    showModeSelect();
  }

  function showModeSelect() {
    showScreen('screen-mode');
    const names = { math:'Math', reading:'Reading', writing:'Writing', spelling:'Spelling', science:'Science' };
    document.getElementById('mode-title').textContent = names[state.subject] || state.subject;
    document.getElementById('grade-badge-mode').textContent =
      state.grade === 'K' ? 'Kindergarten' : state.grade === 'SAT' ? 'SAT Prep' : `Grade ${state.grade}`;

    const pDesc = document.getElementById('practice-mode-desc');
    const tDesc = document.getElementById('test-mode-desc');
    const tGrid = document.getElementById('test-time-grid');
    const tLabel = document.getElementById('test-time-label');
    const tSection = document.getElementById('test-time-section');

    switch(state.subject) {
      case 'math':
        pDesc.textContent = '15 questions · choose your time limit below';
        tDesc.textContent = '20 harder questions · fresh timer';
        tLabel.textContent = 'Choose time limit:';
        tGrid.innerHTML = buildTimeButtons('test', [1800,1200,720,300], ['30 min','20 min','12 min','5 min']);
        tSection.style.display = 'block';
        break;
      case 'reading':
        pDesc.textContent = '1 story + 5 questions · choose your time limit below';
        tDesc.textContent = '2 stories + 12 questions · choose time limit:';
        tLabel.textContent = 'Choose time limit:';
        tGrid.innerHTML = buildTimeButtons('test', [1800,1200,720,300], ['30 min','20 min','12 min','5 min']);
        tSection.style.display = 'block';
        break;
      case 'writing':
        pDesc.textContent = 'Read a story and write a summary or opinion essay · choose your time limit below';
        tDesc.textContent = 'New writing prompt · choose time limit:';
        tLabel.textContent = 'Choose time limit:';
        tGrid.innerHTML = buildTimeButtons('test', [1800,1200,720,300], ['30 min','20 min','12 min','5 min']);
        tSection.style.display = 'block';
        break;
      case 'spelling':
        pDesc.textContent = '8 words · hear the word, type to spell · choose session time below';
        tDesc.textContent = '12 words · per-word time limit:';
        tLabel.textContent = 'Time per word:';
        tGrid.innerHTML = buildTimeButtons('test', [30,20,10], ['30 sec','20 sec','10 sec'], true);
        tSection.style.display = 'block';
        break;
      case 'science':
        pDesc.textContent = '8 questions · choose your time limit below';
        tDesc.textContent = '12 questions · choose time limit:';
        tLabel.textContent = 'Choose time limit:';
        tGrid.innerHTML = buildTimeButtons('test', [1800,1200,720,300], ['30 min','20 min','12 min','5 min']);
        tSection.style.display = 'block';
        break;
    }
  }

  function buildTimeButtons(mode, times, labels, isSpelling=false) {
    return times.map((t, i) =>
      `<button class="time-btn" onclick="App.startSession('${mode}', ${t})">${labels[i]}</button>`
    ).join('');
  }

  // ─── Session Start ────────────────────────────────────────
  function startSession(mode, time) {
    Audio.click();
    state.mode = mode;

    if (state.subject === 'spelling' && mode === 'test') {
      state.wordTimeLimit = time;
      startSpelling();
      startAutosave();
      return;
    }

    state.timeLimit = time;
    state.timeLeft = time;
    startAutosave();

    switch(state.subject) {
      case 'math':    startMath();    break;
      case 'reading': startReading(); break;
      case 'writing': startWriting(); break;
      case 'spelling':startSpelling();break;
      case 'science': startScience(); break;
    }
  }

  // ─── MATH ────────────────────────────────────────────────
  function startMath() {
    const count = state.mode === 'test' ? 20 : 15;
    const isTest = state.mode === 'test';
    state.questions = Array.from({length: count}, () => generateMathProblem(state.grade, isTest));
    state.currentQ = 0;
    state.score = 0;
    showScreen('screen-play');
    renderMathQ();
    startTimer();
  }

  function renderMathQ() {
    const q = state.questions[state.currentQ];
    const total = state.questions.length;
    updatePlayHeader(state.currentQ + 1, total);
    const body = document.getElementById('play-body');
    body.innerHTML = `
      <div class="question-card">
        <div class="subject-tag math-tag">➕ Math</div>
        <div class="question-text">${q.question}</div>
        <div class="choices-grid">
          ${q.choices.map(c => `<button class="choice-btn" onclick="App.answerMath('${c}')">${c}</button>`).join('')}
        </div>
      </div>`;
  }

  function answerMath(chosen) {
    const q = state.questions[state.currentQ];
    disableChoices();
    if (chosen === q.answer) {
      state.score++;
      Audio.correct();
      highlightChoice(chosen, 'correct');
      showFlash('✓ Correct!', 'flash-correct');
    } else {
      Audio.wrong();
      highlightChoice(chosen, 'wrong');
      highlightChoice(q.answer, 'correct');
      showFlash(`✗ Answer: ${q.answer}`, 'flash-wrong');
    }
    setTimeout(nextQ, 1100);
  }

  // ─── SCIENCE ─────────────────────────────────────────────
  function startScience() {
    const count = state.mode === 'test' ? 12 : 8;
    const pool = getScienceData(state.grade);
    state.questions = pickRandom(pool, count);
    state.currentQ = 0;
    state.score = 0;
    showScreen('screen-play');
    renderScienceQ();
    startTimer();
  }

  function renderScienceQ() {
    const q = state.questions[state.currentQ];
    const total = state.questions.length;
    updatePlayHeader(state.currentQ + 1, total);
    const body = document.getElementById('play-body');
    body.innerHTML = `
      <div class="question-card">
        <div class="subject-tag science-tag">🔬 Science</div>
        <div class="question-text">${q.q}</div>
        <div class="choices-grid">
          ${q.choices.map(c => `<button class="choice-btn" onclick="App.answerScience('${escQ(c)}')">${c}</button>`).join('')}
        </div>
      </div>`;
  }

  function answerScience(chosen) {
    const q = state.questions[state.currentQ];
    disableChoices();
    if (chosen === q.answer) {
      state.score++;
      Audio.correct();
      highlightChoice(chosen, 'correct');
      showFlash('✓ Correct!', 'flash-correct');
    } else {
      Audio.wrong();
      highlightChoice(chosen, 'wrong');
      highlightChoice(q.answer, 'correct');
      showFlash(`✗ ${q.answer}`, 'flash-wrong');
    }
    setTimeout(nextQ, 1200);
  }

  // ─── READING ─────────────────────────────────────────────
  function startReading() {
    const passages = getReadingData(state.grade);
    state.currentQ = 0;
    state.score = 0;

    if (state.mode === 'practice') {
      state.passage = passages[Math.floor(Math.random() * passages.length)];
      state.passages = [state.passage];
      state.passageIdx = 0;
      state.questionOffset = 0;
      state.readingPhase = 'reading';
      showScreen('screen-play');
      renderPassage();
      startTimer();
    } else {
      // Test: 2 passages, 6 questions each (12 total)
      const picked = pickRandom(passages, Math.min(2, passages.length));
      state.passages = picked;
      state.passageIdx = 0;
      state.questionOffset = 0;
      state.readingPhase = 'reading';
      showScreen('screen-play');
      renderPassage();
      startTimer();
    }
  }

  function renderPassage() {
    const p = state.passages[state.passageIdx];
    const isTest = state.mode === 'test';
    const passageLabel = isTest ? ` (Story ${state.passageIdx + 1} of ${state.passages.length})` : '';
    document.getElementById('q-label').textContent = `Reading${passageLabel} — Answer questions when ready`;
    document.getElementById('progress-fill').style.width = '0%';
    const body = document.getElementById('play-body');
    body.innerHTML = `
      <div class="passage-card">
        <div class="subject-tag reading-tag">📖 Reading${passageLabel}</div>
        <h2 class="passage-title">${p.title}</h2>
        <div class="passage-text">${p.passage.replace(/\n/g,'<br><br>')}</div>
        <button class="btn-primary mt20" onclick="App.startReadingQuestions()">Answer Questions →</button>
      </div>`;
  }

  function startReadingQuestions() {
    Audio.click();
    state.readingPhase = 'questions';
    const p = state.passages[state.passageIdx];
    // Practice: 5 questions; Test: up to 6 questions per passage
    const qCount = state.mode === 'practice' ? 5 : 6;
    state.currentQ = state.questionOffset;
    state.passageQs = p.questions.slice(0, qCount);
    state.passageQIdx = 0;
    renderReadingQ();
  }

  function renderReadingQ() {
    const p = state.passages[state.passageIdx];
    const qCount = state.mode === 'practice' ? 5 : 6;
    const totalQ = state.mode === 'test' ? state.passages.length * 6 : 5;
    const globalQ = state.passageIdx * qCount + state.passageQIdx;
    updatePlayHeader(globalQ + 1, totalQ);
    const q = state.passageQs[state.passageQIdx];
    const body = document.getElementById('play-body');
    body.innerHTML = `
      <div class="question-card">
        <div class="subject-tag reading-tag">📖 ${p.title}</div>
        <div class="question-text">${q.q}</div>
        <div class="choices-grid choices-col">
          ${q.choices.map(c => `<button class="choice-btn" onclick="App.answerReading('${escQ(c)}')">${c}</button>`).join('')}
        </div>
      </div>`;
  }

  function answerReading(chosen) {
    const q = state.passageQs[state.passageQIdx];
    disableChoices();
    if (chosen === q.answer) {
      state.score++;
      Audio.correct();
      highlightChoice(chosen, 'correct');
      showFlash('✓ Correct!', 'flash-correct');
    } else {
      Audio.wrong();
      highlightChoice(chosen, 'wrong');
      highlightChoice(q.answer, 'correct');
      showFlash(`✗ ${q.answer}`, 'flash-wrong');
    }
    setTimeout(() => {
      state.passageQIdx++;
      const qCount = state.mode === 'practice' ? 5 : 6;
      if (state.passageQIdx >= qCount || state.passageQIdx >= state.passageQs.length) {
        // Done with this passage's questions
        state.passageIdx++;
        if (state.mode === 'test' && state.passageIdx < state.passages.length) {
          // Show next passage
          state.readingPhase = 'reading';
          state.passageQIdx = 0;
          renderPassage();
        } else {
          // All done
          stopTimer();
          const total = state.mode === 'practice' ? 5 : Math.min(state.passages.length * 6, 12);
          showResults(state.score, total, true);
        }
      } else {
        renderReadingQ();
      }
    }, 1200);
  }

  // ─── WRITING ─────────────────────────────────────────────
  function startWriting() {
    const prompts = getWritingPrompts(state.grade);
    const prompt = prompts[Math.floor(Math.random() * prompts.length)];
    state.currentPrompt = prompt;
    state.writingStart = Date.now();
    showScreen('screen-writing');
    document.getElementById('writing-mode-label').textContent =
      state.mode === 'test' ? 'Writing Test' : 'Writing Practice';
    startWritingTimer();
    const body = document.getElementById('writing-body');

    let storyHtml = '';
    if (prompt.story) {
      storyHtml = `<div class="story-box"><h3>📚 Read This Story:</h3><p>${prompt.story}</p></div>`;
    }

    const typeLabel = prompt.type === 'summary' ? 'Write a Summary' : 'Write Your Opinion Essay';
    body.innerHTML = `
      ${storyHtml}
      <div class="writing-prompt-box">
        <div class="writing-prompt-icon">${prompt.type === 'summary' ? '📝' : '💬'}</div>
        <h3>${typeLabel}</h3>
        <p class="prompt-text">${prompt.prompt}</p>
      </div>
      <div class="writing-area-wrap">
        <textarea id="writing-area" class="writing-area" placeholder="Start writing here..."></textarea>
        <div class="word-count-row">
          <span class="word-count" id="word-count">0 words</span>
          <button class="btn-primary" onclick="App.submitWriting()">Submit ✓</button>
        </div>
      </div>`;

    const ta = document.getElementById('writing-area');
    ta.addEventListener('input', () => {
      const words = ta.value.trim().split(/\s+/).filter(w => w.length > 0).length;
      document.getElementById('word-count').textContent = `${words} word${words !== 1 ? 's' : ''}`;
    });
    ta.focus();
  }

  // ─── API Key Management ───────────────────────────────────
  const API_KEY_STORE = 'lsp_anthropic_key';
  function getApiKey() { try { return localStorage.getItem(API_KEY_STORE) || ''; } catch(e){ return ''; } }
  function saveApiKey(k) { try { localStorage.setItem(API_KEY_STORE, k.trim()); } catch(e){} }

  function showApiKeyModal(onSave) {
    const modal = document.getElementById('modal');
    document.getElementById('modal-title').textContent = '🔑 Anthropic API Key';
    document.getElementById('modal-msg').innerHTML =
      `AI writing grading needs your Anthropic API key.<br>
       <input id="api-key-input" type="password" placeholder="sk-ant-..." style="
         width:100%;margin-top:12px;padding:10px 14px;border-radius:8px;border:2px solid rgba(255,255,255,0.15);
         background:#16213e;color:#fff;font-size:0.95rem;font-family:monospace;
       " value="${getApiKey()}">
       <div style="font-size:0.75rem;color:#a7a9be;margin-top:8px;">
         Stored locally only. Get one at console.anthropic.com
       </div>`;
    const ok = document.getElementById('modal-ok');
    ok.textContent = 'Save & Grade';
    ok.onclick = () => {
      const key = (document.getElementById('api-key-input') || {}).value || '';
      if (key.trim()) { saveApiKey(key); closeModal(); onSave(); }
      else { closeModal(); onSave(); }
    };
    const cancel = document.getElementById('modal-cancel');
    cancel.textContent = 'Skip (word count only)';
    cancel.onclick = () => { closeModal(); onSave(); };
    modal.classList.remove('hidden');
    setTimeout(() => { const inp = document.getElementById('api-key-input'); if(inp) inp.focus(); }, 100);
  }

  async function evaluateWritingWithAI(grade, prompt, text) {
    const apiKey = getApiKey();
    if (!apiKey) return null;
    const words = text.trim().split(/\s+/).filter(w=>w.length>0).length;
    const gradeLabel_ = grade==='K'?'Kindergarten':grade==='SAT'?'SAT-prep':`Grade ${grade}`;
    const evalPrompt = `You are grading a ${gradeLabel_} student's writing response.

Writing prompt given to student:
"${prompt}"

Student's response (${words} words):
"${text}"

Grade honestly. If the student typed random words, nonsense, or content completely unrelated to the prompt, give a very low score (0–15).

Score on these four criteria (0–25 each):
1. Relevance — Does it actually address the prompt?
2. Content — Are ideas clear, meaningful, and supported?
3. Organization — Is there a beginning, middle, end or logical structure?
4. Language — Appropriate vocabulary, grammar, and sentence variety for ${gradeLabel_}?

Respond with ONLY a JSON object, no other text:
{"score":0-100,"stars":0-3,"title":"one or two word result label","feedback":"1-2 sentences of honest, encouraging feedback","isNonsense":true/false,"breakdown":{"relevance":0-25,"content":0-25,"organization":0-25,"language":0-25}}`;

    try {
      const res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'anthropic-dangerous-allow-browser': 'true'
        },
        body: JSON.stringify({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 300,
          messages: [{ role: 'user', content: evalPrompt }]
        })
      });
      if (!res.ok) throw new Error(res.status);
      const data = await res.json();
      const raw = data.content[0].text.trim();
      const jsonStr = raw.startsWith('{') ? raw : raw.match(/\{[\s\S]*\}/)?.[0];
      return JSON.parse(jsonStr);
    } catch(e) {
      console.warn('AI grading failed:', e.message);
      return null;
    }
  }

  async function submitWriting() {
    Audio.click();
    stopWritingTimer();
    const ta = document.getElementById('writing-area');
    const text = ta ? ta.value.trim() : '';
    const words = text.split(/\s+/).filter(w => w.length > 0).length;
    const elapsed = Math.round((Date.now() - state.writingStart) / 1000);
    const timeStr = `${Math.floor(elapsed/60)}m ${elapsed%60}s`;
    stopAutosave();
    runWritingGrade(text, words, timeStr);
  }

  async function runWritingGrade(text, words, timeStr) {
    // Show loading state on writing screen
    const body = document.getElementById('writing-body');
    if (body) {
      body.innerHTML = `
        <div class="writing-grading">
          <div class="grading-spinner"></div>
          <div class="grading-label">🤖 AI is reading your writing…</div>
          <div class="grading-sub">Checking relevance, content, and quality</div>
        </div>`;
    }

    const prompt = state.currentPrompt ? state.currentPrompt.prompt : '';
    let aiResult = null;

    if (words > 0 && getApiKey()) {
      aiResult = await evaluateWritingWithAI(state.grade, prompt, text);
    }

    let score, title, feedbackHtml;
    if (aiResult) {
      score = Math.round((aiResult.stars || 0));
      const pct = aiResult.score || 0;
      title = aiResult.title || (pct >= 80 ? 'Great Job!' : pct >= 60 ? 'Good Effort!' : pct >= 40 ? 'Getting Started' : 'Needs Work');

      if (aiResult.isNonsense) Audio.wrong();
      else if (pct >= 80) Audio.fanfare();
      else if (pct >= 50) Audio.correct();
      else Audio.wrong();

      const bd = aiResult.breakdown || {};
      feedbackHtml = `
        <div class="ai-feedback-box ${aiResult.isNonsense ? 'ai-nonsense' : ''}">
          <div class="ai-feedback-icon">${aiResult.isNonsense ? '⚠️' : '🤖'}</div>
          <div class="ai-feedback-text">${aiResult.isNonsense
            ? `<strong>Off-topic or nonsense detected.</strong> ${aiResult.feedback}`
            : aiResult.feedback}</div>
        </div>
        <div class="ai-breakdown">
          ${[['Relevance', bd.relevance||0],['Content', bd.content||0],['Organization', bd.organization||0],['Language', bd.language||0]].map(([k,v]) =>
            `<div class="ai-breakdown-row">
              <span>${k}</span>
              <div class="ai-bar"><div class="ai-bar-fill" style="width:${v*4}%;background:${v>=20?'var(--green)':v>=12?'var(--yellow)':'var(--accent2)'}"></div></div>
              <span class="ai-score-num">${v}/25</span>
            </div>`).join('')}
        </div>
        <div class="breakdown-item"><span>Total AI Score</span><strong>${aiResult.score}/100</strong></div>
        <div class="breakdown-item"><span>Words Written</span><strong>${words}</strong></div>
        <div class="breakdown-item"><span>Time Spent</span><strong>${timeStr}</strong></div>
        ${text.length > 0 ? `<div class="writing-review"><h4>Your Writing:</h4><div class="writing-review-text">${text.replace(/</g,'&lt;').replace(/\n/g,'<br>')}</div></div>` : ''}`;

      // Save with AI score
      const starScore = aiResult.stars || 0;
      if (state.grade) {
        const delta = starScore - state.autosavedScore;
        const deltaT = 3 - state.autosavedTotal;
        if (deltaT > 0) saveResult('writing', state.grade, delta, deltaT);
      }

      showScreen('screen-results');
      document.getElementById('ring-score').textContent = `${aiResult.score}%`;
      document.getElementById('ring-pct').textContent = `${words} words`;
      setRingProgress(aiResult.score);
      document.getElementById('results-title').textContent = title;
      setStars(aiResult.stars || 0, 3);
      document.getElementById('results-breakdown').innerHTML = feedbackHtml;

    } else {
      // Fallback: word-count grading
      const targets = {k2:20,'35':50,'68':100,'912':150,sat:200};
      const grp = getGradeGroup(state.grade);
      const target = targets[grp] || 50;
      score = words === 0 ? 0 : words < target*0.4 ? 1 : words < target*0.7 ? 2 : 3;
      title = ['Nothing Written','Getting Started','Good Effort!','Great Job!'][score];
      const pct = Math.round(score/3*100);

      if (score >= 3) Audio.fanfare(); else if (score > 0) Audio.correct();
      if (state.grade) {
        const delta = score - state.autosavedScore;
        const deltaT = 3 - state.autosavedTotal;
        if (deltaT > 0) saveResult('writing', state.grade, delta, deltaT);
      }

      showScreen('screen-results');
      document.getElementById('ring-score').textContent = `${words} words`;
      document.getElementById('ring-pct').textContent = `Goal: ${target}+`;
      setRingProgress(pct);
      document.getElementById('results-title').textContent = title;
      setStars(score, 3);
      document.getElementById('results-breakdown').innerHTML = `
        <div class="breakdown-item ai-no-key-note">
          <span>💡 Add an API key for AI grading</span>
          <button class="btn-set-key" onclick="App.openApiKeySettings()">Set Key</button>
        </div>
        <div class="breakdown-item"><span>Words Written</span><strong>${words} / ${target}+ goal</strong></div>
        <div class="breakdown-item"><span>Time Spent</span><strong>${timeStr}</strong></div>
        ${text.length > 0 ? `<div class="writing-review"><h4>Your Writing:</h4><div class="writing-review-text">${text.replace(/</g,'&lt;').replace(/\n/g,'<br>')}</div></div>` : ''}`;
    }
  }

  function openApiKeySettings() {
    showApiKeyModal(() => {});
  }

  // ─── SPELLING ────────────────────────────────────────────
  function startSpelling() {
    const pool = getSpellingWords(state.grade);
    const count = state.mode === 'test' ? 12 : 8;
    state.spellingWords = pickRandom(pool, count);
    state.spellingIdx = 0;
    state.spellingCorrect = 0;
    showScreen('screen-spelling-word');
    renderSpellingWord();
    if (state.mode === 'practice') {
      startSpellingPracticeTimer();
    }
  }

  function renderSpellingWord() {
    const total = state.spellingWords.length;
    const idx = state.spellingIdx;
    const pct = (idx / total) * 100;
    document.getElementById('spell-q-label').textContent = `Word ${idx + 1} / ${total}`;
    document.getElementById('spell-progress-fill').style.width = pct + '%';

    const center = document.getElementById('spelling-center');
    const isTest = state.mode === 'test';

    center.innerHTML = `
      <div class="spell-card">
        <div class="subject-tag spelling-tag">🔤 Spelling ${isTest ? 'Test' : 'Practice'}</div>
        <div class="spell-word-display">
          <div class="spell-listen-area">
            <button class="btn-listen" onclick="App.speakCurrentWord()">🔊 Hear Word</button>
            ${!isTest ? `<button class="btn-listen btn-repeat" onclick="App.speakCurrentWord()">🔁 Repeat</button>` : ''}
          </div>
          ${isTest ? `<div class="spell-timer-bar"><div class="spell-timer-fill" id="spell-timer-bar-fill"></div></div>
            <div class="spell-time-left" id="spell-time-left">${state.wordTimeLimit}s</div>` : ''}
        </div>
        <div class="spell-input-area">
          <input type="text" id="spell-input" class="spell-input"
            placeholder="Type the word here..." autocomplete="off" autocorrect="off"
            spellcheck="false" autocapitalize="off"
            onkeydown="if(event.key==='Enter') App.submitSpelling()">
          <button class="btn-primary btn-spell-submit" onclick="App.submitSpelling()">Check ✓</button>
        </div>
        ${!isTest ? `<div class="spell-hint">Hint: ${state.spellingWords[idx].length} letters</div>` : ''}
      </div>`;

    // Speak the word automatically after a short delay
    setTimeout(() => App.speakCurrentWord(), 400);

    // Focus input
    setTimeout(() => {
      const inp = document.getElementById('spell-input');
      if (inp) inp.focus();
    }, 200);

    // Start per-word timer for test
    if (isTest) {
      startWordTimer();
    }
  }

  function speakCurrentWord() {
    const word = state.spellingWords[state.spellingIdx];
    Audio.speakWord(word);
    Audio.wordReveal();
  }

  function submitSpelling() {
    const inp = document.getElementById('spell-input');
    if (!inp) return;
    const typed = inp.value.trim().toLowerCase();
    const correct = state.spellingWords[state.spellingIdx].toLowerCase();

    if (state.mode === 'test') stopWordTimer();

    if (typed === correct) {
      state.spellingCorrect++;
      Audio.correct();
      showSpellFeedback(true, correct);
    } else {
      Audio.wrong();
      showSpellFeedback(false, correct);
    }
  }

  function showSpellFeedback(isCorrect, correctWord) {
    const center = document.getElementById('spelling-center');
    center.innerHTML += `
      <div class="spell-feedback ${isCorrect ? 'spell-correct' : 'spell-wrong'}">
        ${isCorrect ? `✓ Correct! <strong>${correctWord}</strong>` : `✗ The word was: <strong>${correctWord}</strong>`}
      </div>`;

    disableEl('spell-input');
    disableEl('btn-spell-submit');

    setTimeout(() => {
      state.spellingIdx++;
      if (state.spellingIdx >= state.spellingWords.length) {
        stopSpellingTimers();
        showResults(state.spellingCorrect, state.spellingWords.length);
      } else {
        renderSpellingWord();
      }
    }, 1400);
  }

  let wordTimerInterval = null;
  function startWordTimer() {
    state.wordTimeLeft = state.wordTimeLimit;
    updateWordTimerDisplay();
    if (wordTimerInterval) clearInterval(wordTimerInterval);
    wordTimerInterval = setInterval(() => {
      state.wordTimeLeft--;
      updateWordTimerDisplay();
      if (state.wordTimeLeft <= 5) Audio.urgentTick();
      if (state.wordTimeLeft <= 0) {
        clearInterval(wordTimerInterval);
        wordTimerInterval = null;
        // Time's up for this word — mark wrong
        const correct = state.spellingWords[state.spellingIdx];
        Audio.wrong();
        showSpellFeedback(false, correct);
      }
    }, 1000);
  }

  function stopWordTimer() {
    if (wordTimerInterval) { clearInterval(wordTimerInterval); wordTimerInterval = null; }
  }

  function updateWordTimerDisplay() {
    const el = document.getElementById('spell-time-left');
    const bar = document.getElementById('spell-timer-bar-fill');
    if (el) el.textContent = `${state.wordTimeLeft}s`;
    if (bar) {
      const pct = (state.wordTimeLeft / state.wordTimeLimit) * 100;
      bar.style.width = pct + '%';
      bar.style.background = pct > 50 ? '#4ecdc4' : pct > 25 ? '#f7d060' : '#ff6b6b';
    }
  }

  let spellingPracticeTimer = null;
  function startSpellingPracticeTimer() {
    state.timeLeft = state.timeLimit;
    updateSpellHeaderTimer();
    spellingPracticeTimer = setInterval(() => {
      state.timeLeft--;
      updateSpellHeaderTimer();
      if (state.timeLeft <= 0) {
        clearInterval(spellingPracticeTimer);
        spellingPracticeTimer = null;
        Audio.sadEnd();
        stopSpellingTimers();
        showResults(state.spellingCorrect, state.spellingWords.length);
      }
    }, 1000);
  }

  function stopSpellingTimers() {
    stopWordTimer();
    if (spellingPracticeTimer) { clearInterval(spellingPracticeTimer); spellingPracticeTimer = null; }
  }

  function updateSpellHeaderTimer() {
    const el = document.getElementById('spell-timer-text');
    const box = document.getElementById('spell-timer-box');
    if (el) el.textContent = formatTime(state.timeLeft);
    if (box) {
      if (state.timeLeft <= 60) box.classList.add('timer-urgent');
      else box.classList.remove('timer-urgent');
    }
  }

  // ─── TIMER (for play screen) ──────────────────────────────
  let timerInterval = null;

  function startTimer() {
    state.timeLeft = state.timeLimit;
    updateTimerDisplay();
    if (timerInterval) clearInterval(timerInterval);
    timerInterval = setInterval(() => {
      state.timeLeft--;
      updateTimerDisplay();
      if (state.timeLeft === 60) Audio.tick();
      if (state.timeLeft <= 10 && state.timeLeft > 0) Audio.urgentTick();
      if (state.timeLeft <= 0) {
        clearInterval(timerInterval);
        timerInterval = null;
        Audio.sadEnd();
        timeUp();
      }
    }, 1000);
  }

  function stopTimer() {
    if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
  }

  let writingTimerInterval = null;
  function startWritingTimer() {
    state.timeLeft = state.timeLimit;
    updateWritingTimerDisplay();
    if (writingTimerInterval) clearInterval(writingTimerInterval);
    writingTimerInterval = setInterval(() => {
      state.timeLeft--;
      updateWritingTimerDisplay();
      if (state.timeLeft === 60) Audio.tick();
      if (state.timeLeft <= 10) Audio.urgentTick();
      if (state.timeLeft <= 0) {
        clearInterval(writingTimerInterval);
        writingTimerInterval = null;
        submitWriting();
      }
    }, 1000);
  }

  function stopWritingTimer() {
    if (writingTimerInterval) { clearInterval(writingTimerInterval); writingTimerInterval = null; }
  }

  function updateTimerDisplay() {
    const el = document.getElementById('timer-text');
    const box = document.getElementById('timer-box');
    if (el) el.textContent = formatTime(state.timeLeft);
    if (box) {
      if (state.timeLeft <= 60) box.classList.add('timer-urgent');
      else box.classList.remove('timer-urgent');
    }
  }

  function updateWritingTimerDisplay() {
    const el = document.getElementById('writing-timer-text');
    if (el) el.textContent = formatTime(state.timeLeft);
  }

  function timeUp() {
    // Show what was answered so far
    const total = state.questions ? state.questions.length : (state.spellingWords ? state.spellingWords.length : 0);
    showResults(state.score, total);
  }

  function formatTime(s) {
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2,'0')}`;
  }

  // ─── Next Question ────────────────────────────────────────
  function nextQ() {
    state.currentQ++;
    const total = state.questions.length;
    if (state.currentQ >= total) {
      stopTimer();
      showResults(state.score, total);
      return;
    }
    switch(state.subject) {
      case 'math':    renderMathQ();    break;
      case 'science': renderScienceQ(); break;
    }
  }

  // ─── RESULTS ─────────────────────────────────────────────
  function showResults(score, total, fromReading=false) {
    stopTimer();
    stopSpellingTimers();
    stopWritingTimer();
    stopAutosave();
    // Save only the delta not already persisted by autosave
    if (state.subject && state.grade && total > 0) {
      const deltaScore = score - state.autosavedScore;
      const deltaTotal = total - state.autosavedTotal;
      if (deltaTotal > 0) saveResult(state.subject, state.grade, deltaScore, deltaTotal);
    }
    const pct = total > 0 ? Math.round((score / total) * 100) : 0;

    // Play sound
    if (pct >= 80) Audio.fanfare();
    else if (pct >= 50) Audio.correct();
    else Audio.sadEnd();

    if (state.subject !== 'writing') {
      document.getElementById('ring-score').textContent = `${score}/${total}`;
      document.getElementById('ring-pct').textContent = `${pct}%`;
    }
    setRingProgress(pct);
    setStars(score, total);

    const titles = {
      0: "Keep Trying!", 33: "Getting There!", 50: "Almost!", 67: "Good Work!",
      80: "Great Job!", 90: "Excellent!", 100: "Perfect! 🌟"
    };
    let title = "Keep Trying!";
    for (const [threshold, t] of Object.entries(titles)) {
      if (pct >= Number(threshold)) title = t;
    }
    document.getElementById('results-title').textContent = title;

    if (state.subject !== 'writing') {
      document.getElementById('results-breakdown').innerHTML = `
        <div class="breakdown-item"><span>Correct</span><strong>${score}</strong></div>
        <div class="breakdown-item"><span>Wrong</span><strong>${total - score}</strong></div>
        <div class="breakdown-item"><span>Score</span><strong>${pct}%</strong></div>
        <div class="breakdown-item"><span>Mode</span><strong>${state.mode === 'test' ? '📝 Test' : '📚 Practice'}</strong></div>`;
    }

    showScreen('screen-results');
  }

  function setRingProgress(pct) {
    const ring = document.getElementById('ring-fill');
    if (!ring) return;
    const circumference = 2 * Math.PI * 50;
    const offset = circumference - (pct / 100) * circumference;
    ring.style.strokeDasharray = circumference;
    ring.style.strokeDashoffset = offset;
    const color = pct >= 80 ? '#4ecdc4' : pct >= 50 ? '#f7d060' : '#ff6b6b';
    ring.style.stroke = color;
  }

  function setStars(score, total) {
    const pct = total > 0 ? score / total : 0;
    const stars = pct >= 0.9 ? 3 : pct >= 0.7 ? 2 : pct >= 0.4 ? 1 : 0;
    // Award wallet stars once per session
    if (!state.starsAwarded && stars > 0) {
      state.starsAwarded = true;
      addStarsToWallet(stars);
    }
    const starsEl = document.getElementById('results-stars');
    if (starsEl) {
      starsEl.innerHTML = [1,2,3].map(i =>
        `<span class="star ${i <= stars ? 'star-lit' : 'star-dim'}">★</span>`
      ).join('');
    }
  }

  function playAgain() {
    Audio.click();
    const savedGrade = state.grade;
    const savedSubject = state.subject;
    const savedMode = state.mode;
    const savedTime = state.timeLimit;
    const savedWordTime = state.wordTimeLimit;
    resetState();
    state.grade = savedGrade;
    state.subject = savedSubject;
    startSession(savedMode, savedSubject === 'spelling' && savedMode === 'test' ? savedWordTime : savedTime);
  }

  // ─── Helpers ─────────────────────────────────────────────
  function updatePlayHeader(current, total) {
    document.getElementById('q-label').textContent = `Question ${current} / ${total}`;
    const pct = ((current - 1) / total) * 100;
    document.getElementById('progress-fill').style.width = pct + '%';
  }

  function disableChoices() {
    document.querySelectorAll('.choice-btn').forEach(b => b.disabled = true);
  }

  function highlightChoice(val, cls) {
    document.querySelectorAll('.choice-btn').forEach(b => {
      if (b.textContent.trim() === val) b.classList.add(cls);
    });
  }

  function disableEl(id) {
    const el = document.getElementById(id);
    if (el) el.disabled = true;
  }

  function escQ(s) {
    return s.replace(/'/g, "\\'").replace(/"/g, '&quot;');
  }

  // ─── Flash Feedback ───────────────────────────────────────
  function showFlash(msg, cls) {
    const flash = document.getElementById('feedback-flash');
    const inner = document.getElementById('flash-inner');
    inner.textContent = msg;
    inner.className = 'flash-inner ' + cls;
    flash.classList.remove('hidden');
    setTimeout(() => flash.classList.add('hidden'), 900);
  }

  // ─── LEVEL TEST SYSTEM ───────────────────────────────────
  const SUBJ_ORDER = ['math','reading','writing','spelling','science'];
  const SUBJ_NAMES = { math:'Math', reading:'Reading', writing:'Writing', spelling:'Spelling', science:'Science' };
  const SUBJ_ICONS = { math:'➕', reading:'📖', writing:'✏️', spelling:'🔤', science:'🔬' };
  const SUBJ_CLS   = { math:'math', reading:'reading', writing:'writing', spelling:'spelling', science:'science' };

  let lt = {};  // level test live state
  let ltSettings = { iqRounding: 10, startMode: 'auto' };

  function resetLT() {
    const startIdx = getLTStartIdx();
    lt = {
      subjIdx: 0,
      qInSubj: 0,
      totalQ: 0,
      levels: SUBJ_ORDER.map(() => startIdx),    // current difficulty per subject (float)
      levelHistory: SUBJ_ORDER.map(() => []),      // level snapshot after each Q
      scores: SUBJ_ORDER.map(() => 0),             // correct answers per subject
      usedIds: SUBJ_ORDER.map(() => []),            // used question IDs per subject
      finalLevels: SUBJ_ORDER.map(() => null),      // computed at end of each subject
      currentQ: null,
    };
  }

  function getLTStartIdx() {
    switch (ltSettings.startMode) {
      case 'easy': return 3;
      case 'mid':  return 6;
      case 'hard': return 10;
      default: { // auto: use average progress level
        const indices = SUBJ_ORDER.map(s => {
          const lv = getSubjectLevel(s);
          return lv ? GRADE_ORDER.indexOf(lv) : -1;
        }).filter(i => i >= 0);
        if (!indices.length) return 5;
        return Math.round(indices.reduce((a,b)=>a+b,0)/indices.length);
      }
    }
  }

  function showLevelSetup() {
    Audio.click();
    showScreen('screen-lt-setup');
  }

  function setLtRounding(val, btn) {
    ltSettings.iqRounding = val;
    document.querySelectorAll('#lt-rounding-group .lt-radio-btn').forEach(b => b.classList.remove('lt-radio-active'));
    btn.classList.add('lt-radio-active');
  }

  function setLtStart(val, btn) {
    ltSettings.startMode = val;
    document.querySelectorAll('#lt-start-group .lt-radio-btn').forEach(b => b.classList.remove('lt-radio-active'));
    btn.classList.add('lt-radio-active');
  }

  function beginLevelTest() {
    Audio.click();
    resetLT();
    showScreen('screen-lt-play');
    renderLTQuestion();
  }

  function renderLTQuestion() {
    const si = lt.subjIdx;
    const subject = SUBJ_ORDER[si];
    const levelFloat = lt.levels[si];
    const gradeLabel_ = gradeLabel(gradeIdxToGrade(levelFloat));

    // Update header
    document.getElementById('lt-q-label').textContent =
      `${SUBJ_NAMES[subject]} ${lt.qInSubj + 1}/20`;
    const pct = (lt.totalQ / 100) * 100;
    document.getElementById('lt-progress-fill').style.width = pct + '%';
    const badge = document.getElementById('lt-diff-badge');
    badge.textContent = gradeLabel_;
    badge.className = `lt-diff-badge lt-diff-${SUBJ_CLS[subject]}`;

    // Generate question
    const q = getLevelTestQ(subject, levelFloat, lt.usedIds[si]);
    lt.currentQ = q;
    if (q._id) lt.usedIds[si].push(q._id);
    else if (q.question) lt.usedIds[si].push(q.question.slice(0,20));

    const body = document.getElementById('lt-play-body');
    const passageHtml = q.passageText
      ? `<div class="lt-passage">${q.passageText}</div>`
      : '';
    body.innerHTML = `
      <div class="question-card">
        <div class="subject-tag ${SUBJ_CLS[subject]}-tag">${SUBJ_ICONS[subject]} ${SUBJ_NAMES[subject]}</div>
        ${passageHtml}
        <div class="question-text">${q.question}</div>
        <div class="choices-grid choices-col">
          ${q.choices.map(c =>
            `<button class="choice-btn" onclick="App.answerLT('${c.replace(/'/g,"&#39;")}')">${c}</button>`
          ).join('')}
        </div>
      </div>`;
  }

  function answerLT(chosen) {
    const q = lt.currentQ;
    const si = lt.subjIdx;
    document.querySelectorAll('#lt-play-body .choice-btn').forEach(b => b.disabled = true);

    const correct = chosen === q.answer;
    if (correct) {
      lt.scores[si]++;
      Audio.correct();
      showFlash('✓ Correct!', 'flash-correct');
      lt.levels[si] = Math.min(13, lt.levels[si] + 0.75);
    } else {
      Audio.wrong();
      showFlash(`✗ ${q.answer}`, 'flash-wrong');
      lt.levels[si] = Math.max(0, lt.levels[si] - 0.5);
    }

    // Highlight choices
    document.querySelectorAll('#lt-play-body .choice-btn').forEach(b => {
      if (b.textContent.trim() === q.answer) b.classList.add('correct');
      else if (b.textContent.trim() === chosen && !correct) b.classList.add('wrong');
    });

    lt.levelHistory[si].push(lt.levels[si]);
    lt.qInSubj++;
    lt.totalQ++;

    if (lt.qInSubj >= 20) {
      // Compute final level for this subject: weighted average of last 10 level snapshots
      const hist = lt.levelHistory[si];
      const tail = hist.slice(-10);
      const avg = tail.reduce((a,b)=>a+b,0) / tail.length;
      lt.finalLevels[si] = avg;
      // Save to progress
      const finalGrade = gradeIdxToGrade(avg);
      saveResult(SUBJ_ORDER[si], finalGrade, lt.scores[si], 20);
    }

    setTimeout(() => {
      if (lt.qInSubj >= 20) {
        lt.subjIdx++;
        lt.qInSubj = 0;
        if (lt.subjIdx >= SUBJ_ORDER.length) {
          showLTResults();
        } else {
          showSubjectTransition();
        }
      } else {
        renderLTQuestion();
      }
    }, 1100);
  }

  function showSubjectTransition() {
    const nextSubj = SUBJ_ORDER[lt.subjIdx];
    const body = document.getElementById('lt-play-body');
    const doneSubj = SUBJ_ORDER[lt.subjIdx - 1];
    const doneLevel = gradeIdxToGrade(lt.finalLevels[lt.subjIdx - 1]);
    body.innerHTML = `
      <div class="lt-transition-card">
        <div class="lt-trans-done">
          <span class="lt-trans-icon">${SUBJ_ICONS[doneSubj]}</span>
          <span>${SUBJ_NAMES[doneSubj]} complete</span>
          <span class="lt-trans-level">${gradeLabel(doneLevel)}</span>
        </div>
        <div class="lt-trans-next">
          <div class="lt-trans-next-label">Up next</div>
          <div class="lt-trans-next-name">${SUBJ_ICONS[nextSubj]} ${SUBJ_NAMES[nextSubj]}</div>
          <div class="lt-trans-next-sub">20 questions · adaptive difficulty</div>
        </div>
        <button class="btn-primary" onclick="App.renderLTQuestion()">Start ${SUBJ_NAMES[nextSubj]} →</button>
      </div>`;
    document.getElementById('lt-q-label').textContent = `${lt.subjIdx * 20}/100 done`;
    document.getElementById('lt-progress-fill').style.width = `${lt.subjIdx * 20}%`;
    Audio.click();
  }

  function showLTResults() {
    showScreen('screen-lt-results');

    // Compute overall IQ
    const validLevels = lt.finalLevels.filter(l => l !== null);
    const avgLevel = validLevels.reduce((a,b)=>a+b,0) / validLevels.length;
    const rawIQ = gradeIdxToIQ(avgLevel);
    const r = ltSettings.iqRounding;
    const iq = Math.round(rawIQ / r) * r;

    // IQ description
    const iqDesc = iq >= 140 ? 'Exceptional — top 0.5%'
      : iq >= 130 ? 'Very superior — top 2%'
      : iq >= 120 ? 'Superior — top 9%'
      : iq >= 110 ? 'Above average — top 25%'
      : iq >= 100 ? 'Average range'
      : iq >= 90  ? 'Below average range'
      : 'Developing — keep practicing!';

    document.getElementById('lt-iq-number').textContent = iq;
    document.getElementById('lt-iq-desc').textContent = iqDesc;

    // Color the IQ card
    const iqCard = document.getElementById('lt-iq-card');
    iqCard.className = 'lt-iq-card ' + (iq >= 120 ? 'iq-high' : iq >= 100 ? 'iq-avg' : 'iq-low');

    // Overall grade
    const overallGrade = gradeIdxToGrade(avgLevel);
    document.getElementById('lt-overall-grade').innerHTML = `
      <div class="lt-overall-result">
        <span class="lt-overall-icon">🎓</span>
        <div>
          <div class="lt-overall-sub">Overall Performance Level</div>
          <div class="lt-overall-lbl">${gradeLabel(overallGrade)}</div>
        </div>
      </div>`;

    // Per-subject cards
    const cards = SUBJ_ORDER.map((s, i) => {
      const fl = lt.finalLevels[i];
      const lv = fl !== null ? gradeIdxToGrade(fl) : null;
      const acc = Math.round((lt.scores[i] / 20) * 100);
      const stars = accToStars(acc);
      const starsHtml = [1,2,3,4,5].map(n =>
        `<span class="pstar ${n<=stars?'pstar-lit':'pstar-dim'}">★</span>`).join('');
      return `
        <div class="prog-card prog-subj-${SUBJ_CLS[s]}">
          <div class="prog-left">
            <span class="prog-icon">${SUBJ_ICONS[s]}</span>
            <div class="prog-meta">
              <div class="prog-name">${SUBJ_NAMES[s]}</div>
              <div class="prog-level-lbl ${lv?'prog-level-has':''}">${lv ? gradeLabel(lv) : '—'}</div>
            </div>
          </div>
          <div class="prog-right">
            <div class="prog-stars">${starsHtml}</div>
            <div class="prog-stat">${lt.scores[i]}/20 correct · ${acc}%</div>
            <div class="prog-acc-bar"><div class="prog-acc-fill" style="width:${acc}%"></div></div>
          </div>
        </div>`;
    }).join('');
    document.getElementById('lt-subject-cards').innerHTML = cards;

    if (iq >= 120) Audio.fanfare();
    else if (iq >= 100) Audio.correct();
    else Audio.sadEnd();
  }

  function confirmLtExit() {
    Audio.click();
    const modal = document.getElementById('modal');
    document.getElementById('modal-title').textContent = 'Exit Level Test?';
    document.getElementById('modal-msg').textContent = 'Progress in this test will be lost.';
    const ok = document.getElementById('modal-ok');
    ok.textContent = 'Yes, Exit';
    ok.onclick = () => { closeModal(); showWelcome(); };
    modal.classList.remove('hidden');
  }

  // ─── BAD WORD FILTER ─────────────────────────────────────
  const BAD_WORDS = [
    'ass','arse','bastard','bitch','bollocks','bullshit','cock','crap','cum',
    'cunt','damn','dick','dildo','douche','dumbass','fag','faggot','fuck',
    'fucker','fucking','goddamn','hell','homo','jackass','jerk','moron',
    'motherfucker','nigga','nigger','penis','piss','porn','prick','pussy',
    'retard','shit','slut','spaz','twat','vagina','wank','whore'
  ];
  function hasBadWord(text) {
    const clean = text.toLowerCase().replace(/[^a-z]/g,'');
    return BAD_WORDS.some(w => clean.includes(w));
  }

  // ─── NAME SYSTEM ─────────────────────────────────────────
  const NAME_KEY = 'lsp_name';

  function getName() { return localStorage.getItem(NAME_KEY) || ''; }
  function setName(n) { localStorage.setItem(NAME_KEY, n.trim()); }

  function renderGreeting() {
    const el = document.getElementById('welcome-greeting');
    if (!el) return;
    const name = getName();
    if (name) {
      el.innerHTML = `<span class="greeting-hi">Hi, ${name}!</span> <button class="greeting-edit" onclick="App.promptName(true)" title="Change name">✏️</button>`;
    } else {
      el.innerHTML = `<button class="greeting-set" onclick="App.promptName(false)">👤 Set your name</button>`;
    }
  }

  function promptName(isEdit) {
    const current = getName();
    const modal = document.getElementById('modal');
    document.getElementById('modal-title').textContent = isEdit ? 'Change Your Name' : 'What\'s your name?';
    document.getElementById('modal-msg').innerHTML =
      `<input id="name-input" type="text" maxlength="20" placeholder="Enter your name…" style="
        width:100%;margin-top:10px;padding:11px 14px;border-radius:8px;
        border:2px solid rgba(255,255,255,0.15);background:#16213e;
        color:#fff;font-size:1.1rem;text-align:center;font-family:inherit;
      " value="${current}">`;
    const ok = document.getElementById('modal-ok');
    ok.textContent = isEdit ? 'Save' : 'Let\'s go! 🚀';
    ok.onclick = () => {
      const val = ((document.getElementById('name-input') || {}).value || '').trim();
      if (!val) { closeModal(); return; }
      if (hasBadWord(val)) {
        const inp = document.getElementById('name-input');
        if (inp) {
          inp.style.borderColor = '#ff6b6b';
          inp.value = '';
          inp.placeholder = '⚠️ Keep it kind — try again!';
        }
        return; // don't close modal
      }
      setName(val); closeModal(); renderGreeting();
    };
    const cancel = document.getElementById('modal-cancel');
    cancel.textContent = 'Skip';
    cancel.onclick = () => closeModal();
    modal.classList.remove('hidden');
    setTimeout(() => {
      const inp = document.getElementById('name-input');
      if (inp) { inp.focus(); inp.select(); }
    }, 80);
  }

  // ─── STAR WALLET & TOKEN SYSTEM ──────────────────────────
  const WALLET_KEY  = 'lsp_stars';
  const TOKENS_KEY  = 'lsp_tokens';

  function getWallet() { return parseInt(localStorage.getItem(WALLET_KEY) || '0', 10); }
  function addStarsToWallet(n) {
    if (n <= 0) return;
    localStorage.setItem(WALLET_KEY, getWallet() + n);
    updateStarDisplays();
  }
  function spendStars(n) {
    const s = getWallet();
    if (s < n) return false;
    localStorage.setItem(WALLET_KEY, s - n);
    updateStarDisplays();
    return true;
  }
  function getTokens() { try { return JSON.parse(localStorage.getItem(TOKENS_KEY) || '{}'); } catch(e) { return {}; } }
  function addTokens(game, n) { const t=getTokens(); t[game]=(t[game]||0)+n; localStorage.setItem(TOKENS_KEY,JSON.stringify(t)); }
  function useToken(game) { const t=getTokens(); if(!(t[game]>0)) return false; t[game]--; localStorage.setItem(TOKENS_KEY,JSON.stringify(t)); return true; }
  function updateStarDisplays() {
    const s = getWallet();
    document.querySelectorAll('.star-wallet-count').forEach(el => el.textContent = s);
  }

  // ─── GAMES STORE ─────────────────────────────────────────
  function showStore() {
    Audio.click();
    showScreen('screen-store');
    updateStarDisplays();
    renderStore();
  }

  function renderStore() {
    const tokens = getTokens();
    const GAMES = [
      { key:'match',    name:'Match',    icon:'🃏', color:'#7c6af7', single:50,  bundle:400,
        desc:'Flip face-down cards and find pairs of equal values. Beat your best time!' },
      { key:'pizzeria', name:'Pizzeria', icon:'🍕', color:'#ff9f43', single:55,  bundle:450,
        desc:'Customers order fractions of pizza — cut it right and serve them fast. 1 pizza = 1 ⭐!' },
      { key:'archery',  name:'Archery',  icon:'🏹', color:'#4ecdc4', single:60,  bundle:500,
        desc:'Solve math equations to aim your arrow. Build a streak for a bullseye — worth 5 real stars!' },
    ];
    document.getElementById('store-games').innerHTML = GAMES.map(g => {
      const tok = tokens[g.key] || 0;
      const bundleSave = g.single * 10 - g.bundle;
      return `
        <div class="game-card" style="border-color:${g.color}50">
          <div class="game-card-head">
            <span class="game-big-icon">${g.icon}</span>
            <div class="game-card-info">
              <div class="game-card-name">${g.name}</div>
              <div class="game-card-desc">${g.desc}</div>
            </div>
          </div>
          <div class="game-card-foot">
            <div class="game-tok-count ${tok>0?'tok-active':''}">
              ${tok > 0 ? `${tok} play${tok!==1?'s':''} ready` : 'No plays left'}
            </div>
            <div class="game-buy-row">
              ${tok > 0 ? `<button class="btn-play-now" style="background:${g.color}" onclick="App.playGame('${g.key}')">▶ Play</button>` : ''}
              <button class="btn-buy-one" onclick="App.buyGame('${g.key}',1)">1 play <strong>⭐${g.single}</strong></button>
              <button class="btn-buy-bundle" onclick="App.buyGame('${g.key}',10)">×10 bundle <strong>⭐${g.bundle}</strong> <span class="save-tag">save ${bundleSave}!</span></button>
            </div>
          </div>
        </div>`;
    }).join('');
  }

  // Per-game costs — single play and bundle
  const GAME_COSTS = { match:{single:50,bundle:400}, pizzeria:{single:55,bundle:450}, archery:{single:60,bundle:500} };

  function buyGame(game, qty) {
    Audio.click();
    const costs = GAME_COSTS[game] || {single:50,bundle:400};
    const cost = qty === 1 ? costs.single : costs.bundle;
    if (!spendStars(cost)) {
      showFlash(`Need ⭐ ${cost} stars — keep studying!`, 'flash-wrong');
      Audio.wrong();
      return;
    }
    addTokens(game, qty);
    Audio.correct();
    showFlash(`+${qty} play${qty>1?'s':''} unlocked! 🎮`, 'flash-correct');
    renderStore();
  }

  function playGame(game) {
    Audio.click();
    if (!useToken(game)) { showFlash('No plays left! Buy more.', 'flash-wrong'); return; }
    switch(game) {
      case 'match':    startMatch();    break;
      case 'pizzeria': startPizzeria(); break;
      case 'archery':  startArchery();  break;
    }
  }

  function exitGame() {
    Audio.click();
    if (matchState.timer) { clearInterval(matchState.timer); matchState.timer = null; }
    if (pizzaTimer)       { clearInterval(pizzaTimer); pizzaTimer = null; }
    showStore();
  }

  // ─── MATCH CARD GAME ─────────────────────────────────────
  const MATCH_PAIRS = [
    {id:0, a:"3 × 4",   b:"12"},
    {id:1, a:"5 + 8",   b:"13"},
    {id:2, a:"20 − 6",  b:"14"},
    {id:3, a:"45 ÷ 5",  b:"9"},
    {id:4, a:"1/2",     b:"50%"},
    {id:5, a:"1/4",     b:"25%"},
    {id:6, a:"√25",     b:"5"},
    {id:7, a:"2³",      b:"8"},
  ];
  const MATCH_RECORD_KEY = 'lsp_match_best';
  let matchState = { timer: null };

  function startMatch() {
    showScreen('screen-match');
    const cards = [];
    MATCH_PAIRS.forEach(p => {
      cards.push({id:p.id, val:p.a, flipped:false, matched:false});
      cards.push({id:p.id, val:p.b, flipped:false, matched:false});
    });
    for(let i=cards.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[cards[i],cards[j]]=[cards[j],cards[i]];}
    matchState = { cards, firstIdx:null, secondIdx:null, matches:0, seconds:0, timer:null, canFlip:true };
    const rec = localStorage.getItem(MATCH_RECORD_KEY);
    document.getElementById('match-record').textContent = rec ? `Best: ${formatTime(parseInt(rec))}` : 'Best: --';
    document.getElementById('match-timer').textContent = '0:00';
    renderMatchGrid();
    matchState.timer = setInterval(() => {
      matchState.seconds++;
      document.getElementById('match-timer').textContent = formatTime(matchState.seconds);
    }, 1000);
  }

  function renderMatchGrid() {
    document.getElementById('match-grid').innerHTML = matchState.cards.map((c,i) => `
      <div class="match-card ${c.flipped?'mc-flipped':''} ${c.matched?'mc-matched':''}" onclick="App.flipCard(${i})">
        <div class="mc-inner">
          <div class="mc-back">?</div>
          <div class="mc-front">${c.val}</div>
        </div>
      </div>`).join('');
  }

  function flipCard(idx) {
    if (!matchState.canFlip) return;
    const c = matchState.cards[idx];
    if (c.flipped || c.matched) return;
    Audio.click();
    c.flipped = true;
    if (matchState.firstIdx === null) {
      matchState.firstIdx = idx;
      renderMatchGrid();
    } else {
      matchState.secondIdx = idx;
      matchState.canFlip = false;
      renderMatchGrid();
      const a = matchState.cards[matchState.firstIdx];
      const b = matchState.cards[matchState.secondIdx];
      if (a.id === b.id) {
        Audio.correct();
        a.matched = b.matched = true;
        matchState.matches++;
        matchState.firstIdx = matchState.secondIdx = null;
        matchState.canFlip = true;
        renderMatchGrid();
        if (matchState.matches === MATCH_PAIRS.length) { clearInterval(matchState.timer); setTimeout(showMatchResults, 500); }
      } else {
        Audio.wrong();
        setTimeout(() => {
          a.flipped = b.flipped = false;
          matchState.firstIdx = matchState.secondIdx = null;
          matchState.canFlip = true;
          renderMatchGrid();
        }, 900);
      }
    }
  }

  function showMatchResults() {
    const t = matchState.seconds;
    const prev = parseInt(localStorage.getItem(MATCH_RECORD_KEY) || '99999', 10);
    const isRecord = t < prev;
    if (isRecord) localStorage.setItem(MATCH_RECORD_KEY, t);
    const stars = t <= 30 ? 3 : t <= 60 ? 2 : 1;
    addStarsToWallet(stars);
    if (isRecord) Audio.fanfare(); else Audio.correct();
    document.getElementById('match-grid').innerHTML = `
      <div class="game-result-screen">
        <div class="gr-stars">${[1,2,3].map(i=>`<span class="star ${i<=stars?'star-lit':'star-dim'}">★</span>`).join('')}</div>
        <div class="gr-main">⏱ ${formatTime(t)}</div>
        ${isRecord ? '<div class="gr-record">🏆 New Record!</div>' : `<div class="gr-sub">Best: ${formatTime(prev)}</div>`}
        <div class="gr-earned">+${stars} ⭐ added to wallet</div>
        <div class="gr-btns">
          <button class="btn-primary" onclick="App.playGame('match')">Play Again</button>
          <button class="btn-secondary" onclick="App.showStore()">Store</button>
        </div>
      </div>`;
  }

  // ─── PIZZERIA GAME ────────────────────────────────────────
  const PIZZA_FRACS = [
    {n:1,d:2,lbl:"1/2"},{n:1,d:3,lbl:"1/3"},{n:1,d:4,lbl:"1/4"},
    {n:2,d:3,lbl:"2/3"},{n:3,d:4,lbl:"3/4"},{n:1,d:6,lbl:"1/6"},{n:1,d:8,lbl:"1/8"},
  ];
  const CUSTOMER_NAMES = ["Alex","Sam","Jordan","Taylor","Morgan","Casey","Riley","Drew","Chris","Pat"];
  let pizzaState = {};
  let pizzaTimer = null;

  function startPizzeria() {
    showScreen('screen-pizzeria');
    pizzaState = { score:0, timeLeft:60, current:null, feedback:'', fbType:'' };
    nextPizzaCustomer();
    if (pizzaTimer) clearInterval(pizzaTimer);
    pizzaTimer = setInterval(() => {
      pizzaState.timeLeft--;
      const el = document.getElementById('pizzeria-timer');
      if (el) el.textContent = formatTime(pizzaState.timeLeft);
      if (pizzaState.timeLeft <= 0) { clearInterval(pizzaTimer); pizzaTimer = null; showPizzeriaResults(); }
    }, 1000);
  }

  function nextPizzaCustomer() {
    pizzaState.current = PIZZA_FRACS[rnd(0, PIZZA_FRACS.length-1)];
    pizzaState.customerName = CUSTOMER_NAMES[rnd(0, CUSTOMER_NAMES.length-1)];
    pizzaState.feedback = '';
    renderPizzeria();
  }

  function renderPizzeria() {
    const f = pizzaState.current;
    document.getElementById('pizzeria-score-hdr').textContent = `${pizzaState.score} 🍕`;
    document.getElementById('pizzeria-body').innerHTML = `
      <div class="pizza-scene">
        <div class="pizza-customer-bubble">
          <span class="pizza-customer-name">${pizzaState.customerName}</span> wants
          <span class="pizza-want">${f.lbl}</span> of the pizza!
        </div>
        <div class="pizza-svg-wrap">${buildPizzaSVG(f.n, f.d)}</div>
        <div class="pizza-btns">
          ${PIZZA_FRACS.map(fr =>
            `<button class="pizza-btn ${fr.lbl===f.lbl?'pizza-btn-target':''}"
              onclick="App.servePizza('${fr.lbl}','${f.lbl}')">${fr.lbl}</button>`).join('')}
        </div>
        ${pizzaState.feedback ? `<div class="pizza-fb ${pizzaState.fbType}">${pizzaState.feedback}</div>` : ''}
      </div>`;
  }

  function buildPizzaSVG(n, d) {
    const cx=80, cy=80, r=65;
    const sa = -Math.PI/2;
    const sweep = (n/d)*2*Math.PI;
    const ea = sa + sweep;
    const x1=(cx+r*Math.cos(sa)).toFixed(1), y1=(cy+r*Math.sin(sa)).toFixed(1);
    const x2=(cx+r*Math.cos(ea)).toFixed(1), y2=(cy+r*Math.sin(ea)).toFixed(1);
    const la = sweep > Math.PI ? 1 : 0;
    return `<svg viewBox="0 0 160 160" width="150" height="150">
      <circle cx="${cx}" cy="${cy}" r="${r}" fill="#f9ca24" stroke="#e67e22" stroke-width="3"/>
      <circle cx="65" cy="70" r="5" fill="#c0392b"/><circle cx="95" cy="72" r="5" fill="#c0392b"/>
      <circle cx="80" cy="92" r="5" fill="#27ae60"/><circle cx="62" cy="88" r="4" fill="#27ae60"/>
      <circle cx="100" cy="60" r="4" fill="#c0392b"/>
      <path d="M${cx},${cy} L${x1},${y1} A${r},${r} 0 ${la},1 ${x2},${y2} Z"
            fill="rgba(255,107,107,0.72)" stroke="#c0392b" stroke-width="2"/>
      <text x="${cx}" y="${cy-r-10}" text-anchor="middle" font-size="15" font-weight="900" fill="#333">${n}/${d}</text>
    </svg>`;
  }

  function servePizza(chosen, target) {
    if (chosen === target) {
      Audio.correct();
      pizzaState.score++;
      pizzaState.feedback = '✓ Perfect! Next customer…';
      pizzaState.fbType = 'fb-correct';
      renderPizzeria();
      setTimeout(nextPizzaCustomer, 650);
    } else {
      Audio.wrong();
      pizzaState.feedback = `✗ That's ${chosen} — try again!`;
      pizzaState.fbType = 'fb-wrong';
      renderPizzeria();
    }
  }

  function showPizzeriaResults() {
    const score = pizzaState.score;
    // 1 pizza served = 1 star earned
    const stars = score;
    if (stars > 0) addStarsToWallet(stars);
    if (score >= 8) Audio.fanfare(); else if (score > 0) Audio.correct(); else Audio.sadEnd();
    // Show 3-star badge based on performance tier (display only, not currency)
    const badge = score >= 8 ? 3 : score >= 4 ? 2 : score >= 1 ? 1 : 0;
    document.getElementById('pizzeria-body').innerHTML = `
      <div class="game-result-screen">
        <div class="gr-stars">${[1,2,3].map(i=>`<span class="star ${i<=badge?'star-lit':'star-dim'}">★</span>`).join('')}</div>
        <div class="gr-main">${score} pizza${score!==1?'s':''} served!</div>
        <div class="gr-earned">+${stars} ⭐ added to wallet</div>
        <div class="gr-sub" style="color:var(--text-dim);font-size:0.85rem">1 pizza = 1 star</div>
        <div class="gr-btns">
          <button class="btn-primary" onclick="App.playGame('pizzeria')">Play Again</button>
          <button class="btn-secondary" onclick="App.showStore()">Store</button>
        </div>
      </div>`;
  }

  // ─── ARCHERY GAME ─────────────────────────────────────────
  let archeryState = {};

  function startArchery() {
    showScreen('screen-archery');
    archeryState = {
      streak: 0, score: 0, starsEarned: 0,
      arrowsLeft: 10, arrows: [], currentQ: null,
      grade: state.grade || '6',
    };
    document.getElementById('archery-pts').textContent = '0 pts';
    document.getElementById('archery-wallet-gain').textContent = '⭐ 0 earned';
    nextArcheryQ();
  }

  function nextArcheryQ() {
    if (archeryState.arrowsLeft <= 0) { showArcheryResults(); return; }
    archeryState.currentQ = generateMathProblem(archeryState.grade, archeryState.streak > 3);
    archeryState.arrowsLeft--;
    renderArchery();
  }

  function renderArchery() {
    const streak = archeryState.streak;
    const aimPct = Math.min(100, streak * 18 + 10);
    const aimColor = aimPct >= 80 ? '#4ecdc4' : aimPct >= 50 ? '#f7d060' : '#ff6b6b';
    const q = archeryState.currentQ;
    document.getElementById('archery-body').innerHTML = `
      <div class="archery-layout">
        <div class="archery-left">
          ${buildTargetSVG(archeryState.arrows)}
          <div class="aim-bar-wrap">
            <div class="aim-bar-label">Aim Precision</div>
            <div class="aim-bar-track">
              <div class="aim-bar-fill" style="width:${aimPct}%;background:${aimColor}"></div>
            </div>
            <div class="aim-streak">🔥 Streak: ${streak}</div>
          </div>
        </div>
        <div class="archery-right">
          <div class="archery-arrows-left">Arrows left: ${archeryState.arrowsLeft}</div>
          <div class="question-text arch-q">${q.question}</div>
          <div class="choices-grid">
            ${q.choices.map(c =>
              `<button class="choice-btn" onclick="App.shootArrow('${c.replace(/'/g,"&#39;")}')">${c}</button>`
            ).join('')}
          </div>
          ${streak >= 5 ? '<div class="bullseye-alert">🎯 Next correct = BULLSEYE +5⭐!</div>' : ''}
        </div>
      </div>`;
  }

  function buildTargetSVG(arrows) {
    const rings = [{r:58,fill:'#fff'},{r:46,fill:'#000'},{r:34,fill:'#2196f3'},{r:22,fill:'#f44336'},{r:10,fill:'#ffeb3b'}];
    const ringsSvg = rings.map(({r,fill}) =>
      `<circle cx="60" cy="60" r="${r}" fill="${fill}" stroke="rgba(0,0,0,0.2)" stroke-width="1"/>`).join('');
    const ringNums = rings.map(({r},i) =>
      `<text x="${60+r-7}" y="63" font-size="7" fill="${i<2?'#aaa':'#555'}">${i+1}</text>`).join('');
    const arrowsSvg = arrows.map((a,i) => {
      if (!a.hit) return '';
      const ringData = [58,42,30,18,6];
      const dist = ringData[a.ring-1];
      const angle = (i/(arrows.length||1))*6.28 + i*0.7;
      const ax = (60 + dist*Math.cos(angle)).toFixed(1);
      const ay = (60 + dist*Math.sin(angle)).toFixed(1);
      return `<circle cx="${ax}" cy="${ay}" r="3.5" fill="#ff4444" stroke="white" stroke-width="1.5"/>
              <line x1="${ax}" y1="${ay}" x2="${ax}" y2="${parseFloat(ay)-12}" stroke="#8B4513" stroke-width="2"/>`;
    }).join('');
    return `<svg viewBox="0 0 120 120" width="150" height="150" style="filter:drop-shadow(0 4px 12px rgba(0,0,0,0.4))">
      ${ringsSvg}${ringNums}${arrowsSvg}
    </svg>`;
  }

  function shootArrow(chosen) {
    const q = archeryState.currentQ;
    const correct = chosen === q.answer;
    document.querySelectorAll('#archery-body .choice-btn').forEach(b => {
      b.disabled = true;
      if (b.textContent.trim() === q.answer) b.classList.add('correct');
      else if (b.textContent.trim() === chosen && !correct) b.classList.add('wrong');
    });

    let ring, bonus = 0;
    if (correct) {
      archeryState.streak++;
      const s = archeryState.streak;
      ring = s >= 5 ? 5 : s >= 4 ? 4 : s >= 3 ? 3 : s >= 2 ? 2 : 1;
      archeryState.score += ring;
      archeryState.arrows.push({ hit:true, ring });
      if (ring === 5) {
        bonus = 5;
        archeryState.starsEarned += 5;
        addStarsToWallet(5);
        Audio.fanfare();
        showFlash('🎯 BULLSEYE! +5⭐', 'flash-correct');
      } else {
        Audio.correct();
        showFlash(`Ring ${ring}! +${ring} pts`, 'flash-correct');
      }
    } else {
      archeryState.streak = 0;
      archeryState.arrows.push({ hit:false, ring:0 });
      Audio.wrong();
      showFlash('Miss!', 'flash-wrong');
    }

    document.getElementById('archery-pts').textContent = `${archeryState.score} pts`;
    document.getElementById('archery-wallet-gain').textContent = `⭐ ${archeryState.starsEarned} earned`;
    setTimeout(nextArcheryQ, 1000);
  }

  function showArcheryResults() {
    const score = archeryState.score;
    const bullseyes = archeryState.arrows.filter(a => a.ring===5).length;
    const sessionStars = score >= 40 ? 3 : score >= 20 ? 2 : score >= 5 ? 1 : 0;
    if (sessionStars > 0) addStarsToWallet(sessionStars);
    if (score >= 40) Audio.fanfare(); else if (score > 0) Audio.correct(); else Audio.sadEnd();
    document.getElementById('archery-body').innerHTML = `
      <div class="game-result-screen">
        <div class="gr-stars">${[1,2,3].map(i=>`<span class="star ${i<=sessionStars?'star-lit':'star-dim'}">★</span>`).join('')}</div>
        <div class="gr-main">${score} / 50 pts</div>
        ${bullseyes > 0 ? `<div class="gr-record">🎯 ${bullseyes} bullseye${bullseyes!==1?'s':''}!</div>` : ''}
        ${archeryState.starsEarned > 0 ? `<div class="gr-bonus-stars">+${archeryState.starsEarned} ⭐ bullseye bonus!</div>` : ''}
        <div class="gr-earned">+${sessionStars} ⭐ session stars</div>
        <div class="gr-btns">
          <button class="btn-primary" onclick="App.playGame('archery')">Play Again</button>
          <button class="btn-secondary" onclick="App.showStore()">Store</button>
        </div>
      </div>`;
  }

  // ─── Progress / Rating System ────────────────────────────
  const PROGRESS_KEY = 'lsp_v1_progress';
  const GRADE_ORDER = ['K','1','2','3','4','5','6','7','8','9','10','11','12','SAT'];

  function loadProgress() {
    try { return JSON.parse(localStorage.getItem(PROGRESS_KEY) || '{}'); } catch(e) { return {}; }
  }

  function saveProgress(prog) {
    try { localStorage.setItem(PROGRESS_KEY, JSON.stringify(prog)); } catch(e) {}
  }

  function computeIQFromProg(prog) {
    const subjects = ['math','reading','writing','spelling','science'];
    const indices = subjects.map(s => {
      const subj = prog[s];
      if (!subj) return -1;
      let best = -1;
      for (const g of GRADE_ORDER) {
        if (!subj[g]) continue;
        const d = subj[g];
        if (d.total >= 8 && d.correct / d.total >= 0.65) best = GRADE_ORDER.indexOf(g);
      }
      return best;
    }).filter(i => i >= 0);
    if (!indices.length) return null;
    const avg = indices.reduce((a,b)=>a+b,0) / indices.length;
    return Math.round(gradeIdxToIQ(avg));
  }

  function saveResult(subject, grade, score, total) {
    if (!grade || total <= 0) return;
    const prog = loadProgress();
    if (!prog[subject]) prog[subject] = {};
    if (!prog[subject][grade]) prog[subject][grade] = { correct: 0, total: 0, sessions: 0 };
    prog[subject][grade].correct += score;
    prog[subject][grade].total += total;
    prog[subject][grade].sessions += 1;

    // Overall IQ snapshot for the main stock chart
    if (!prog.history) prog.history = [];
    const iq = computeIQFromProg(prog);
    if (iq) {
      prog.history.push({ ts: Date.now(), iq, subject });
      if (prog.history.length > 200) prog.history = prog.history.slice(-200);
    }

    // Per-subject accuracy snapshot for individual subject charts
    if (!prog.subjectHistory) prog.subjectHistory = {};
    if (!prog.subjectHistory[subject]) prog.subjectHistory[subject] = [];
    let tc = 0, tq = 0;
    for (const g of GRADE_ORDER) {
      if (prog[subject][g]) { tc += prog[subject][g].correct; tq += prog[subject][g].total; }
    }
    const sacc = tq > 0 ? Math.round(tc / tq * 100) : 0;
    prog.subjectHistory[subject].push({ ts: Date.now(), acc: sacc });
    if (prog.subjectHistory[subject].length > 50) prog.subjectHistory[subject] = prog.subjectHistory[subject].slice(-50);

    saveProgress(prog);
  }

  // ─── Stock Chart ──────────────────────────────────────────
  function buildStockChart(history) {
    if (!history || history.length < 2) {
      return `<div class="chart-empty">Complete a few sessions to see your growth chart</div>`;
    }

    const W = 560, H = 140;
    const PAD = { l:44, r:16, t:12, b:28 };
    const pts = history;
    const iqs = pts.map(p => p.iq);
    const rawMin = Math.min(...iqs), rawMax = Math.max(...iqs);
    const spread = Math.max(rawMax - rawMin, 10);
    const yMin = rawMin - spread * 0.15, yMax = rawMax + spread * 0.15;

    const xS = i => PAD.l + (i / (pts.length - 1)) * (W - PAD.l - PAD.r);
    const yS = v => PAD.t + (1 - (v - yMin) / (yMax - yMin)) * (H - PAD.t - PAD.b);

    const coordStr = pts.map((p,i) => `${xS(i).toFixed(1)},${yS(p.iq).toFixed(1)}`).join(' ');
    const first = pts[0].iq, last = pts[pts.length-1].iq;
    const isUp = last >= first;
    const color = isUp ? '#4ecdc4' : '#ff6b6b';
    const changePct = first > 0 ? Math.round(Math.abs((last-first)/first*100)) : 0;
    const arrow = isUp ? '▲' : '▼';

    // Area polygon
    const areaCoords = `${xS(0).toFixed(1)},${(H-PAD.b).toFixed(1)} ${coordStr} ${xS(pts.length-1).toFixed(1)},${(H-PAD.b).toFixed(1)}`;

    // Y-axis grid lines (3 lines)
    const gridIQs = [yMin + (yMax-yMin)*0.25, yMin + (yMax-yMin)*0.5, yMin + (yMax-yMin)*0.75];
    const gridLines = gridIQs.map(v => {
      const y = yS(v).toFixed(1);
      return `<line x1="${PAD.l}" y1="${y}" x2="${W-PAD.r}" y2="${y}" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>
              <text x="${PAD.l-6}" y="${y}" fill="rgba(255,255,255,0.3)" font-size="9" text-anchor="end" dominant-baseline="middle">${Math.round(v)}</text>`;
    }).join('');

    // First and last label
    const lastX = xS(pts.length-1).toFixed(1), lastY = yS(last).toFixed(1);
    const firstY = yS(first).toFixed(1);

    return `
      <svg viewBox="0 0 ${W} ${H}" class="stock-svg" preserveAspectRatio="xMidYMid meet">
        <defs>
          <linearGradient id="sg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="${color}" stop-opacity="0.25"/>
            <stop offset="100%" stop-color="${color}" stop-opacity="0.01"/>
          </linearGradient>
        </defs>
        ${gridLines}
        <polygon points="${areaCoords}" fill="url(#sg)"/>
        <polyline points="${coordStr}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
        <circle cx="${xS(0).toFixed(1)}" cy="${firstY}" r="3.5" fill="${color}" opacity="0.6"/>
        <circle cx="${lastX}" cy="${lastY}" r="5" fill="${color}"/>
        <text x="${lastX}" y="${(parseFloat(lastY)-10).toFixed(1)}" fill="${color}" font-size="10" text-anchor="middle" font-weight="bold">${last}</text>
      </svg>
      <div class="chart-footer">
        <span class="chart-sessions">${pts.length} session${pts.length!==1?'s':''}</span>
        <span class="chart-delta ${isUp?'chart-up':'chart-down'}">${arrow} ${changePct}% ${isUp?'growth':'decline'}</span>
        <span class="chart-range">IQ ${Math.min(...iqs)}–${Math.max(...iqs)}</span>
      </div>`;
  }

  // ─── Mini Subject Sparkline ───────────────────────────────
  const SUBJ_COLORS = { math:'#ff6b6b', reading:'#4ecdc4', writing:'#45b7d1', spelling:'#96ceb4', science:'#f9ca24' };

  function buildMiniChart(history, subject) {
    if (!history || history.length < 2) return '<div class="mini-empty">Play more sessions to see growth</div>';

    const W = 300, H = 48;
    const vals = history.map(h => h.acc);
    const rawMin = Math.min(...vals), rawMax = Math.max(...vals);
    const spread = Math.max(rawMax - rawMin, 8);
    const yMin = Math.max(0, rawMin - spread * 0.2);
    const yMax = Math.min(100, rawMax + spread * 0.2);

    const xS = i => (i / (vals.length - 1)) * W;
    const yS = v => H - ((v - yMin) / Math.max(yMax - yMin, 1)) * H;

    const coords = vals.map((v,i) => `${xS(i).toFixed(1)},${yS(v).toFixed(1)}`).join(' ');
    const first = vals[0], last = vals[vals.length - 1];
    const isUp = last >= first;
    const c = isUp ? '#4ecdc4' : '#ff6b6b';
    const changePct = first > 0 ? Math.round(Math.abs((last - first) / first * 100)) : 0;
    const gid = `mg_${subject}`;
    const area = `0,${H} ${coords} ${xS(vals.length-1).toFixed(1)},${H}`;

    return `
      <div class="mini-chart-row">
        <svg viewBox="0 0 ${W} ${H}" class="mini-svg" preserveAspectRatio="none">
          <defs>
            <linearGradient id="${gid}" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="${c}" stop-opacity="0.35"/>
              <stop offset="100%" stop-color="${c}" stop-opacity="0"/>
            </linearGradient>
          </defs>
          <polygon points="${area}" fill="url(#${gid})"/>
          <polyline points="${coords}" fill="none" stroke="${c}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
          <circle cx="${xS(vals.length-1).toFixed(1)}" cy="${yS(last).toFixed(1)}" r="3.5" fill="${c}"/>
        </svg>
        <div class="mini-stats">
          <span class="mini-delta ${isUp?'chart-up':'chart-down'}">${isUp?'▲':'▼'} ${changePct}%</span>
          <span class="mini-range">${Math.min(...vals)}%–${Math.max(...vals)}%</span>
        </div>
      </div>`;
  }

  // ─── IQ Bar ───────────────────────────────────────────────
  function buildIQBar(iq) {
    const pct = Math.min(100, (iq / 200) * 100);
    const barColor = iq >= 135 ? '#a78bfa' : iq >= 120 ? '#4ecdc4' : iq >= 105 ? '#7c6af7' : iq >= 90 ? '#f7d060' : '#ff6b6b';
    const desc = iq >= 145 ? 'Exceptional' : iq >= 130 ? 'Very Superior' : iq >= 120 ? 'Superior'
      : iq >= 110 ? 'Above Average' : iq >= 90 ? 'Average' : iq >= 80 ? 'Below Average' : 'Developing';
    const ticks = [70, 85, 100, 115, 130, 145, 160];
    const ticksHtml = ticks.map(v =>
      `<div class="iq-tick" style="left:${(v/200)*100}%">
         <div class="iq-tick-line ${v===100?'iq-tick-avg':''}"></div>
         <div class="iq-tick-num">${v}</div>
       </div>`).join('');
    return `
      <div class="iq-bar-wrap">
        <div class="iq-bar-top">
          <div class="iq-number-big" style="color:${barColor}">${iq}<span class="iq-denom">/200</span></div>
          <div class="iq-desc-badge" style="background:${barColor}20;color:${barColor};border-color:${barColor}40">${desc}</div>
        </div>
        <div class="iq-track">
          <div class="iq-fill" style="width:${pct}%;background:linear-gradient(90deg,${barColor}99,${barColor})"></div>
          <div class="iq-glow" style="left:${pct}%;background:${barColor}"></div>
        </div>
        <div class="iq-ticks">${ticksHtml}</div>
      </div>`;
  }

  // ─── Autosave (every 60 seconds mid-session) ─────────────
  let autosaveInterval = null;

  function getMidSessionState() {
    // Returns { score, total } of questions answered so far this session
    switch (state.subject) {
      case 'math':
      case 'science':
        return { score: state.score, total: state.currentQ };
      case 'spelling':
        return { score: state.spellingCorrect, total: state.spellingIdx };
      case 'reading': {
        const qpp = state.mode === 'practice' ? 5 : 6;
        const total = (state.passageIdx || 0) * qpp + (state.passageQIdx || 0);
        return { score: state.score, total };
      }
      case 'writing': {
        const ta = document.getElementById('writing-area');
        const words = ta ? ta.value.trim().split(/\s+/).filter(w => w.length > 0).length : 0;
        const targets = { k2:20, '35':50, '68':100, '912':150, sat:200 };
        const grp = getGradeGroup(state.grade);
        const target = targets[grp] || 50;
        const stars = words >= target ? 3 : words >= target*0.7 ? 2 : words >= target*0.4 ? 1 : 0;
        return { score: stars, total: 3 };
      }
      default:
        return { score: 0, total: 0 };
    }
  }

  function doAutosave() {
    if (!state.subject || !state.grade) return;
    const { score, total } = getMidSessionState();
    const deltaScore = score - state.autosavedScore;
    const deltaTotal = total - state.autosavedTotal;
    if (deltaTotal > 0) {
      saveResult(state.subject, state.grade, deltaScore, deltaTotal);
      state.autosavedScore = score;
      state.autosavedTotal = total;
      // Brief visual pulse on the progress button to confirm save
      const btn = document.querySelector('.btn-progress-sm');
      if (btn) {
        btn.textContent = '✓ Saved';
        setTimeout(() => { btn.textContent = '📊 Progress'; }, 1200);
      }
    }
  }

  function startAutosave() {
    stopAutosave();
    state.autosavedScore = 0;
    state.autosavedTotal = 0;
    autosaveInterval = setInterval(doAutosave, 60000);
  }

  function stopAutosave() {
    if (autosaveInterval) { clearInterval(autosaveInterval); autosaveInterval = null; }
  }

  function getSubjectLevel(subject) {
    const prog = loadProgress();
    const subj = prog[subject];
    if (!subj) return null;
    let bestIdx = -1;
    for (const g of GRADE_ORDER) {
      if (!subj[g]) continue;
      const d = subj[g];
      if (d.total < 8) continue;
      if (d.correct / d.total >= 0.65) bestIdx = GRADE_ORDER.indexOf(g);
    }
    return bestIdx >= 0 ? GRADE_ORDER[bestIdx] : null;
  }

  function getSubjectStats(subject) {
    const prog = loadProgress();
    const subj = prog[subject];
    if (!subj) return { acc: 0, sessions: 0, totalQ: 0, hasData: false };
    let correct = 0, total = 0, sessions = 0;
    for (const g of GRADE_ORDER) {
      if (!subj[g]) continue;
      correct += subj[g].correct;
      total += subj[g].total;
      sessions += subj[g].sessions;
    }
    return { acc: total > 0 ? Math.round(correct / total * 100) : 0, sessions, totalQ: total, hasData: sessions > 0 };
  }

  function getOverallLevel() {
    const subjects = ['math','reading','writing','spelling','science'];
    const indices = subjects.map(s => {
      const lv = getSubjectLevel(s);
      return lv !== null ? GRADE_ORDER.indexOf(lv) : -1;
    }).filter(i => i >= 0);
    if (!indices.length) return null;
    const avg = indices.reduce((a,b)=>a+b,0) / indices.length;
    return GRADE_ORDER[Math.max(0, Math.min(13, Math.round(avg)))];
  }

  function accToStars(acc) {
    if (acc >= 95) return 5;
    if (acc >= 85) return 4;
    if (acc >= 75) return 3;
    if (acc >= 65) return 2;
    if (acc >= 50) return 1;
    return 0;
  }

  function gradeLabel(g) {
    if (!g) return null;
    if (g === 'K') return 'Kindergarten';
    if (g === 'SAT') return 'SAT Level';
    return `Grade ${g}`;
  }

  function showProgress() {
    Audio.click();
    showScreen('screen-progress');
    renderProgress();
  }

  function renderProgress() {
    const subjects = [
      { key:'math',     name:'Math',     icon:'➕', cls:'math' },
      { key:'reading',  name:'Reading',  icon:'📖', cls:'reading' },
      { key:'writing',  name:'Writing',  icon:'✏️', cls:'writing' },
      { key:'spelling', name:'Spelling', icon:'🔤', cls:'spelling' },
      { key:'science',  name:'Science',  icon:'🔬', cls:'science' },
    ];

    const prog = loadProgress();
    const overall = getOverallLevel();
    const allStats = subjects.map(s => getSubjectStats(s.key));
    const totalSessions = allStats.reduce((a,b)=>a+b.sessions,0);
    const currentIQ = computeIQFromProg(prog);
    const history = prog.history || [];

    // ── Stock chart ──
    const chartWrap = document.getElementById('overall-level-wrap');
    chartWrap.innerHTML = `
      <div class="stock-card">
        <div class="stock-header">
          <span class="stock-title">IQ Growth</span>
          <span class="stock-sessions">${totalSessions} session${totalSessions!==1?'s':''}</span>
        </div>
        <div class="stock-chart-area">${buildStockChart(history)}</div>
      </div>`;

    // ── IQ bar + grade ──
    const iqWrap = document.getElementById('iq-bar-section');
    if (iqWrap) {
      if (currentIQ) {
        const gl = overall ? gradeLabel(overall) : null;
        iqWrap.innerHTML = `
          ${buildIQBar(currentIQ)}
          ${gl ? `<div class="prog-grade-badge">🎓 ${gl}</div>` : ''}`;
      } else {
        iqWrap.innerHTML = `<div class="no-data-msg">Complete sessions with 8+ questions to see your IQ and grade</div>`;
      }
    }

    // ── Subject cards ──
    const subjectHistory = prog.subjectHistory || {};
    const cardsEl = document.getElementById('progress-cards');
    cardsEl.innerHTML = subjects.map(s => {
      const level = getSubjectLevel(s.key);
      const stats = getSubjectStats(s.key);
      const stars = accToStars(stats.acc);
      const starsHtml = [1,2,3,4,5].map(i =>
        `<span class="pstar ${i<=stars?'pstar-lit':'pstar-dim'}">★</span>`).join('');
      const lbl = level ? gradeLabel(level) : (stats.hasData ? 'Keep practicing!' : 'No sessions yet');
      const hist = subjectHistory[s.key] || [];
      const miniChart = buildMiniChart(hist, s.key);
      return `
        <div class="prog-card prog-subj-${s.cls} ${hist.length >= 2 ? 'prog-card-has-chart' : ''}">
          <div class="prog-card-top">
            <div class="prog-left">
              <span class="prog-icon">${s.icon}</span>
              <div class="prog-meta">
                <div class="prog-name">${s.name}</div>
                <div class="prog-level-lbl ${level?'prog-level-has':''}">${lbl}</div>
              </div>
            </div>
            <div class="prog-right">
              <div class="prog-stars">${starsHtml}</div>
              ${stats.hasData
                ? `<div class="prog-stat">${stats.acc}% · ${stats.sessions} session${stats.sessions!==1?'s':''}</div>`
                : '<div class="prog-stat">—</div>'}
            </div>
          </div>
          ${hist.length >= 2 ? `<div class="prog-chart-section">${miniChart}</div>` : ''}
        </div>`;
    }).join('');
  }

  function confirmClearProgress() {
    Audio.click();
    const modal = document.getElementById('modal');
    document.getElementById('modal-title').textContent = 'Reset Progress?';
    document.getElementById('modal-msg').textContent = 'This will delete ALL your ratings and session history. This cannot be undone.';
    const ok = document.getElementById('modal-ok');
    ok.textContent = 'Yes, Reset';
    ok.onclick = () => {
      closeModal();
      try { localStorage.removeItem(PROGRESS_KEY); } catch(e) {}
      ok.textContent = 'Yes, Exit';
      renderProgress();
    };
    modal.classList.remove('hidden');
  }

  // ─── Modal ────────────────────────────────────────────────
  function confirmExit() {
    Audio.click();
    const modal = document.getElementById('modal');
    const ok = document.getElementById('modal-ok');
    document.getElementById('modal-title').textContent = 'Exit Session?';
    document.getElementById('modal-msg').textContent = 'Your progress in this session will be lost.';
    ok.onclick = () => { closeModal(); stopAllTimers(); showSubjectSelect(); };
    modal.classList.remove('hidden');
  }

  function closeModal() {
    document.getElementById('modal').classList.add('hidden');
  }

  function stopAllTimers() {
    stopTimer();
    stopSpellingTimers();
    stopWritingTimer();
    stopAutosave();
  }

  // ─── Stars background ─────────────────────────────────────
  function createStars() {
    const bg = document.getElementById('star-bg');
    if (!bg) return;
    bg.innerHTML = '';
    for (let i = 0; i < 80; i++) {
      const star = document.createElement('div');
      star.className = 'star-dot';
      star.style.left = Math.random() * 100 + '%';
      star.style.top = Math.random() * 100 + '%';
      star.style.animationDelay = (Math.random() * 3) + 's';
      star.style.width = star.style.height = (Math.random() * 3 + 1) + 'px';
      bg.appendChild(star);
    }
  }

  // ─── Public API ───────────────────────────────────────────
  return {
    showWelcome, showGradeSelect, showSubjectSelect,
    showModeSelect,
    selectSubject,
    startSession,
    answerMath,
    answerScience,
    answerReading,
    startReadingQuestions,
    submitWriting,
    speakCurrentWord,
    submitSpelling,
    playAgain,
    confirmExit,
    closeModal,
    showProgress,
    confirmClearProgress,
    openApiKeySettings,
    promptName,
    showStore,
    buyGame,
    playGame,
    exitGame,
    flipCard,
    servePizza,
    shootArrow,
    showLevelSetup,
    setLtRounding,
    setLtStart,
    beginLevelTest,
    answerLT,
    renderLTQuestion,
    confirmLtExit,
  };
})();

// Kick off on load
window.addEventListener('load', () => {
  App.showWelcome();
});
