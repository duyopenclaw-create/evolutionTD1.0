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
      autosavedScore: 0,  // how much has already been persisted this session
      autosavedTotal: 0,
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
    // Append IQ snapshot to history for the stock chart
    if (!prog.history) prog.history = [];
    const iq = computeIQFromProg(prog);
    if (iq) {
      prog.history.push({ ts: Date.now(), iq, subject });
      if (prog.history.length > 200) prog.history = prog.history.slice(-200);
    }
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
    const cardsEl = document.getElementById('progress-cards');
    cardsEl.innerHTML = subjects.map(s => {
      const level = getSubjectLevel(s.key);
      const stats = getSubjectStats(s.key);
      const stars = accToStars(stats.acc);
      const starsHtml = [1,2,3,4,5].map(i =>
        `<span class="pstar ${i<=stars?'pstar-lit':'pstar-dim'}">★</span>`).join('');
      const lbl = level ? gradeLabel(level) : (stats.hasData ? 'Keep practicing!' : 'No sessions yet');
      const accBar = stats.hasData ? `<div class="prog-acc-bar"><div class="prog-acc-fill" style="width:${stats.acc}%"></div></div>` : '';
      return `
        <div class="prog-card prog-subj-${s.cls}">
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
              ? `<div class="prog-stat">${stats.acc}% · ${stats.sessions} session${stats.sessions!==1?'s':''}</div>
                 ${accBar}`
              : '<div class="prog-stat">—</div>'}
          </div>
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
