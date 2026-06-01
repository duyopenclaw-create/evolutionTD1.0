// ============================================================
//  LearningSAT+ Data
// ============================================================

// Map grades to content groups
const GRADE_GROUP = {
  'K':'k2','1':'k2','2':'k2',
  '3':'35','4':'35','5':'35',
  '6':'68','7':'68','8':'68',
  '9':'912','10':'912','11':'912','12':'912',
  'SAT':'sat'
};

// ─────────────────────────────────────────
//  MATH PROBLEM GENERATOR
// ─────────────────────────────────────────
function rnd(a,b){ return Math.floor(Math.random()*(b-a+1))+a; }

// Build a problem — places correct answer at a truly random position, deduplicates all choices
function mp(question, correct, w1, w2, w3) {
  const ans = String(correct);
  const seen = new Set([ans]);
  const wrongs = [];
  for (const w of [w1, w2, w3]) {
    const ws = String(w);
    if (!seen.has(ws)) { seen.add(ws); wrongs.push(ws); }
  }
  // Fill to 3 unique wrongs if candidates were duplicates
  const num = Number(correct);
  let fill = 1;
  while (wrongs.length < 3) {
    const cand = !isNaN(num) ? String(num + fill) : `${correct}(${fill})`;
    if (!seen.has(cand)) { seen.add(cand); wrongs.push(cand); }
    fill++;
  }
  // Place correct answer at a uniformly random position 0–3
  const pos = Math.floor(Math.random() * 4);
  const choices = [...wrongs];
  choices.splice(pos, 0, ans);
  return { question, answer: ans, choices };
}

function generateMathProblem(grade, isTest=false) {

  // ── Kindergarten ─────────────────────────────────────────
  // Sums/differences within 10. Wrong answers are ±1 or ±2.
  if (grade === 'K') {
    const ops = [
      () => { const a=rnd(1,5),b=rnd(1,5); return mp(`${a} + ${b} = ?`, a+b, a+b+1, a+b-1<0?a+b+2:a+b-1, a+b+2); },
      () => { const s=rnd(3,10),b=rnd(1,s-1); return mp(`${s} − ${b} = ?`, s-b, s-b+1, s-b+2, s-b-1<0?s-b+3:s-b-1); },
      () => { const a=rnd(1,9); return mp(`__ + 1 = ${a+1}`, a, a+1, a+2, a-1<0?a+3:a-1); },
      () => { const a=rnd(2,8); return mp(`${a} − 1 = ?`, a-1, a, a+1, a-2<0?a+1:a-2); },
      () => { const a=rnd(1,9); return mp(`${a} + 0 = ?`, a, a+1, a-1<0?a+2:a-1, 0); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 1 ────────────────────────────────────────────
  // Add/subtract within 20, skip counting, missing addend
  if (grade === '1') {
    const ops = [
      () => { const a=rnd(5,12),b=rnd(3,8); return mp(`${a} + ${b} = ?`, a+b, a+b+1, a+b-1, a+b+2); },
      () => { const s=rnd(11,18),b=rnd(3,9); return mp(`${s} − ${b} = ?`, s-b, s-b+1, s-b+2, s-b-1<0?s-b+3:s-b-1); },
      () => { const a=rnd(1,14),b=rnd(1,6); return mp(`${a} + ? = ${a+b}`, b, b+1, b-1<0?b+2:b-1, b+2); },
      () => { const a=rnd(2,10); return mp(`Count by 2s: ${a}, ${a+2}, ${a+4}, __ = ?`, a+6, a+5, a+7, a+8); },
      () => { const a=rnd(1,9); return mp(`Which is GREATER: ${a} or ${a+rnd(1,5)}?`, a+rnd(1,5), a, 'They are equal', a-1<0?a+1:a-1); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 2 ────────────────────────────────────────────
  // 2-digit add/subtract, intro multiplication (2s, 5s, 10s)
  if (grade === '2') {
    const ops = [
      () => { const a=rnd(15,55),b=rnd(15,40); return mp(`${a} + ${b} = ?`, a+b, a+b+10, a+b-10, a+b+1); },
      () => { const s=rnd(40,90),b=rnd(11,35); return mp(`${s} − ${b} = ?`, s-b, s-b+10, s-b-10, s-b+1); },
      () => { const a=rnd(2,6); return mp(`${a} × 2 = ?`, a*2, a*2+2, a*2-2, a*2+1); },
      () => { const a=rnd(2,9); return mp(`${a} × 5 = ?`, a*5, a*5+5, a*5-5, a*5+1); },
      () => { const a=rnd(2,9); return mp(`${a} × 10 = ?`, a*10, a*10+10, a*10-10, a); },
      () => { const a=rnd(20,60),b=rnd(10,30); return mp(`What is ${a} + ${b}? Round to nearest 10: ?`, Math.round((a+b)/10)*10, Math.round((a+b)/10)*10+10, Math.round((a+b)/10)*10-10, a+b); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 3 ────────────────────────────────────────────
  // Multiplication tables 1–12, division, unit fractions
  if (grade === '3') {
    const ops = [
      () => { const a=rnd(2,12),b=rnd(2,12); return mp(`${a} × ${b} = ?`, a*b, a*b+a, a*b-a, a*b+b); },
      () => { const a=rnd(2,9),b=rnd(2,9); return mp(`${a*b} ÷ ${b} = ?`, a, a+1, a-1<0?a+2:a-1, a+2); },
      () => { const d=rnd(2,8); const whole=d*rnd(2,6); return mp(`What is 1/${d} of ${whole}?`, whole/d, whole/d+1, whole/d+d, whole/d-1<0?whole/d+2:whole/d-1); },
      () => { const a=rnd(3,12),b=rnd(3,12); return mp(`${b} × ${a} = ? (same as ${a} × ${b})`, a*b, a*b+b, a*b-a, a+b); },
      () => { const a=rnd(2,9); return mp(`${a} × 0 = ?`, 0, a, 1, a+1); },
      () => { const a=rnd(24,99); const b=rnd(2,4); const q=Math.floor(a/b); const r=a%b; if(r===0) return mp(`${a} ÷ ${b} = ?`, q, q+1, q-1, q+2); return mp(`${b*q} ÷ ${b} = ?`, q, q+1, q-1<0?q+2:q-1, b); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 4 ────────────────────────────────────────────
  // 2-digit × 2-digit, division with remainders, decimals, comparing fractions
  if (grade === '4') {
    const ops = [
      () => { const a=rnd(11,25),b=rnd(11,25); return mp(`${a} × ${b} = ?`, a*b, a*b+a, a*b+b, a*b-a); },
      () => { const q=rnd(10,30),d=rnd(3,9); return mp(`${q*d} ÷ ${d} = ?`, q, q+1, q-1<0?q+2:q-1, q+d); },
      () => { const a=rnd(1,8),b=rnd(1,8); return mp(`${a}.${b} + 1.0 = ?`, a+1+'.'+b, a+'.'+b, a+2+'.'+b, a+1+'.'+(b+1>9?0:b+1)); },
      () => { const n=rnd(2,7); return mp(`Which fraction is LARGER: ${n}/${n+1} or 1/2?`, `${n}/${n+1}`, '1/2', 'They are equal', `1/${n}`); },
      () => { const a=rnd(100,400),b=rnd(20,80); return mp(`${a} ÷ ${b} ≈ ? (round to nearest whole)`, Math.round(a/b), Math.round(a/b)+1, Math.round(a/b)-1<0?Math.round(a/b)+2:Math.round(a/b)-1, Math.round(a/b)+2); },
      () => { const a=rnd(2,6),b=a+rnd(1,4); return mp(`${a}/8 + ${b}/8 = ? /8 (enter numerator)`, a+b, a+b+1, a+b-1, a+b+2); },
      () => { const h=isTest?rnd(15,30):rnd(10,20), w=isTest?rnd(12,25):rnd(8,18); return mp(`Perimeter of rectangle: length=${h}, width=${w}. P = ?`, 2*(h+w), h+w, 2*h+w, h*w > 200 ? 2*(h+w)+4 : h*w); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 5 ────────────────────────────────────────────
  // Fraction ops, decimal mult/div, order of operations, exponents, volume
  if (grade === '5') {
    const ops = [
      () => { const d=rnd(3,8); const n1=rnd(1,d-1),n2=rnd(1,d-1); const sum=n1+n2; return mp(`${n1}/${d} + ${n2}/${d} = ?/${d} — enter the numerator`, sum >= d ? sum : sum, sum+1, sum-1<0?sum+2:sum-1, sum+d); },
      () => { const a=rnd(2,8),b=rnd(2,5); return mp(`${a} + ${b} × 3 = ? (order of operations)`, a+b*3, (a+b)*3, a+b+3, a*3+b); },
      () => { const b=rnd(2,5); return mp(`${b}³ = ? (${b} to the 3rd power)`, b*b*b, b*b, b*b*b+b, b*3); },
      () => { const l=rnd(3,8),w=rnd(3,7),h=rnd(2,6); return mp(`Volume of box: ${l} × ${w} × ${h} = ?`, l*w*h, l*w+h, l+w+h, l*w*h+l); },
      () => { const a=rnd(2,9),b=rnd(2,5); const dec=parseFloat((a/b).toFixed(1)); return mp(`${a} ÷ ${b} ≈ ? (to 1 decimal)`, dec, parseFloat((dec+0.5).toFixed(1)), parseFloat((dec-0.5<0?dec+1:dec-0.5).toFixed(1)), parseFloat((dec+1).toFixed(1))); },
      () => { const p=rnd(10,50)*2; return mp(`${p}% of 200 = ?`, p*2, p, p*2+10, p*2-10); },
    ];
    return ops[rnd(0,ops.length-1)]();
  }

  // ── Grade 6 ────────────────────────────────────────────
  // Ratios, percents, integers, one-step equations, unit rates
  if (grade === '6') {
    const ops = [
      () => { const x=rnd(3,15),add=rnd(5,20); return mp(`Solve: x + ${add} = ${x+add}. x = ?`, x, x+1, x+add, x-1<0?x+2:x-1); },
      () => { const x=rnd(3,15),sub=rnd(2,10); if(x<=sub) return ops[0](); return mp(`Solve: x − ${sub} = ${x-sub}. x = ?`, x, x+sub, x-sub, x+1); },
      () => { const p=rnd(1,9)*10; const base=rnd(2,9)*10; return mp(`${p}% of ${base} = ?`, p*base/100, p*base/100+p, p*base/100-p, base/10); },
      () => { const neg=rnd(1,9),pos=rnd(neg+1,15); return mp(`−${neg} + ${pos} = ?`, pos-neg, pos+neg, neg-pos, -(pos-neg)); },
      () => { const neg=rnd(1,8),neg2=rnd(1,8); return mp(`−${neg} − ${neg2} = ?`, -(neg+neg2), neg+neg2, neg-neg2, -(neg-neg2)); },
      () => { const rate=rnd(4,12),hrs=rnd(2,8); return mp(`A worker earns $${rate}/hour. In ${hrs} hours, total = $?`, rate*hrs, rate+hrs, rate*hrs+rate, rate*hrs-rate); },
      () => { const a=rnd(2,8),b=rnd(2,8); return mp(`Ratio ${a}:${b}. If first quantity = ${a*rnd(2,5)}, second = ?`, (()=>{const m=rnd(2,5);return mp(`Ratio ${a}:${b}. If first = ${a*m}, second = ?`, b*m, b*m+b, b*m-b, a*m).answer;})(), b+1, b-1<0?b+2:b-1, a+b); },
    ];
    // simpler version of ratio problem to avoid nested closure
    const m6=rnd(2,5),a6=rnd(2,8),b6=rnd(2,8);
    const ratioP = mp(`Ratio ${a6}:${b6}. If first quantity = ${a6*m6}, second quantity = ?`, b6*m6, b6*m6+b6, b6*m6-b6<0?b6*m6+b6*2:b6*m6-b6, a6*m6);
    const pool = [
      mp(`Solve: x + ${rnd(5,20)} = ${rnd(3,15)+rnd(5,20)}. x = ?`, (()=>{const x=rnd(3,15),add=rnd(5,20);return [x,add];})(),(()=>{const x=rnd(3,15),add=rnd(5,20);return x;})(),(()=>{const x=rnd(3,15),add=rnd(5,20);return x+1;})(),(()=>{const x=rnd(3,15),add=rnd(5,20);return x+add;})()),
    ];
    // Use clean ops array
    const g6ops = (() => {
      const x=rnd(3,15),add=rnd(5,20);
      const p=rnd(1,9)*10, base=rnd(2,9)*10;
      const neg=rnd(1,9),pos=rnd(neg+1,15);
      const rate=rnd(4,12),hrs=rnd(2,8);
      return [
        mp(`Solve: x + ${add} = ${x+add}. x = ?`, x, x+add, x+1, add),
        mp(`${p}% of ${base} = ?`, p*base/100, base/p, p+base, p*base/100+p),
        mp(`−${neg} + ${pos} = ?`, pos-neg, -(pos+neg), pos+neg, neg-pos),
        mp(`Earn $${rate}/hour. In ${hrs} hours, total = $?`, rate*hrs, rate+hrs, rate*(hrs+1), rate*hrs-rate),
        ratioP,
      ];
    })();
    return g6ops[rnd(0,g6ops.length-1)];
  }

  // ── Grade 7 ────────────────────────────────────────────
  // Two-step equations, percent change, geometry, statistics
  if (grade === '7') {
    const x7=rnd(2,10), m7=rnd(2,5), b7=rnd(2,12);
    const l7=rnd(5,16),w7=rnd(3,10);
    const nums7=[rnd(4,20),rnd(4,20),rnd(4,20),rnd(4,20),rnd(4,20)];
    const sum7=nums7.reduce((a,b)=>a+b,0);
    const ops7=[
      mp(`Solve: ${m7}x + ${b7} = ${m7*x7+b7}. x = ?`, x7, x7+1, x7+b7, m7*x7+b7),
      mp(`Solve: ${m7}x − ${b7} = ${m7*x7-b7}. x = ?`, x7, x7+m7, x7-1<0?x7+2:x7-1, m7*x7),
      mp(`Area of triangle: base=${l7}, height=${w7}. Area = ?`, (l7*w7)/2, l7*w7, l7+w7, l7*w7/2+w7),
      mp(`Mean of [${nums7.join(', ')}] = ?`, Math.round(sum7/5), Math.round(sum7/5)+2, Math.round(sum7/5)-2, Math.round(sum7/4)),
      (()=>{const orig=rnd(50,100)*2,pct=rnd(1,4)*10; return mp(`Price: $${orig}. Increases ${pct}%. New price = $?`, orig*(1+pct/100), orig+pct, orig*(1+pct/100)+orig*0.1, orig*(1+pct/100)-orig*0.1); })(),
      (()=>{const neg=rnd(1,10); const pos=rnd(neg+1,20); return mp(`${pos} − ${neg+pos} = ?`, -neg, neg, -(neg+pos), neg+1); })(),
    ];
    return ops7[rnd(0,ops7.length-1)];
  }

  // ── Grade 8 ────────────────────────────────────────────
  // Slope, linear equations, systems, Pythagorean theorem, scientific notation
  if (grade === '8') {
    const triples = [[3,4,5],[5,12,13],[6,8,10],[8,15,17],[9,12,15]];
    const tr = triples[rnd(0,triples.length-1)];
    const x8=rnd(1,10), m8=rnd(2,6), b8=rnd(2,15);
    const ops8=[
      mp(`Solve: ${m8}x + ${b8} = ${m8*x8+b8}. x = ?`, x8, x8+1, x8-1<0?x8+2:x8-1, m8+b8),
      mp(`Right triangle: legs ${tr[0]} and ${tr[1]}. Hypotenuse = ?`, tr[2], tr[2]+1, tr[0]+tr[1], tr[2]-1),
      (()=>{const x1=rnd(0,4),y1=rnd(0,8),run=rnd(2,5),rise=rnd(1,6); return mp(`Slope through (${x1},${y1}) and (${x1+run},${y1+rise}): rise/run = ?/${run}. Slope = ?/${run} — enter numerator`, rise, rise+1, rise-1<0?rise+2:rise-1, run); })(),
      (()=>{const base=rnd(2,9); const exp=rnd(2,4); return mp(`${base}² = ? ${isTest?'(watch out — not ×2)':''}`, base*base, base*2, base*base+base, base*base-base); })(),
      (()=>{const a=rnd(2,8); return mp(`√${a*a} = ?`, a, a+1, a*a, a-1<0?a+2:a-1); })(),
      (()=>{const x=rnd(1,9); return mp(`Solve the system: x + y = ${x+rnd(2,8)}, x − y = ${x-rnd(1,x-1<1?2:x-1)}. Find x+y by substitution: x = ?`, x, x+1, x-1<0?x+2:x-1, x+2); })(),
    ];
    return ops8[rnd(0,ops8.length-1)];
  }

  // ── Grade 9 (Algebra 1/2) ─────────────────────────────
  // Quadratics, factoring, functions, polynomials
  if (grade === '9') {
    const r1=rnd(1,7), r2=rnd(1,7);
    const x9=rnd(1,8), m9=rnd(1,4);
    const ops9=[
      mp(`x² − ${r1+r2}x + ${r1*r2} = 0. One solution: x = ?`, r1, r2===r1?r1+1:r2, r1+r2, r1*r2),
      mp(`Solve: x² = ${r1*r1}. Positive solution: x = ?`, r1, r1+1, r1*r1, r1-1<0?r1+2:r1-1),
      mp(`f(x) = ${m9}x + ${rnd(1,8)}. f(${x9}) = ?`, (()=>{const c=rnd(1,8);return mp(`f(x)=${m9}x+${c}. f(${x9})=?`,m9*x9+c,m9*x9+c+m9,m9*x9+c-m9,m9*(x9+1)+c).answer;})(), m9*x9, x9+m9, m9+x9+1),
      (()=>{const a=rnd(2,6),b=rnd(1,8); return mp(`Expand (x+${a})(x+${b}). Middle coefficient (x term) = ?`, a+b, a*b, a-b<0?b-a:a-b, a+b+1); })(),
      (()=>{const m=rnd(1,5),b=rnd(1,10); return mp(`y = ${m}x − ${b}. When y = 0, x = ? (x-intercept)`, b/m===Math.floor(b/m)?b/m:-999, b/m===Math.floor(b/m)?b/m+1:-998, b, m); })(),
      (()=>{const c=rnd(1,8); const a=rnd(1,4); return mp(`${a}x² + 0x − ${a*c*c} = 0. Positive solution: x = ?`, c, c+1, c-1<0?c+2:c-1, a*c); })(),
    ].filter(p=>p.answer!=='-999'&&p.answer!=='-998');
    // fallback safe problems
    const safe=[
      mp(`x² − ${r1+r2}x + ${r1*r2} = 0. One solution: x = ?`, r1, r2===r1?r1+1:r2, r1+r2, r1*r2),
      mp(`Solve: x² = ${r1*r1}. Positive solution: x = ?`, r1, r1+1, r1*2, r1*r1),
    ];
    const pool9=[...ops9,...safe];
    return pool9[rnd(0,pool9.length-1)];
  }

  // ── Grade 10 (Geometry/Trig) ──────────────────────────
  // Sin/cos/tan, circle area/arc, coordinate geometry
  if (grade === '10') {
    const ops10=[
      mp(`sin(30°) = ? (as a fraction — enter denominator: it is 1/2, so denominator = ?)`, 2, 3, 4, 1),
      mp(`cos(60°) = 1/2. True or False?`, 'True', 'False', 'Only for right triangles', 'Depends on the triangle'),
      mp(`tan(45°) = ?`, 1, 0, 2, '√2'),
      (()=>{const r=rnd(3,9); return mp(`Area of circle, r=${r}. Use π≈3.14. Area ≈ ?`, Math.round(3.14*r*r), Math.round(3.14*r*r)+Math.round(3.14*r), Math.round(3.14*r*r*2), Math.round(2*3.14*r)); })(),
      (()=>{const r=rnd(4,10); return mp(`Circumference of circle, r=${r}. C = 2πr ≈ ? (use π≈3.14)`, Math.round(2*3.14*r), Math.round(3.14*r*r), r*2, Math.round(3.14*r)); })(),
      (()=>{const m=rnd(1,5),b=rnd(1,10),x1=rnd(1,8),x2=x1+rnd(1,5); return mp(`Line y=${m}x+${b}: x-intercept (set y=0) — solve 0=${m}x+${b}, x = ?`, -b/m===Math.floor(-b/m)?-b/m:-999, -b/m===Math.floor(-b/m)?-b/m+1:-998, b, m); })(),
      mp(`Two parallel lines cut by a transversal. One angle = 65°. The CO-INTERIOR (same-side interior) angle = ?°`, 115, 65, 180, 90),
      mp(`In a 30-60-90 triangle, if the short leg = 5, the hypotenuse = ?`, 10, 5, 15, '5√3'),
    ].filter(p=>p.answer!=='-999'&&p.answer!=='-998');
    return ops10[rnd(0,ops10.length-1)];
  }

  // ── Grade 11 (Algebra 2 / Pre-Calc) ──────────────────
  // Logs, sequences, exponential equations, trig identities
  if (grade === '11') {
    const ops11=[
      (()=>{const base=rnd(2,5),exp=rnd(2,5); return mp(`log${base}(${Math.pow(base,exp)}) = ?`, exp, exp+1, exp-1<0?exp+2:exp-1, base); })(),
      (()=>{const x=rnd(2,6); return mp(`log₂(${Math.pow(2,x)}) = ?`, x, x+1, x-1<0?x+2:x-1, Math.pow(2,x)); })(),
      (()=>{const x=rnd(1,5); return mp(`2^x = ${Math.pow(2,x)}. x = ?`, x, x+1, x-1<0?x+2:x-1, Math.pow(2,x)); })(),
      (()=>{const first=rnd(2,8),d=rnd(2,6),n=isTest?8:6; return mp(`Arithmetic sequence: first=${first}, d=${d}. ${n}th term = ?`, first+(n-1)*d, first+n*d, first+(n-1)*d+1, first+n*d-d+1); })(),
      (()=>{const first=rnd(2,4),r=rnd(2,3); return mp(`Geometric sequence: ${first}, ${first*r}, ${first*r*r}, next term = ?`, first*r*r*r, first*r*r*r+first, first*r*r, first*r*r*r*r); })(),
      mp(`Evaluate: sin²(30°) + cos²(30°) = ?`, 1, 0, '1/2', 2),
      (()=>{const n=rnd(4,8); return mp(`Sum of arithmetic series: first=${rnd(1,5)}, last=${rnd(20,40)}, ${n} terms. Sum = n/2 × (first+last). If first=3, last=19, n=9. Sum = ?`, 99, 108, 9*3, 9*19); })(),
    ];
    return ops11[rnd(0,ops11.length-1)];
  }

  // ── Grade 12 (Pre-Calc / Stats) ───────────────────────
  // Combinations, probability, limits, statistics
  if (grade === '12') {
    const fact = f => f<=1?1:f*fact(f-1);
    const ops12=[
      (()=>{const n=rnd(4,8),r=rnd(2,Math.min(4,n-1)); const ans=fact(n)/(fact(r)*fact(n-r)); return mp(`C(${n},${r}) = ? (combinations)`, ans, ans+n, ans-r<0?ans+r:ans-r, fact(n)/fact(r)); })(),
      (()=>{const p=rnd(2,6); return mp(`P(event) = 1/${p}. P(NOT event) = ?`, `${p-1}/${p}`, `1/${p}`, `${p}/${p-1}`, '1'); })(),
      (()=>{const x=rnd(2,6); return mp(`lim x→${x} of (x²−${x*x})/(x−${x}) = ? [L'Hopital or factor]`, 2*x, x, x*x, 2*x+1); })(),
      (()=>{const vals=[rnd(60,80),rnd(60,80),rnd(60,80),rnd(60,80),rnd(60,80)]; const m=Math.round(vals.reduce((a,b)=>a+b)/5); return mp(`Mean of [${vals.join(', ')}] = ?`, m, m+5, m-5, m+1); })(),
      mp(`P(A) = 0.3, P(B) = 0.4, independent. P(A AND B) = ?`, '0.12', '0.7', '0.34', '0.12+0.7'),
      (()=>{const base=rnd(2,4),exp=rnd(3,5); return mp(`${base}^${exp} = ?`, Math.pow(base,exp), Math.pow(base,exp)+base, base*exp, Math.pow(base,exp-1)); })(),
    ];
    return ops12[rnd(0,ops12.length-1)];
  }

  // ── SAT ──────────────────────────────────────────────
  // Multi-step problems requiring 2+ operations. Genuinely hard.
  const satPool = [
    // Consecutive integers
    (()=>{const start=rnd(4,20)*2; return mp(`Three consecutive even integers sum to ${start*3+6}. Largest integer = ?`, start+4, start+2, start+6, start+3); })(),
    // Rectangle with constraints
    (()=>{const w=rnd(5,12),extra=rnd(2,6); const l=2*w+extra; const P=2*(l+w); return mp(`Rectangle: length is ${extra} more than twice the width. Perimeter = ${P}. Width = ?`, w, w+1, w-1<0?w+2:w-1, l); })(),
    // Markup/discount
    (()=>{const cost=rnd(20,80)*5; const markup=rnd(1,4)*25; const price=cost*(1+markup/100); return mp(`Item costs $${cost}. Sold at ${markup}% markup. Selling price = $?`, price, cost+markup, price+cost*0.1, price-cost*0.1); })(),
    // Percent decrease
    (()=>{const orig=rnd(8,20)*10; const pct=rnd(1,4)*10; return mp(`A population of ${orig} decreases by ${pct}%. New population = ?`, orig*(1-pct/100), orig-pct, orig*(pct/100), orig+orig*(pct/100)); })(),
    // System of equations — find x+y
    (()=>{const x=rnd(3,8),y=rnd(3,8); return mp(`System: 2x + y = ${2*x+y}, x + 2y = ${x+2*y}. Find x: solve by substitution. x = ?`, x, y, x+y, x-1<0?x+2:x-1); })(),
    // Quadratic word problem: height function
    (()=>{const v=rnd(2,6)*8; const peak=v*v/64; return mp(`Ball thrown up: h = −16t² + ${v}t (feet). Maximum height = ? feet`, peak, peak*2, v, peak+16); })(),
    // Compound interest
    mp(`$${2000} at 5% annual interest, compounded yearly for 2 years. Final = $?`, 2205, 2200, 2210, 2100),
    // Age problem
    (()=>{const now=rnd(8,20),diff=rnd(3,10); return mp(`Sam is ${now}. In ${diff} years, Sam will be ${now+diff}. Now Sam is ${diff} years older than Alex. Alex is now ?`, now-diff, now, now+diff, diff); })(),
    // Ratio problem
    (()=>{const total=rnd(3,7)*8; const partA=rnd(2,5); const partB=rnd(2,5); const share=Math.round(total*partB/(partA+partB)); return mp(`${total} items split in ratio ${partA}:${partB}. Larger share = ?`, Math.max(Math.round(total*partA/(partA+partB)),share), Math.min(Math.round(total*partA/(partA+partB)),share), total/2, partB); })(),
    // Absolute value
    (()=>{const c=rnd(3,8); return mp(`|x − ${c}| = 3. The TWO solutions are x = ${c+3} and x = ?`, c-3, c+3, c, 3); })(),
    // Exponent equation
    (()=>{const base=rnd(2,4),exp=rnd(2,5); return mp(`${base}^x = ${Math.pow(base,exp)}. x = ?`, exp, exp+1, exp-1<0?exp+2:exp-1, base*exp); })(),
    // Quadratic — vertex x-coordinate
    (()=>{const h=rnd(2,7),k=rnd(5,20); return mp(`Parabola: y = (x−${h})² + ${k}. Vertex x-coordinate = ?`, h, k, h+1, h-1<0?h+2:h-1); })(),
    // Data: median vs mean
    mp(`Data set: 3, 7, 7, 9, 14. Mean = 8. Median = ?`, 7, 8, 9, 6),
    // Probability
    (()=>{const good=rnd(3,8),total=good+rnd(4,10); return mp(`Bag has ${good} red and ${total-good} blue marbles. P(red) = ${good}/${total}. If doubled, P(red) = ?`, `${good}/${total}`, `${good*2}/${total*2}`, `${good+1}/${total}`, '1/2'); })(),
    // Solve for variable in formula
    (()=>{const r=rnd(3,9),t=rnd(2,5); return mp(`d = rt. d=${r*t}, t=${t}. r = ?`, r, r+1, r*t, t); })(),
  ].filter(Boolean);

  return satPool[rnd(0,satPool.length-1)];
}

// ─────────────────────────────────────────
//  SPELLING WORDS
// ─────────────────────────────────────────
const SPELLING = {
  'K': ['cat','dog','sun','run','big','hat','sit','cup','red','mom','dad','fun','hot','top','pin','map','bag','net','fog','bus'],
  '1': ['about','after','again','also','away','back','ball','call','came','come','down','each','fell','fish','from','give','good','have','help','here','him','home','into','just','keep','kind','left','like','look','made','make','more','most','much','name','next','nice','noon','open','over','play','said','some','soon','stop','take','then','them','they','this','time','town','upon','very','walk','want','well','when','will','with','yard'],
  '2': ['almost','already','because','between','brought','careful','caught','change','children','complete','country','decide','different','enough','family','father','friend','giant','group','heavy','important','instead','large','letter','listen','money','mother','nothing','number','often','other','people','person','picture','place','please','pretty','quick','quite','really','reason','school','second','sister','should','small','sound','spell','story','stump','thought','three','together','usually','water','where','which','while','world','young','every'],
  '3': ['adventure','against','already','although','amount','animal','another','answer','around','beautiful','became','believe','beyond','billion','bother','brought','cabinet','capital','careful','caught','chapter','circle','climate','coach','completely','consider','correct','danger','decide','describe','different','divide','especially','evening','example','exercise','explain','factory','finally','follow','forgot','forward','fraction','garden','gather','general','happen','history','however','include','inside','instead','island','itself','journal','knowing','language','library','machine','measure','middle','million','minute','moment','natural','neighbor','neither','notice','number','often','outside','perhaps','picture','planet','practice','problem','produce','product','protect','provide','purpose','quarter','quickly','really','reason','recent','record','regular','remain','remove','report','result','review','science','season','second','section','sentence','several','similar','simple','single','soldier','special','square','statement','straight','strong','subject','supply','suppose','system','teacher','thought','through','together','toward','trouble','usually','valley','variety','village','whether','whole','without','wonder','world'],
  '4': ['accomplish','accurate','achieve','analyze','ancient','anxious','apparent','appreciate','argument','attention','audience','authority','available','average','awkward','beginning','behavior','beneath','boundary','breathe','calendar','campaign','candidate','capacity','challenge','character','confident','consequence','continent','continuous','criticize','definitely','desperate','develop','difference','disappear','discipline','discover','discussion','distinguish','education','elaborate','eliminate','embarrass','emphasis','enthusiasm','environment','essential','evaluate','evidence','excellent','excitement','experience','explanation','extraordinary','familiar','fascinating','February','fortunate','frequent','gracious','guarantee','guidance','humorous','identify','ignorant','immediate','important','improvement','individual','influence','innocent','intelligence','January','judgment','knowledge','language','leadership','magnificent','maintain','management','material','medicine','memory','misconduct','mysterious','necessary','neighbor','nervous','numerous','opportunity','original','parallelism','participation','particular','peculiar','permanent','personal','physical','popular','possession','precious','preference','preparation','privilege','probably','professor','promotion','proportion','psychology','quotient','realistic','recognize','recommend','responsible','restaurant','ridiculous','sacrifice','scientist','sentence','September','significant','similar','solution','source','strength','structure','successful','sufficient','suggestion','summary','surprise','technical','temporary','tradition','understanding','unusual','valuable','varieties','vegetables','volunteer','Wednesday','weighing'],
  '5': ['abbreviate','absolute','accumulate','acknowledgment','adjacent','administration','adverse','aggregate','allegiance','alliteration','allusion','ambiguous','anonymous','anticipate','apologize','approximately','argument','arithmetic','assistance','astonish','attorney','authentic','beneficial','bibliography','bizarre','catastrophe','circumstance','civilization','collaborate','commemorate','commodity','communicated','comparison','competent','complication','comprehension','concentrate','conscience','consciousness','consecutive','controversy','convenient','coordinate','correspond','courageous','criticism','curiosity','deceive','declaration','definite','demonstration','descendant','desperately','determination','diagonal','disapprove','discouragement','editorial','elaborate','emergency','emigrate','encyclopedia','enthusiasm','equivalent','eventually','exaggerate','exceed','exquisite','extraordinary','flamboyant','government','guarantee','hereditary','hypothesis','illustrious','immigrant','impartial','independence','indigenous','inevitable','influence','initiative','innumerable','integrity','investigate','legislature','legitimate','lieutenant','logical','magnificent','mathematics','meticulous','mischievous','mnemonic','monopoly','monotonous','multiplication','necessary','nonchalant','noticeably','numerous','obstacle','opposition','opportunity','organization','parliamentary','perception','perseverance','perspiration','pharaoh','phenomenal','philosophical','precisely','prejudice','preparation','president','privilege','procedure','pronunciation','psychology','quantity','reasonably','recommend','rehabilitation','repetition','representative','resources','responsibility','retrieve','ridiculous','sacrifice','satisfactory','secretary','significant','simultaneously','specification','stimulate','submission','subsequently','substantial','sufficient','superintendent','superstition','syllable','synonymous','temperature','thorough','tragedy','transition','ultimate','unconditional','unforgettable','universal','variable','victorious','vigilance','vocabulary','vulnerable','Wednesday'],
  '6': ['abolition','abstraction','academic','accommodate','acquaintance','acronym','acute','adequate','adjective','allegory','allege','allocate','amendment','analogy','annotation','anthropology','approximate','archaeology','assertion','assess','assimilation','atmosphere','attribute','autonomous','axiom','bilateral','biography','botany','bourgeoisie','bureaucracy','calculated','campaign','capitalism','category','chronicle','circumstance','civilization','coefficient','coherent','commemorate','compatible','complementary','comprehension','conclusion','configuration','consecutive','conservation','conspiracy','constitutional','contamination','context','correlation','cumulative','curriculum','cynical','declaration','definitive','democracy','denomination','derivative','descendant','designation','determination','dialogue','differential','discrepancy','dissertation','elaborate','eloquent','empirical','equivalent','estimate','evaluation','evolution','exaggerate','exemplary','exhaustive','exposition','expression','extensive','factual','figurative','fragmentation','fundamental','geometric','government','gradient','gravity','guarantee','hereditary','hierarchy','hypothesis','ideology','imperative','implication','improper','independent','indigenous','inequality','inference','infinite','integration','intensity','interpretation','latitude','legislation','linguistic','literacy','logarithm','magnitude','marginalize','mechanism','metaphor','microscopic','migration','misconception','narrative','nationalism','notation','observation','opposition','organization','originate','parallel','parameter','participation','peninsula','perception','persecution','phenomenon','philosophy','proportion','protocol','qualify','quantity','quotient','rationalize','rebellion','recognition','rectangle','resilience','significance','simulation','solitude','sovereignty','specification','strategy','submission','synthesis','tendency','theorem','transmission','triangulate','ultimately','unconventional','variable','verification','versatile'],
  '7': ['abbreviation','aberration','abstinence','acceleration','acquiescence','affirmation','aggregation','alliteration','ambiguity','ameliorate','anachronism','anecdote','annotation','antecedent','antithesis','application','approximation','arbitration','assertion','assumption','asymmetrical','authorization','bibliography','calculus','categorization','circumference','clarification','classification','coefficient','coherence','commemoration','commiserate','compensation','complementary','comprehension','configuration','conjugate','conservation','consolidation','contamination','convention','culmination','deconstruction','definition','deliberate','demonstration','depreciation','derivative','designation','determination','differential','displacement','dissemination','documentation','elaboration','elimination','emancipation','encapsulation','equilibrium','evaluation','examination','exemplify','expectation','explanation','exponent','extrapolation','feasibility','formulation','fragmentation','fundamental','generalization','geographic','hyperbole','hypothesis','ideological','illustrate','imagination','implication','inauguration','independence','indeterminate','inference','integration','interpretation','jurisdiction','justification','knowledge','latitude','legislation','liberation','limitation','manifestation','manipulation','measurement','memorization','methodology','microscopic','modification','narrative','negotiation','observation','optimization','organization','oscillation','participation','perception','perpendicular','perspective','precipitation','prerequisite','preservation','probability','proclamation','proportion','quadratic','rationalization','realization','rebellion','recognition','recommendation','reconstruction','regulation','reinforcement','reliability','reluctance','representation','requirement','resistance','significance','specification','substitution','symbolism','systematize','transformation','translation','triangulation','uncertainty','visualization'],
  '8': ['abstraction','accountability','acknowledgment','acquiescence','administration','affirmation','alliteration','ambiguity','amplification','anachronism','analogy','annotation','antithesis','application','approximation','argumentation','assertion','assessment','assimilation','authorization','bibliography','bureaucracy','calcification','categorization','characterization','circumferential','classification','coefficient','commemoration','commentary','compensation','comprehensive','configuration','conjugation','consequence','consolidation','contamination','contradiction','coordination','correlation','culmination','deconstruction','deliberation','demonstration','depreciation','derivation','designation','differentiation','disequilibrium','displacement','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','examination','expectation','exponent','extrapolation','feasibility','formulation','fragmentation','fundamental','generalization','globalization','hypothesis','ideological','implication','inauguration','independence','indeterminate','integration','interpretation','jurisdiction','justification','legislation','liberalization','manipulation','measurement','methodology','modification','negotiation','observation','optimization','organization','oscillation','participation','perpendicular','perspective','precipitation','preservation','probability','proclamation','quadratic','rationalization','reconstruction','regulation','reinforcement','reliability','representation','requirement','resistance','significance','specification','substitution','transformation','triangulation','visualization'],
  '9': ['abstraction','acceleration','accountability','acquiescence','affirmation','alliteration','ambiguity','amplification','anachronism','analogy','annotation','anthropomorphism','antithesis','application','approximation','arbitration','argumentation','assertion','assessment','assimilation','authorization','bibliography','bifurcation','bureaucracy','calcification','categorization','characterization','circumferential','classification','coefficient','commemoration','comprehensive','configuration','conjugation','consequence','consolidation','contamination','contradiction','coordination','correlation','culmination','deliberation','demonstration','derivation','differentiation','disequilibrium','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','examination','exponent','extrapolation','feasibility','formulation','fragmentation','generalization','globalization','hypothesis','ideological','implication','independence','integration','interpretation','jurisdiction','legislation','liberalization','manipulation','measurement','methodology','modification','negotiation','observation','optimization','organization','oscillation','participation','perpendicular','perspective','precipitation','preservation','probability','proclamation','rationalization','reconstruction','regulation','reinforcement','reliability','representation','requirement','resistance','significance','specification','substitution','transformation','triangulation','visualization'],
  '10': ['abolition','abstraction','accountability','acquiescence','affirmation','algebraic','alliteration','ambiguity','amplification','anachronism','analogy','annotation','anthropomorphism','antithesis','application','approximation','arbitration','argumentation','assertion','assessment','assimilation','authorization','bibliography','bifurcation','bureaucracy','categorization','characterization','circumferential','classification','coefficient','commemoration','comprehensive','configuration','conjugation','consequence','consolidation','contradiction','coordination','culmination','deliberation','demonstration','derivation','differentiation','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','examination','exponent','extrapolation','formulation','generalization','globalization','hypothesis','ideological','implication','independence','integration','interpretation','jurisdiction','legislation','liberalization','manipulation','methodology','modification','negotiation','observation','optimization','oscillation','participation','perpendicular','perspective','precipitation','preservation','probability','rationalization','reconstruction','regulation','reinforcement','reliability','representation','significance','specification','substitution','transformation','visualization'],
  '11': ['abstraction','acceleration','accountability','acquiescence','affirmation','algebraic','alliteration','ambiguity','amplification','anachronism','analogy','anthropomorphism','antithesis','approximation','arbitration','argumentation','assertion','assimilation','authorization','bifurcation','bureaucracy','categorization','characterization','coefficient','commemoration','comprehensive','configuration','conjugation','consequence','consolidation','contradiction','culmination','deliberation','derivation','differentiation','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','exponent','extrapolation','formulation','generalization','globalization','hypothesis','ideological','implication','independence','integration','interpretation','jurisdiction','legislation','manipulation','methodology','modification','negotiation','optimization','oscillation','participation','perpendicular','perspective','preservation','probability','rationalization','reconstruction','regulation','reinforcement','reliability','representation','significance','specification','substitution','transformation','visualization'],
  '12': ['abstraction','acquiescence','affirmation','alliteration','ambiguity','amplification','anachronism','analogy','anthropomorphism','antithesis','approximation','arbitration','argumentation','assertion','assimilation','bifurcation','categorization','characterization','coefficient','commemoration','configuration','conjugation','consequence','consolidation','contradiction','culmination','deliberation','derivation','differentiation','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','exponent','extrapolation','formulation','generalization','globalization','hypothesis','ideological','implication','integration','interpretation','jurisdiction','legislation','manipulation','methodology','modification','negotiation','optimization','oscillation','participation','perspective','preservation','probability','rationalization','reconstruction','regulation','reinforcement','reliability','representation','significance','specification','substitution','transformation','visualization'],
  'SAT': ['abstraction','acceleration','acquiescence','affirmation','alliteration','ambiguity','amplification','anachronism','analogy','anthropomorphism','antithesis','approximation','arbitration','argumentation','assertion','assimilation','bifurcation','categorization','characterization','coefficient','commemoration','configuration','conjugation','consequence','consolidation','contradiction','culmination','deliberation','derivation','differentiation','dissemination','documentation','elaboration','emancipation','encapsulation','equilibrium','evaluation','exponent','extrapolation','formulation','generalization','globalization','hypothesis','ideological','implication','integration','interpretation','jurisdiction','legislation','manipulation','methodology','modification','negotiation','optimization','oscillation','participation','perspective','preservation','probability','rationalization','reconstruction','regulation','reinforcement','reliability','representation','significance','specification','substitution','transformation','visualization']
};

// ─────────────────────────────────────────
//  READING PASSAGES
// ─────────────────────────────────────────
const READING = {
  k2: [
    {
      title: "The Little Cloud",
      passage: `One day, a little cloud floated high in the sky. It was white and fluffy, like a soft pillow.\n\nThe little cloud wanted to make something special. It looked down at the dry, brown earth below. The flowers were drooping. The trees looked sad. The animals were thirsty.\n\n"I know what I will do!" said the little cloud. It gathered up all its water and began to rain. Drip, drip, drip! Pitter-patter, pitter-patter!\n\nThe flowers lifted their heads. The trees waved their green leaves. The animals opened their mouths and drank the cool raindrops.\n\nAfter the rain stopped, the sun came back out. A rainbow appeared across the sky — red, orange, yellow, green, blue, and purple!\n\nThe little cloud smiled. It felt happy knowing it had helped everyone below.`,
      questions: [
        { q: "Where was the little cloud?", choices: ["In the ocean","In the sky","Under a tree","In a garden"], answer: "In the sky" },
        { q: "What did the cloud look like?", choices: ["Dark and scary","White and fluffy","Small and thin","Big and gray"], answer: "White and fluffy" },
        { q: "What did the little cloud decide to do?", choices: ["Fly away","Make snow","Rain on the earth","Blow wind"], answer: "Rain on the earth" },
        { q: "How did the flowers react to the rain?", choices: ["They fell over","They lifted their heads","They turned brown","They hid underground"], answer: "They lifted their heads" },
        { q: "What appeared after the rain stopped?", choices: ["A storm","Stars","A rainbow","More clouds"], answer: "A rainbow" },
      ]
    },
    {
      title: "Max Learns to Ride",
      passage: `Max wanted to ride a bike. His big sister Rosa had a red bike, and Max thought it looked so fun.\n\n"Can you teach me?" Max asked.\n\nRosa smiled. "Sure! But you might fall down. That's okay. Everyone falls when they learn."\n\nRosa held the back of Max's bike while he pedaled. Max felt wobbly. He was scared.\n\n"Don't let go!" he said.\n\nBut Rosa let go quietly — and Max kept riding! He didn't even notice at first.\n\nThen Max looked back and saw Rosa standing far behind him. He was riding ALL BY HIMSELF!\n\n"I'm doing it! I'm doing it!" Max shouted with joy.\n\nHe stopped the bike and ran back to hug his sister. "Thank you, Rosa!" he said. "You're the best teacher ever!"`,
      questions: [
        { q: "What did Max want to learn?", choices: ["To swim","To ride a bike","To draw","To cook"], answer: "To ride a bike" },
        { q: "Who taught Max to ride?", choices: ["His mom","His dad","His sister Rosa","His friend"], answer: "His sister Rosa" },
        { q: "What color was the bike?", choices: ["Blue","Green","Yellow","Red"], answer: "Red" },
        { q: "What did Rosa do that surprised Max?", choices: ["She fell down","She let go of the bike","She started crying","She rode away"], answer: "She let go of the bike" },
        { q: "How did Max feel at the end?", choices: ["Angry","Scared","Joyful","Tired"], answer: "Joyful" },
      ]
    },
    {
      title: "The Brave Little Turtle",
      passage: `Shelly was a small turtle who lived near a pond. She had a beautiful shell with brown and yellow spots. But Shelly was very shy. She always hid inside her shell when other animals came near.\n\nOne afternoon, a young rabbit named Bo got his foot stuck between two rocks near the pond. He called for help, but none of the bigger animals were around.\n\nShelly heard his cries. She was scared, but she thought, "I have to help."\n\nShe slowly walked over, pushed one rock with her strong back legs, and freed Bo's foot.\n\n"Thank you!" Bo cried. "You saved me! I didn't know you were so strong!"\n\nShelly smiled. "I didn't either," she said softly.\n\nAfter that day, Shelly wasn't quite so shy anymore. She had discovered something wonderful — she was braver than she knew.`,
      questions: [
        { q: "Where did Shelly live?", choices: ["In a forest","Near a pond","In a field","By the ocean"], answer: "Near a pond" },
        { q: "Why did Shelly usually hide in her shell?", choices: ["She was cold","She was sleeping","She was shy","She was hungry"], answer: "She was shy" },
        { q: "What problem did Bo have?", choices: ["He was lost","His foot was stuck","He was sick","He fell into the water"], answer: "His foot was stuck" },
        { q: "How did Shelly help Bo?", choices: ["She called for help","She carried him","She pushed the rock with her legs","She dug a hole"], answer: "She pushed the rock with her legs" },
        { q: "What did Shelly learn about herself?", choices: ["She was faster than she thought","She was braver than she knew","She was the best swimmer","She had many friends"], answer: "She was braver than she knew" },
      ]
    }
  ],
  '35': [
    {
      title: "The Secret Garden Club",
      passage: `Every Saturday morning, Priya and her three friends met in the empty lot behind their school. Most people saw nothing but weeds and old broken fences. But Priya saw something different — she saw a garden.\n\nThe four friends had been working for six weeks. They had pulled weeds, turned the soil, built raised beds from scrap wood, and planted seeds they'd bought with their own allowance money.\n\nNow, small green shoots were pushing through the dark earth.\n\n"Look at the tomatoes!" shouted Marcus, pointing at a cluster of tiny red globes beginning to form on the vine.\n\n"My sunflowers are taller than me," said Elena proudly, stretching to show that the plants now reached her shoulders.\n\nDeon had planted herbs — basil, mint, and lavender. He pinched a leaf and let everyone smell his fingers. It was amazing.\n\nOne morning, they arrived to find Mrs. Hernandez, the school principal, standing at the edge of their garden. They froze.\n\n"I heard about this place," she said slowly. Then she smiled wide. "I'd like to make this an official school garden. Would that be okay?"\n\nThe four friends looked at each other and burst into cheers.`,
      questions: [
        { q: "Where did the friends build their garden?", choices: ["In Priya's backyard","In an empty lot behind the school","At a park","On a rooftop"], answer: "In an empty lot behind the school" },
        { q: "How long had they been working on the garden?", choices: ["Six days","Six months","Six weeks","Six years"], answer: "Six weeks" },
        { q: "What had Marcus noticed growing?", choices: ["Sunflowers","Herbs","Tomatoes","Pumpkins"], answer: "Tomatoes" },
        { q: "What was Deon's contribution to the garden?", choices: ["Sunflowers","Tomatoes","Herbs","Fruit trees"], answer: "Herbs" },
        { q: "How did the story end?", choices: ["The principal made them leave","The garden was destroyed","The principal wanted to make it an official school garden","The friends gave up on the garden"], answer: "The principal wanted to make it an official school garden" },
      ]
    },
    {
      title: "The Last Lighthouse Keeper",
      passage: `On a rocky point jutting into the Atlantic Ocean stood the oldest lighthouse in the state. Its white tower had guided ships safely past the dangerous rocks for over 150 years.\n\nFor the past 23 years, Harold Finch had been its keeper. He wound the great gears that turned the light, repaired the iron railings, and kept detailed logs of every ship that passed.\n\nBut times were changing. The harbor authority had installed GPS systems on all vessels. Electronic buoys now marked the dangerous rocks. Harold received a letter saying the lighthouse would be automated — no keeper needed.\n\nHarold climbed to the top of the tower one last time and gazed out at the gray Atlantic. In his career, he had helped guide 3,000 ships to safety. Once, he had personally called the Coast Guard when he spotted a vessel taking on water, saving eleven lives.\n\nA young reporter arrived to interview him. "How do you feel about leaving?" she asked.\n\n"The sea doesn't care about progress," Harold said. "But I'm glad the light will keep shining. That's what matters. Not who turns it on."`,
      questions: [
        { q: "How old was the lighthouse?", choices: ["Over 50 years","Over 100 years","Over 150 years","Over 200 years"], answer: "Over 150 years" },
        { q: "How long had Harold been the lighthouse keeper?", choices: ["3 years","13 years","23 years","33 years"], answer: "23 years" },
        { q: "Why was the lighthouse being automated?", choices: ["It was too expensive to repair","New technology made a keeper unnecessary","Harold was retiring voluntarily","A storm had damaged it"], answer: "New technology made a keeper unnecessary" },
        { q: "What was Harold's most significant act as keeper?", choices: ["Writing detailed logs","Repairing the railings","Calling the Coast Guard to save eleven lives","Guiding 3,000 ships"], answer: "Calling the Coast Guard to save eleven lives" },
        { q: "What does Harold's final statement suggest about him?", choices: ["He is angry about losing his job","He cares more about the lighthouse's purpose than his own role","He thinks technology is better than people","He wants the light turned off"], answer: "He cares more about the lighthouse's purpose than his own role" },
      ]
    },
    {
      title: "Crossing the Great Basin",
      passage: `In 1850, fourteen-year-old Abigail Turner left Missouri with her family in a covered wagon headed for California. The journey across the Great Basin Desert was the most dangerous part of the 2,000-mile Oregon Trail.\n\nThe Basin stretched 400 miles of salt flats, alkali dust, and scorching sun. The family's three oxen had to be rationed carefully — each ox needed 15 gallons of water per day. They carried 200 gallons, barely enough.\n\nOn the fourth day, one ox went lame. Without it, their wagon couldn't carry all their supplies. Abigail's father made a painful decision: they had to leave behind their furniture, extra clothing, and most of their food stores. They kept only water, medicine, seeds, and tools.\n\nAbigail wrote in her diary: "Papa says we carry only what will keep us alive. I left behind my books — all except one. I kept the dictionary Grandmother gave me. It weighs two pounds. I told Papa a mind without words is like a wagon without wheels."\n\nThey made it across. In California, Abigail eventually became a schoolteacher, using that same dictionary for 40 years.`,
      questions: [
        { q: "How old was Abigail when she crossed the desert?", choices: ["Ten","Twelve","Fourteen","Sixteen"], answer: "Fourteen" },
        { q: "How wide was the Great Basin Desert they had to cross?", choices: ["200 miles","400 miles","800 miles","1000 miles"], answer: "400 miles" },
        { q: "Why did the family have to leave supplies behind?", choices: ["The wagon was on fire","One ox went lame","They found a shorter route","They were told to by soldiers"], answer: "One ox went lame" },
        { q: "What ONE book did Abigail keep?", choices: ["A novel","A Bible","A history book","A dictionary"], answer: "A dictionary" },
        { q: "What does Abigail's quote 'a mind without words is like a wagon without wheels' mean?", choices: ["Wagons are more important than words","Words and language are essential to thinking","Dictionaries are the most important books","She didn't care about furniture"], answer: "Words and language are essential to thinking" },
      ]
    }
  ],
  '68': [
    {
      title: "The Algorithm That Changed Everything",
      passage: `In the spring of 2009, seventeen-year-old Amir Osei built a program in his bedroom that no one asked for, using tools no one had taught him. He called it "MatchLocal" — a simple algorithm that connected elderly residents with nearby teenagers willing to do yard work, grocery shopping, or minor home repairs.\n\nThe idea came from watching his grandmother struggle to find reliable help after her hip surgery. Her neighborhood association kept a paper list that was always outdated. Amir thought: why not automate the matching?\n\nThe algorithm worked by weighing three factors: proximity (how close the helper lived), availability (when they were free), and verified reviews from previous assignments. It wasn't complex by professional standards, but it was thoughtful.\n\nWithin eight months, MatchLocal had 340 registered users in Amir's city. Local newspapers covered it. A nonprofit offered him a small grant to expand the platform.\n\nBut Amir faced a harder problem than code: trust. Many elderly residents were skeptical of technology they couldn't see or understand. Some refused to use it.\n\nAmir responded by hosting "tech afternoons" at the local community center — not to sell his app, but to teach basic digital literacy. He brought his grandmother, who became his most convincing spokesperson.\n\n"He didn't build it to be famous," she told one newspaper. "He built it because he watched me cry when I couldn't get my gutters cleaned."`,
      questions: [
        { q: "What problem did Amir's algorithm solve?", choices: ["Finding jobs for teenagers","Connecting elderly residents with nearby helpers","Delivering groceries automatically","Updating the neighborhood association website"], answer: "Connecting elderly residents with nearby helpers" },
        { q: "What THREE factors did the algorithm weigh?", choices: ["Age, experience, and location","Proximity, availability, and verified reviews","Speed, price, and distance","Rating, education, and age"], answer: "Proximity, availability, and verified reviews" },
        { q: "What was the harder problem Amir faced beyond writing the code?", choices: ["Finding enough teenagers","Getting newspaper coverage","Building trust with elderly residents who were skeptical of technology","Receiving funding"], answer: "Building trust with elderly residents who were skeptical of technology" },
        { q: "How did Amir address that problem?", choices: ["He gave up on older users","He hired a marketing team","He hosted digital literacy sessions at the community center","He simplified the app significantly"], answer: "He hosted digital literacy sessions at the community center" },
        { q: "According to Amir's grandmother, what was Amir's true motivation?", choices: ["Fame and recognition","Making money","Solving a real problem he witnessed","Learning to code professionally"], answer: "Solving a real problem he witnessed" },
      ]
    },
    {
      title: "The Migration of the Monarch",
      passage: `Every autumn, roughly 300 million monarch butterflies undertake one of the most extraordinary migrations in the animal kingdom — a journey of up to 3,000 miles from the northern United States and Canada to a cluster of about 12 oyamel fir forests in the mountains of Michoacán, Mexico.\n\nWhat makes this feat remarkable isn't just the distance — it's the navigation. The butterflies that begin the journey south have never been to Mexico. Their great-great-grandparents made the previous trip. Yet somehow, monarchs locate the same groves of trees each year.\n\nResearchers have found that monarchs use a kind of "time-compensated sun compass" — essentially a biological clock calibrated to the sun's position in the sky. Even on cloudy days, they can sense polarized light to maintain direction.\n\nBut the monarch population has collapsed by more than 80% since the 1990s. Three threats converge: the loss of milkweed in the U.S. Midwest (the only plant monarch caterpillars can eat), illegal logging that destroys Mexican overwintering forests, and climate change shifting the timing of seasonal cues.\n\nScientists are now creating "milkweed corridors" — strips of native vegetation planted along major flight paths — in hopes of reversing the decline. Whether these efforts will be enough remains uncertain. The monarchs don't wait for us to figure it out.`,
      questions: [
        { q: "How far do monarch butterflies travel during migration?", choices: ["Up to 300 miles","Up to 1,000 miles","Up to 3,000 miles","Up to 5,000 miles"], answer: "Up to 3,000 miles" },
        { q: "Why is the monarchs' navigation particularly remarkable?", choices: ["They travel at night","The butterflies making the trip have never been to their destination before","They travel faster than any other insect","They don't need food during the journey"], answer: "The butterflies making the trip have never been to their destination before" },
        { q: "How do monarchs navigate?", choices: ["By following rivers","By using magnetic fields from the Earth","Using a biological clock calibrated to the sun's position","By following older butterflies"], answer: "Using a biological clock calibrated to the sun's position" },
        { q: "By how much has the monarch population declined since the 1990s?", choices: ["20%","40%","60%","Over 80%"], answer: "Over 80%" },
        { q: "What are 'milkweed corridors' designed to do?", choices: ["Replace the Mexican overwintering forests","Provide food for caterpillars along flight paths","Block illegal logging","Control climate change"], answer: "Provide food for caterpillars along flight paths" },
      ]
    },
    {
      title: "The Boy Who Mapped the Sky",
      passage: `In 1783, William Herschel — a German-born musician living in Bath, England — had already made one of the greatest accidental discoveries in astronomical history: the planet Uranus, the first planet identified with a telescope.\n\nBut Herschel was not content with planets. He wanted to understand the structure of the entire Milky Way.\n\nWith his sister Caroline as his partner — who herself discovered eight comets and would become the first woman paid for scientific work — William spent decades systematically sweeping the sky with a 20-foot reflecting telescope he had built himself. He recorded the position and brightness of over 800 nebulae and star clusters.\n\nHerschel's revolutionary insight was to treat the sky not as a flat ceiling dotted with lights, but as a three-dimensional space. By studying how stars clustered, he reasoned that the Milky Way was a disk-shaped system, and that our Sun sat somewhere within it.\n\nHe was correct about the disk shape. He was wrong about the Sun's position — we now know the Sun is far from the center. But his method — systematic observation followed by structural reasoning — became the foundation of modern observational astronomy.\n\n"I have looked farther into space than ever human being did before me," Herschel once wrote. He was being precise, not boastful. The telescope he had built could gather more light than any instrument in history.`,
      questions: [
        { q: "What was Herschel's famous accidental discovery?", choices: ["The Milky Way","Neptune","Uranus","A new star cluster"], answer: "Uranus" },
        { q: "Who was Herschel's partner in his sky surveys?", choices: ["His wife","His brother","His sister Caroline","A university colleague"], answer: "His sister Caroline" },
        { q: "What was Herschel's revolutionary new way of thinking about the sky?", choices: ["That planets orbited stars","That the sky was flat","That the sky was three-dimensional space","That comets were more important than stars"], answer: "That the sky was three-dimensional space" },
        { q: "What was Herschel correct about — and wrong about?", choices: ["He was right that the Sun was at the center, wrong about the disk shape","He was right about the disk shape, wrong about the Sun's position","He was right about both things","He was wrong about both things"], answer: "He was right about the disk shape, wrong about the Sun's position" },
        { q: "What does the passage suggest was Herschel's most lasting contribution?", choices: ["Discovering Uranus","Building the world's biggest telescope","Establishing systematic observation followed by structural reasoning","Mapping all visible comets"], answer: "Establishing systematic observation followed by structural reasoning" },
      ]
    }
  ],
  '912': [
    {
      title: "The Epidemiologist's Dilemma",
      passage: `In March 2003, Dr. Carlo Urbani, an Italian epidemiologist working for the World Health Organization in Hanoi, received an unusual patient at a French hospital. The man, a Chinese-American businessman, had a severe respiratory illness unlike anything Urbani had encountered. Within days, hospital staff were also falling sick.\n\nUrbani immediately recognized the pattern: a novel pathogen with human-to-human transmission capability. He contacted the WHO and Vietnamese health authorities with urgency, recommending immediate quarantine of the entire hospital — a drastic measure that would later prove decisive in preventing what was identified as SARS (Severe Acute Respiratory Syndrome) from spreading explosively through Vietnam.\n\nThe quarantine caused significant economic disruption. It separated families. Healthcare workers — many of whom had not yet consented to special risks — were confined to the hospital. Some questioned the ethics of the decision: could one individual unilaterally impose such restrictions on others?\n\nUrbani himself was infected before the quarantine was fully in place. Knowing he was contagious, he voluntarily isolated himself, insisting he not be transported to a country with less-developed infrastructure, where he might seed an outbreak. He died in Bangkok on March 29, 2003, at age 46.\n\nThe WHO later credited Urbani's response with preventing a catastrophic Southeast Asian outbreak. Vietnam became the first country to successfully contain SARS. The tools used — rapid identification, transparent reporting, swift quarantine — were precisely the protocols Urbani had demanded under pressure.\n\nHis case remains a touchstone in medical ethics courses: when do the duties of public health override individual autonomy, and what do we owe those who are asked to bear disproportionate risk in service of collective safety?`,
      questions: [
        { q: "What disease did Urbani help identify?", choices: ["Ebola","MERS","SARS","COVID-19"], answer: "SARS" },
        { q: "Why was Urbani's recommendation of hospital quarantine considered drastic?", choices: ["It was extremely expensive","It stopped all air travel","It confined hospital staff who hadn't consented to special risks","It required international cooperation"], answer: "It confined hospital staff who hadn't consented to special risks" },
        { q: "Why did Urbani insist on not being transported to his home country when infected?", choices: ["He wanted to stay near his family","He wanted to continue working","He feared spreading the disease to a less-developed area","He didn't trust foreign hospitals"], answer: "He feared spreading the disease to a less-developed area" },
        { q: "What does the passage identify as Urbani's most significant contribution?", choices: ["Developing a SARS vaccine","Discovering the SARS virus genetically","His rapid response protocols preventing a catastrophic outbreak","Treating the first patients personally"], answer: "His rapid response protocols preventing a catastrophic outbreak" },
        { q: "What ethical question does Urbani's case raise in medical ethics?", choices: ["Should doctors be paid more?","When do public health duties override individual autonomy?","Should quarantine be voluntary only?","Is it ethical to work in dangerous countries?"], answer: "When do public health duties override individual autonomy?" },
      ]
    },
    {
      title: "What Silence Sounds Like",
      passage: `In 2011, composer John Luther Adams won the Pulitzer Prize for Music for a piece called "Become Ocean" — a 42-minute orchestral work designed to evoke geological and oceanic time. But before this triumph, Adams spent 30 years living in a cabin in the Alaskan wilderness, making music that almost no one heard.\n\nHis choice was deliberate and, to most people in the music industry, incomprehensible. Adams had trained in New York, had connections, had early critical recognition. He walked away from it to listen.\n\n"I needed to understand silence before I could understand sound," he told an interviewer. In Alaska, he developed what he called "sonic geography" — the practice of notating the natural soundscape of a specific landscape and translating it into musical composition. His early works mapped the acoustic signatures of particular Alaskan mountains, rivers, and ice fields.\n\nCritics who eventually heard his work were divided. Some called it revolutionary — a genuine synthesis of ecology and music. Others found it self-indulgent, inaccessible, too slow. The standard rap against Adams was that he had sacrificed craft and audience in pursuit of purity.\n\nHis defenders pointed to a different metric: Adams had spent three decades asking what music was for — not who it was for. The resulting work had a quality of attention that most concert music, optimized for performance venues and critics' deadlines, does not even attempt.\n\nWhen "Become Ocean" premiered with the Seattle Symphony, the audience sat in stunned silence at its conclusion for nearly 30 seconds before applauding. Whether that silence was confusion, awe, or both, no one could agree. Perhaps that ambiguity was the point.`,
      questions: [
        { q: "What award did Adams win in 2011?", choices: ["Nobel Prize","Grammy Award","Pulitzer Prize for Music","National Book Award"], answer: "Pulitzer Prize for Music" },
        { q: "Why was Adams's decision to move to Alaska considered unusual in the music industry?", choices: ["Alaska had no recording studios","He had connections and early recognition that he walked away from","Alaska was too cold for instruments","He was required to leave New York"], answer: "He had connections and early recognition that he walked away from" },
        { q: "What did Adams mean by 'sonic geography'?", choices: ["Making music louder outdoors","Using GPS to find recording locations","Notating natural soundscapes and translating them into composition","Studying how sound travels through different landscapes"], answer: "Notating natural soundscapes and translating them into composition" },
        { q: "What was the 'standard rap' or main criticism against Adams?", choices: ["He was too commercially successful","He had sacrificed craft and audience in pursuit of purity","He copied other composers","His music was too short"], answer: "He had sacrificed craft and audience in pursuit of purity" },
        { q: "What does the passage suggest was most different about Adams's approach to music?", choices: ["He used unusual instruments","He spent 30 years asking what music was for, not who it was for","He refused to perform in concert halls","He wrote only for solo instruments"], answer: "He spent 30 years asking what music was for, not who it was for" },
      ]
    },
    {
      title: "The Trolley Problem, Reconsidered",
      passage: `In 1967, philosopher Philippa Foot published a thought experiment that has since become the most discussed scenario in applied ethics. The premise: a runaway trolley is speeding toward five people tied to the tracks. You are standing next to a lever. If you pull it, the trolley diverts to a side track, where one person is tied. Do you pull the lever?\n\nMost people say yes. The utilitarian calculus seems clear: five lives outweigh one. But Foot's actual purpose was not to establish a rule — it was to expose a tension in moral reasoning.\n\nHer contemporary Judith Jarvis Thomson modified the scenario. Now you are on a bridge overlooking the tracks. The only way to stop the trolley is to push a large man off the bridge — his body will halt the trolley and save the five. Same arithmetic: one life versus five. Yet most people who said yes to the lever refuse to push the man.\n\nWhy? The outcomes are numerically identical. Philosophers have proposed many explanations: the doctrine of double effect (harm as a side effect of achieving good is more permissible than harm as a means to achieve good); the act-omission distinction (doing harm is worse than allowing harm); the personal force principle (using physical contact to cause harm triggers different moral intuitions).\n\nWhat the trolley problem really reveals is that human moral reasoning is not a single unified system. We apply different frameworks — sometimes utilitarian, sometimes deontological, sometimes based on gut revulsion — depending on the framing of the situation. Understanding that inconsistency may be the first step toward moral wisdom, or the beginning of a very long argument.`,
      questions: [
        { q: "Who first published the trolley problem thought experiment?", choices: ["Judith Jarvis Thomson","Immanuel Kant","Philippa Foot","Peter Singer"], answer: "Philippa Foot" },
        { q: "What was Foot's actual purpose with the thought experiment?", choices: ["To prove that five lives always outweigh one","To establish a rule for emergency decisions","To expose a tension in moral reasoning","To argue against utilitarian ethics"], answer: "To expose a tension in moral reasoning" },
        { q: "Why does Thomson's bridge variation reveal an inconsistency?", choices: ["It involves more people","It involves a different location","The outcomes are numerically identical yet people respond differently","It was published by a different philosopher"], answer: "The outcomes are numerically identical yet people respond differently" },
        { q: "What does the 'doctrine of double effect' hold?", choices: ["Two people must always be saved over one","Harm as a side effect of doing good is more permissible than harm as a means to good","Double the benefit must outweigh any harm","Effects of actions must be evaluated twice"], answer: "Harm as a side effect of doing good is more permissible than harm as a means to good" },
        { q: "What does the passage suggest is the trolley problem's deepest insight?", choices: ["Utilitarianism is always the correct framework","Five lives always outweigh one life","Human moral reasoning is not a single unified system","Physical distance makes ethical choices easier"], answer: "Human moral reasoning is not a single unified system" },
      ]
    }
  ],
  sat: [
    {
      title: "The Invisible Architecture of Cities",
      passage: `Urban planners have long understood that the physical layout of a city shapes behavior — that grid streets versus curvilinear roads, or the presence of parks versus parking lots, influences how residents interact, exercise, and even vote. But a growing body of research suggests that a city's invisible architecture — its acoustic environment, its light patterns, its air circulation systems — may have equally profound effects on cognitive function and mental health.\n\nA 2018 study published in Nature found that urban residents exposed to more than 65 decibels of traffic noise (approximately the volume of a vacuum cleaner) showed measurably elevated cortisol levels and reduced performance on executive function tasks, regardless of whether they consciously perceived the noise as bothersome. The effect was cumulative: residents exposed for more than five years showed cognitive patterns consistent with accelerated aging.\n\nLight presents a parallel problem. The blue-spectrum light emitted by LED streetlights — now standard in most Western cities following a decade of energy-efficiency retrofits — suppresses melatonin production at a ratio 5 times greater than the sodium-vapor lamps they replaced. A 2020 study found a 12% higher rate of depression diagnosis in neighborhoods that had switched to LED lighting within the previous three years.\n\nCity planners are now experimenting with "sensory urbanism" — designing districts around their acoustic, olfactory, and luminescence profiles rather than solely around traffic flow and zoning. The Dutch city of Amsterdam has piloted a "soundscape" approach, designating specific zones as protected quiet areas where ambient noise must remain below 50 decibels.\n\nCritics argue that sensory urbanism is a luxury for affluent cities, irrelevant to the 2.5 billion people expected to move to cities by 2050, most in the developing world. Its proponents counter that the cognitive costs of ignoring the invisible city — measured in healthcare expenditure, productivity loss, and decades of reduced well-being — are precisely what developing cities cannot afford.`,
      questions: [
        { q: "What does the passage mean by a city's 'invisible architecture'?", choices: ["Underground infrastructure like sewers and pipes","Buildings that are difficult to see","Acoustic, light, and air circulation environments","City planning regulations that aren't publicly posted"], answer: "Acoustic, light, and air circulation environments" },
        { q: "According to the 2018 Nature study, what was notable about the effect of traffic noise on residents?", choices: ["It only affected elderly residents","It only mattered if residents consciously found the noise bothersome","The effect occurred regardless of whether residents perceived the noise as bothersome","It caused physical hearing loss"], answer: "The effect occurred regardless of whether residents perceived the noise as bothersome" },
        { q: "Why does the passage describe LED streetlights as presenting a 'parallel problem' to noise?", choices: ["They are also more expensive than previous technology","They also suppress a biological process, with measurable health consequences","They are also invisible to urban planners","They also produce noise in addition to light"], answer: "They also suppress a biological process, with measurable health consequences" },
        { q: "What does Amsterdam's 'soundscape' pilot program involve?", choices: ["Installing noise-canceling equipment throughout the city","Requiring electric vehicles only","Designating protected quiet zones where ambient noise must stay below 50 decibels","Requiring all construction to stop at night"], answer: "Designating protected quiet zones where ambient noise must stay below 50 decibels" },
        { q: "How do proponents of sensory urbanism respond to the criticism that it is a luxury?", choices: ["They agree that developing cities should focus on basic infrastructure first","They argue the cognitive costs of ignoring these factors are exactly what developing cities cannot afford","They say sensory urbanism only applies to residential neighborhoods","They claim the research doesn't apply to developing cities"], answer: "They argue the cognitive costs of ignoring these factors are exactly what developing cities cannot afford" },
      ]
    },
    {
      title: "The Two Cultures, Fifty Years Later",
      passage: `In 1959, the British chemist and novelist C.P. Snow delivered a lecture at Cambridge that became one of the most debated essays of the twentieth century. His argument, published as "The Two Cultures," was that Western intellectual life had fractured into two mutually incomprehensible camps: scientists and literary intellectuals. Each regarded the other with a mix of suspicion and condescension; neither possessed the literacy to engage meaningfully with the other's work.\n\nSnow provocatively asked a group of literary intellectuals whether they could describe the Second Law of Thermodynamics — roughly equivalent, he said, to having read a work of Shakespeare. Almost none could. He viewed this as a civilizational failure with practical consequences: the decisions required to address poverty, industrialization, and technological change required precisely the integration of scientific understanding and humanistic judgment that the divide made impossible.\n\nFifty years later, the diagnosis is being reconsidered. Some argue Snow was right about the divide but wrong about its cause: it is not that scientists and humanists don't talk to each other, but that the institutional structures of modern research universities actively discourage it. Tenure systems, grant funding mechanisms, and publication norms all reward specialization and penalize interdisciplinary work.\n\nOthers argue Snow's binary was always too simple. The most interesting intellectual work — behavioral economics, cognitive neuroscience, environmental humanities, computational social science — has always happened at the seams between disciplines. The real divide may not be between sciences and humanities at all, but between those who can tolerate ambiguity and those who cannot.\n\n"What Snow was really mourning," wrote the critic Stefan Collini in 2009, "was not a lost synthesis, but a lost confidence — the Victorian certainty that educated people had a common set of problems to solve. We've lost that certainty. Whether we've also lost the problems is a different question."`,
      questions: [
        { q: "What was the central argument of Snow's 'The Two Cultures'?", choices: ["Scientists are more important than humanists","Western intellectual life had split into two groups that couldn't understand each other","Universities should focus more on science funding","Literary fiction is more important than scientific research"], answer: "Western intellectual life had split into two groups that couldn't understand each other" },
        { q: "What did Snow use the Second Law of Thermodynamics to illustrate?", choices: ["The complexity of physics","How science is more difficult than literature","Literary intellectuals' ignorance of basic scientific knowledge","The importance of chemistry in education"], answer: "Literary intellectuals' ignorance of basic scientific knowledge" },
        { q: "According to those who reconsider Snow's diagnosis, what actually maintains the divide?", choices: ["Natural differences in how scientists and humanists think","Personal animosity between academics","Institutional structures that reward specialization and penalize interdisciplinary work","The difficulty of understanding both fields"], answer: "Institutional structures that reward specialization and penalize interdisciplinary work" },
        { q: "What alternative divide does the passage suggest may be more accurate than Snow's binary?", choices: ["Between those in universities and those outside them","Between those who can tolerate ambiguity and those who cannot","Between natural scientists and social scientists","Between those who read fiction and those who don't"], answer: "Between those who can tolerate ambiguity and those who cannot" },
        { q: "What does Collini suggest Snow was really mourning?", choices: ["The decline of chemistry as a discipline","The loss of Victorian certainty that educated people shared common problems","The end of great literary novels","The beginning of specialization in universities"], answer: "The loss of Victorian certainty that educated people shared common problems" },
      ]
    },
    {
      title: "Rewilding and the Question of Baseline",
      passage: `Conservation biology has long operated on the concept of a "baseline" — a target state of ecological health against which degradation can be measured and toward which restoration should aim. For most of the twentieth century, this baseline was understood as the pre-industrial ecosystem: the condition of a habitat before logging, farming, or industrial pollution altered it.\n\nBut the rewilding movement — which advocates for the large-scale reintroduction of apex predators, keystone species, and natural disturbance regimes — has forced a reckoning with a more difficult question: which baseline?\n\nIn Europe, proponents of rewilding argue for reintroducing wolves, lynx, and eventually bison to areas where they were eliminated over the past several centuries. But historical ecology research has shown that these same landscapes were fundamentally different before human agricultural settlement 8,000 years ago. Should restoration aim for pre-industrial conditions (the 1600s), pre-agricultural conditions (6000 BCE), or the theoretical "climax ecosystem" that might exist in the absence of any human activity?\n\nEach choice has radically different implications. Pre-industrial restoration supports returning wolves to Scotland. Pre-agricultural restoration might require reintroducing Eurasian aurochs, cave bears, and woolly rhinoceroses — all extinct. The climax ecosystem model is, by definition, impossible to achieve.\n\nThis isn't merely a philosophical puzzle. In the United States, the reintroduction of gray wolves to Yellowstone in 1995 — targeting a pre-twentieth-century baseline — produced what ecologists call a "trophic cascade": wolves suppressed elk populations, which allowed riverbank vegetation to recover, which stabilized riverbanks, which changed river flow patterns. The ecosystem responded to the intervention in ways that no model had predicted.\n\nThe baseline debate reveals something important: ecological systems are not static targets to be returned to, but dynamic processes to be initiated. The goal of rewilding, its strongest advocates now argue, is not to recreate a specific historical moment, but to restore ecological complexity and the capacity for self-regulation.`,
      questions: [
        { q: "What was the traditional understanding of the ecological 'baseline' in conservation biology?", choices: ["The ideal theoretical state with no humans","The pre-industrial ecosystem before logging and industrial pollution","The earliest recorded state of any given ecosystem","The current average state of similar ecosystems worldwide"], answer: "The pre-industrial ecosystem before logging and industrial pollution" },
        { q: "What key challenge does the rewilding movement raise about the baseline concept?", choices: ["Rewilding is too expensive to implement","Which historical moment should serve as the target for restoration?","Reintroducing animals is scientifically impossible","Pre-industrial ecosystems didn't actually exist"], answer: "Which historical moment should serve as the target for restoration?" },
        { q: "Why would pre-agricultural restoration be practically impossible?", choices: ["It would require returning all human settlements","It would require reintroducing extinct species","European governments would not allow it","It would take thousands of years"], answer: "It would require reintroducing extinct species" },
        { q: "What is a 'trophic cascade' as described in the passage?", choices: ["A waterfall in Yellowstone National Park","A chain of ecological effects flowing from the reintroduction of a predator","The process by which wolves hunt elk","A type of river flow pattern"], answer: "A chain of ecological effects flowing from the reintroduction of a predator" },
        { q: "What does the passage suggest is the strongest current argument for rewilding?", choices: ["Recreating the pre-industrial landscape exactly","Returning specific extinct species to their habitats","Restoring ecological complexity and capacity for self-regulation, rather than recreating a specific moment","Preventing all future human interference in natural areas"], answer: "Restoring ecological complexity and capacity for self-regulation, rather than recreating a specific moment" },
      ]
    }
  ]
};

// ─────────────────────────────────────────
//  SCIENCE QUESTIONS
// ─────────────────────────────────────────
const SCIENCE = {
  k2: [
    { q: "What do plants need to grow?", choices: ["Sunlight, water, and soil","Pizza and candy","Just water","Only soil"], answer: "Sunlight, water, and soil" },
    { q: "What is the closest star to Earth?", choices: ["The Moon","Mars","The Sun","Pluto"], answer: "The Sun" },
    { q: "What does a caterpillar turn into?", choices: ["A ladybug","A butterfly or moth","A worm","A bee"], answer: "A butterfly or moth" },
    { q: "Which animal is a mammal?", choices: ["Goldfish","Snake","Dog","Frog"], answer: "Dog" },
    { q: "What does ice become when it warms up?", choices: ["Snow","Rock","Water","Steam"], answer: "Water" },
    { q: "How many legs does an insect have?", choices: ["4","6","8","10"], answer: "6" },
    { q: "What is the sky made of mostly?", choices: ["Water","Dust","Air","Fire"], answer: "Air" },
    { q: "Which sense do we use our ears for?", choices: ["Sight","Touch","Hearing","Smell"], answer: "Hearing" },
    { q: "What do we breathe in to stay alive?", choices: ["Carbon dioxide","Oxygen","Helium","Smoke"], answer: "Oxygen" },
    { q: "Which is NOT a type of weather?", choices: ["Rain","Snow","Gravity","Sunshine"], answer: "Gravity" },
    { q: "Where do fish live?", choices: ["In trees","Underground","In water","On rocks"], answer: "In water" },
    { q: "What do bees collect from flowers?", choices: ["Water","Nectar","Leaves","Dirt"], answer: "Nectar" },
    { q: "Which is a solid?", choices: ["Water","Ice","Steam","Air"], answer: "Ice" },
    { q: "What do you use to see very tiny things?", choices: ["Telescope","Binoculars","Microscope","Camera"], answer: "Microscope" },
    { q: "What season comes after winter?", choices: ["Fall","Summer","Spring","Another winter"], answer: "Spring" },
    { q: "Which body part pumps blood?", choices: ["Brain","Stomach","Heart","Lungs"], answer: "Heart" },
  ],
  '35': [
    { q: "What is photosynthesis?", choices: ["How animals breathe","How plants make food using sunlight","How rocks form","How water freezes"], answer: "How plants make food using sunlight" },
    { q: "What layer of Earth do we live on?", choices: ["Core","Mantle","Crust","Magma"], answer: "Crust" },
    { q: "Which planet is known as the Red Planet?", choices: ["Venus","Jupiter","Mars","Saturn"], answer: "Mars" },
    { q: "What is the water cycle's correct order?", choices: ["Rain → Evaporation → Condensation","Evaporation → Condensation → Precipitation","Snow → Rain → Evaporation","None of these"], answer: "Evaporation → Condensation → Precipitation" },
    { q: "What gas do plants release during photosynthesis?", choices: ["Carbon dioxide","Hydrogen","Oxygen","Nitrogen"], answer: "Oxygen" },
    { q: "Which type of rock is formed from magma?", choices: ["Sedimentary","Metamorphic","Igneous","Limestone"], answer: "Igneous" },
    { q: "What force pulls objects toward Earth?", choices: ["Magnetism","Electricity","Gravity","Friction"], answer: "Gravity" },
    { q: "What is the main component of air?", choices: ["Oxygen (78%)","Nitrogen (78%)","Carbon dioxide (78%)","Water vapor (78%)"], answer: "Nitrogen (78%)" },
    { q: "Which part of the plant absorbs water from the soil?", choices: ["Leaves","Stem","Roots","Flowers"], answer: "Roots" },
    { q: "What is the largest planet in our solar system?", choices: ["Earth","Saturn","Neptune","Jupiter"], answer: "Jupiter" },
    { q: "What is energy from the Sun called?", choices: ["Wind energy","Nuclear energy","Solar energy","Geothermal energy"], answer: "Solar energy" },
    { q: "Which animal is cold-blooded?", choices: ["Bear","Eagle","Snake","Dolphin"], answer: "Snake" },
    { q: "What do we call animals that eat only plants?", choices: ["Carnivores","Omnivores","Herbivores","Predators"], answer: "Herbivores" },
    { q: "What is the process of liquid turning to gas?", choices: ["Condensation","Freezing","Evaporation","Melting"], answer: "Evaporation" },
    { q: "What is the speed of light approximately?", choices: ["300 km/s","300,000 km/s","3,000 km/s","30 km/s"], answer: "300,000 km/s" },
    { q: "What type of simple machine is a ramp?", choices: ["Lever","Pulley","Inclined plane","Wheel and axle"], answer: "Inclined plane" },
  ],
  '68': [
    { q: "What is Newton's Second Law of Motion?", choices: ["For every action there is an equal and opposite reaction","Force equals mass times acceleration","Objects in motion stay in motion","Energy cannot be created or destroyed"], answer: "Force equals mass times acceleration" },
    { q: "What is the atomic number of carbon?", choices: ["6","12","14","8"], answer: "6" },
    { q: "What type of bond involves sharing electrons?", choices: ["Ionic bond","Metallic bond","Covalent bond","Hydrogen bond"], answer: "Covalent bond" },
    { q: "What is the process by which cells divide?", choices: ["Osmosis","Mitosis","Photosynthesis","Fermentation"], answer: "Mitosis" },
    { q: "What does DNA stand for?", choices: ["Deoxyribonucleic acid","Dioxinribonucleic acid","Dimethylribonucleic acid","Dynamic nucleic acid"], answer: "Deoxyribonucleic acid" },
    { q: "What is the SI unit of force?", choices: ["Watt","Joule","Newton","Pascal"], answer: "Newton" },
    { q: "What organelle produces energy in eukaryotic cells?", choices: ["Ribosome","Nucleus","Mitochondria","Cell wall"], answer: "Mitochondria" },
    { q: "What is the chemical formula for water?", choices: ["CO₂","H₂O","NaCl","O₂"], answer: "H₂O" },
    { q: "What is the pH of a neutral solution?", choices: ["0","7","14","10"], answer: "7" },
    { q: "What type of wave does NOT require a medium to travel?", choices: ["Sound wave","Ocean wave","Seismic wave","Electromagnetic wave"], answer: "Electromagnetic wave" },
    { q: "What is tectonic plate movement responsible for?", choices: ["Weather patterns","Ocean currents","Earthquakes and volcanic eruptions","Tidal patterns"], answer: "Earthquakes and volcanic eruptions" },
    { q: "Which particle has no charge in an atom?", choices: ["Proton","Electron","Neutron","Ion"], answer: "Neutron" },
    { q: "What is the Law of Conservation of Energy?", choices: ["Energy is always lost as heat","Energy cannot be created or destroyed, only transformed","Energy equals mass times velocity","All energy comes from the Sun"], answer: "Energy cannot be created or destroyed, only transformed" },
    { q: "What is natural selection?", choices: ["Humans choosing which animals survive","Organisms with favorable traits survive and reproduce more","Animals selecting their food","The choice plants make to grow toward light"], answer: "Organisms with favorable traits survive and reproduce more" },
    { q: "What determines an element's identity?", choices: ["Its mass","Its number of electrons","Its number of protons (atomic number)","Its temperature"], answer: "Its number of protons (atomic number)" },
    { q: "What is a hypothesis?", choices: ["A proven fact","A testable prediction or explanation","A conclusion drawn from data","A final answer in science"], answer: "A testable prediction or explanation" },
  ],
  '912': [
    { q: "What is entropy in thermodynamics?", choices: ["The total energy of a system","A measure of disorder or randomness in a system","The temperature of a system at equilibrium","The rate of energy transfer"], answer: "A measure of disorder or randomness in a system" },
    { q: "What does the Hardy-Weinberg equilibrium describe?", choices: ["How mutations occur","Allele frequencies in a non-evolving population","The rate of natural selection","How DNA replication works"], answer: "Allele frequencies in a non-evolving population" },
    { q: "What is a redox reaction?", choices: ["Any reaction involving heat","A reaction involving transfer of oxygen only","A reaction involving electron transfer (reduction and oxidation)","A reaction that reverses direction"], answer: "A reaction involving electron transfer (reduction and oxidation)" },
    { q: "What is the Heisenberg Uncertainty Principle?", choices: ["Nothing can travel faster than light","We cannot know both position and momentum of a particle precisely","All matter is made of waves","Electrons orbit in fixed paths"], answer: "We cannot know both position and momentum of a particle precisely" },
    { q: "What is gene expression?", choices: ["The genetic code of an organism","The process by which DNA information is used to build proteins","The mutation rate of DNA","The number of chromosomes in a cell"], answer: "The process by which DNA information is used to build proteins" },
    { q: "What is the Krebs cycle?", choices: ["The life cycle of plants","A series of chemical reactions that generate energy from acetyl-CoA","The process of DNA replication","How nerve signals travel"], answer: "A series of chemical reactions that generate energy from acetyl-CoA" },
    { q: "What is Le Chatelier's Principle?", choices: ["The faster the reaction, the more energy is released","A system at equilibrium resists changes by shifting to counteract them","Gases behave ideally under all conditions","Acid-base reactions always produce water"], answer: "A system at equilibrium resists changes by shifting to counteract them" },
    { q: "What is the difference between mitosis and meiosis?", choices: ["Mitosis produces sex cells; meiosis produces body cells","Mitosis produces 2 identical cells; meiosis produces 4 genetically unique cells","They are the same process","Meiosis only occurs in plants"], answer: "Mitosis produces 2 identical cells; meiosis produces 4 genetically unique cells" },
    { q: "What does an action potential in a neuron represent?", choices: ["The cell moving toward stimulation","A rapid electrical signal transmitted along the nerve fiber","A chemical released into a synapse","The neuron repairing damage"], answer: "A rapid electrical signal transmitted along the nerve fiber" },
    { q: "What is dark matter?", choices: ["Black holes","Matter that absorbs all light","A hypothetical substance accounting for mass discrepancies in galaxies","The space between stars"], answer: "A hypothetical substance accounting for mass discrepancies in galaxies" },
    { q: "What is CRISPR-Cas9?", choices: ["A type of virus","A gene editing tool that targets specific DNA sequences","A protein that causes aging","A form of RNA transcription"], answer: "A gene editing tool that targets specific DNA sequences" },
    { q: "What is the significance of the Cambrian explosion?", choices: ["The first appearance of plants on land","A rapid diversification of complex animal body plans ~541 million years ago","The extinction of the dinosaurs","The formation of Earth's atmosphere"], answer: "A rapid diversification of complex animal body plans ~541 million years ago" },
    { q: "What is electromagnetic induction?", choices: ["Charging an object by contact","Generating voltage by changing magnetic flux","The way electric fields repel each other","How motors create motion"], answer: "Generating voltage by changing magnetic flux" },
    { q: "What is the difference between a virus and a bacterium?", choices: ["Viruses are larger; bacteria are smaller","Viruses require a host cell to reproduce; bacteria can reproduce independently","Viruses have cell walls; bacteria do not","Bacteria cause all infectious disease; viruses cause none"], answer: "Viruses require a host cell to reproduce; bacteria can reproduce independently" },
    { q: "What is a buffer in chemistry?", choices: ["A substance that speeds up reactions","A solution that resists changes in pH","A membrane that controls ion flow","A compound that stores energy"], answer: "A solution that resists changes in pH" },
    { q: "What is plate tectonics?", choices: ["The study of earthquakes only","The theory that Earth's lithosphere is divided into moving plates","The formation of volcanoes","The study of mountain formation"], answer: "The theory that Earth's lithosphere is divided into moving plates" },
  ],
  sat: [
    { q: "What is a confidence interval in statistics?", choices: ["The probability that a result is correct","A range within which the true population parameter likely falls","The margin of error in a sample","The significance level of a test"], answer: "A range within which the true population parameter likely falls" },
    { q: "What is the difference between correlation and causation?", choices: ["They mean the same thing","Correlation shows a relationship; causation shows one variable causes the other","Causation is weaker than correlation","Correlation always implies causation with enough data"], answer: "Correlation shows a relationship; causation shows one variable causes the other" },
    { q: "What is the greenhouse effect?", choices: ["Farming in greenhouses","The warming of Earth's surface when greenhouse gases trap heat in the atmosphere","The cooling effect of forests","A natural cooling process"], answer: "The warming of Earth's surface when greenhouse gases trap heat in the atmosphere" },
    { q: "What is CRISPR primarily used for in research?", choices: ["Growing new organs","Editing specific sequences in DNA","Sequencing entire genomes","Creating artificial life"], answer: "Editing specific sequences in DNA" },
    { q: "What does the p-value represent in a scientific study?", choices: ["The size of the effect found","The probability of getting the observed result if the null hypothesis is true","The certainty that the hypothesis is correct","The sample size needed"], answer: "The probability of getting the observed result if the null hypothesis is true" },
    { q: "What is the relationship between wavelength and frequency in light?", choices: ["They are directly proportional","They are inversely proportional (higher frequency = shorter wavelength)","They have no relationship","They are always equal"], answer: "They are inversely proportional (higher frequency = shorter wavelength)" },
    { q: "What is homeostasis?", choices: ["The process of cell division","The regulation of internal conditions to maintain a stable state","The evolution of new traits","The transfer of genetic information"], answer: "The regulation of internal conditions to maintain a stable state" },
    { q: "What is a catalyst?", choices: ["A product of a chemical reaction","A substance that speeds up a reaction without being consumed","An element that stores energy","A type of chemical bond"], answer: "A substance that speeds up a reaction without being consumed" },
    { q: "What is the central dogma of molecular biology?", choices: ["DNA → Protein → RNA","RNA → DNA → Protein","DNA → RNA → Protein","Protein → RNA → DNA"], answer: "DNA → RNA → Protein" },
    { q: "What distinguishes a hypothesis from a theory in science?", choices: ["There is no difference","A theory is a proven fact; a hypothesis is a guess","A theory is a well-tested explanation supported by evidence; a hypothesis is an initial, testable prediction","A hypothesis is stronger than a theory"], answer: "A theory is a well-tested explanation supported by evidence; a hypothesis is an initial, testable prediction" },
    { q: "What is half-life in radioactive decay?", choices: ["The time for an atom to split completely","The time for half of a radioactive sample to decay","The energy released in half a reaction","The temperature at which decay begins"], answer: "The time for half of a radioactive sample to decay" },
    { q: "What is the Doppler effect?", choices: ["The bending of light around massive objects","The change in observed frequency of a wave due to relative motion between source and observer","The interference of two wave sources","The absorption of light by a prism"], answer: "The change in observed frequency of a wave due to relative motion between source and observer" },
    { q: "What is speciation?", choices: ["The extinction of a species","The process by which new distinct species arise","The classification of organisms","The migration of a population"], answer: "The process by which new distinct species arise" },
    { q: "What is the difference between fission and fusion?", choices: ["Fission joins nuclei; fusion splits them","Fission splits nuclei releasing energy; fusion combines nuclei releasing more energy","They are the same nuclear process","Only fission releases energy"], answer: "Fission splits nuclei releasing energy; fusion combines nuclei releasing more energy" },
    { q: "What is synaptic plasticity?", choices: ["The flexibility of neuron cell membranes","The ability of synapses to strengthen or weaken over time, underlying learning","The physical movement of neurons","The chemical composition of neurotransmitters"], answer: "The ability of synapses to strengthen or weaken over time, underlying learning" },
    { q: "What is the role of the prefrontal cortex?", choices: ["Processing visual information","Regulating heartbeat","Executive functions: planning, decision-making, impulse control","Producing hormones"], answer: "Executive functions: planning, decision-making, impulse control" },
  ]
};

// ─────────────────────────────────────────
//  WRITING PROMPTS
// ─────────────────────────────────────────
const WRITING_PROMPTS = {
  k2: [
    { type: 'summary', story: "The cat sat on the mat. A dog came in. The dog was big and loud. The cat ran up a tree. From the tree, the cat looked down at the dog. Then it began to rain. The dog ran inside. The cat climbed down and sat on the mat again.", prompt: "Write a summary of this story. What happened? Use your own words." },
    { type: 'opinion', story: "", prompt: "What is your favorite animal and why? Write at least 3 sentences about why you like it." },
    { type: 'opinion', story: "", prompt: "Do you think kids should have a pet at school? Write your opinion and give at least 2 reasons." },
  ],
  '35': [
    { type: 'summary', story: "The town of Millbrook had a problem. A large factory had closed, and many families had no work. The mayor held a meeting. A young woman named Dani proposed building a community farm on the old factory land. Some people laughed at the idea. But the mayor was interested. Six months later, 40 families were growing food together. The farm produced so much that they began selling vegetables at a market. Dani became the farm manager.", prompt: "Write a summary of this story. Include the problem, the solution, and the outcome." },
    { type: 'opinion', story: "", prompt: "Should students have to wear school uniforms? Write your opinion and support it with at least 3 reasons." },
    { type: 'opinion', story: "", prompt: "What is the most important subject in school: math, reading, science, or another? Explain your opinion with specific reasons." },
  ],
  '68': [
    { type: 'summary', story: "In 1854, physician John Snow mapped the addresses of cholera victims in London and discovered they clustered around a specific water pump on Broad Street. This was before germ theory was accepted — most scientists believed disease spread through 'bad air.' Snow's data-driven approach defied conventional wisdom. He removed the pump handle, and the outbreak ended. His work is now considered the founding act of epidemiology.", prompt: "Write a summary of this passage. Include Snow's method, his finding, his action, and the significance of his work." },
    { type: 'opinion', story: "", prompt: "Should social media companies be required to verify the age of all users? Write a structured argument with an introduction, at least two supporting paragraphs, and a conclusion." },
    { type: 'opinion', story: "", prompt: "Is it more important for students to learn how to think critically or to memorize facts? Write a well-organized argument with evidence and reasoning." },
  ],
  '912': [
    { type: 'summary', story: "In 2003, Wangari Maathai became the first African woman to win the Nobel Peace Prize — not for diplomacy or conflict resolution, but for environmental activism. Her Green Belt Movement had planted over 30 million trees in Kenya, addressing deforestation, soil erosion, and the water crisis. But Maathai argued that environmental destruction and political oppression were inseparable: corrupt governments exploited natural resources; communities without trees were communities without power. Her work challenged the narrow definition of peace.", prompt: "Summarize this passage. Explain Maathai's argument about the connection between environment and peace, and evaluate its logic." },
    { type: 'opinion', story: "", prompt: "Should advanced AI systems be granted any form of legal rights or protections? Develop a nuanced argument, acknowledging counterarguments and addressing them directly." },
    { type: 'opinion', story: "", prompt: "Is it the responsibility of wealthy nations to pay reparations for historical colonialism? Write a formal argument essay with a clear thesis, evidence, counterargument acknowledgment, and conclusion." },
  ],
  sat: [
    { type: 'summary', story: "Philosophers have long debated whether free will exists. Determinists argue that every decision is the inevitable result of prior causes — genetics, upbringing, brain chemistry. Compatibilists counter that free will and determinism are not mutually exclusive: you can act freely even if your actions are causally determined, as long as you act according to your own desires and reasoning, free from external coercion. Hard incompatibilists reject both, arguing neither view truly preserves the moral responsibility that free will implies. The stakes are significant: our systems of justice, reward, and punishment all rest on assumptions about whether people could have chosen otherwise.", prompt: "Write a clear summary of the free will debate as presented. Then write your own position: do you believe free will exists? Support your view with reasoning and, if possible, examples." },
    { type: 'opinion', story: "", prompt: "\"A society that prioritizes equality of outcome over equality of opportunity will ultimately undermine both.\" Agree or disagree. Write a structured analytical essay with a clear thesis, evidence-based support, engagement with the strongest counterargument, and a conclusion that addresses broader implications." },
    { type: 'opinion', story: "", prompt: "Should universities eliminate standardized test requirements for admissions permanently? Write a sophisticated argument that considers evidence on both sides, acknowledges trade-offs, and arrives at a defensible conclusion." },
  ]
};

// ─────────────────────────────────────────
//  Helper: get grade group key
// ─────────────────────────────────────────
function getGradeGroup(grade){
  return GRADE_GROUP[grade] || 'k2';
}

function getReadingData(grade){
  const g = getGradeGroup(grade);
  return READING[g] || READING['k2'];
}

function getScienceData(grade){
  const g = getGradeGroup(grade);
  return SCIENCE[g] || SCIENCE['k2'];
}

function getWritingPrompts(grade){
  const g = getGradeGroup(grade);
  return WRITING_PROMPTS[g] || WRITING_PROMPTS['k2'];
}

function getSpellingWords(grade){
  return SPELLING[grade] || SPELLING['K'];
}

function shuffle(arr){
  const a=[...arr];
  for(let i=a.length-1;i>0;i--){
    const j=Math.floor(Math.random()*(i+1));
    [a[i],a[j]]=[a[j],a[i]];
  }
  return a;
}

function pickRandom(arr, n){
  return shuffle(arr).slice(0,n);
}

// ─────────────────────────────────────────
//  LEVEL TEST DATA
//  gradeIdx: 0=K  1=1  2=2 ... 12=12  13=SAT
// ─────────────────────────────────────────
const GRADE_ORDER_LT = ['K','1','2','3','4','5','6','7','8','9','10','11','12','SAT'];

function gradeIdxToGrade(idx){ return GRADE_ORDER_LT[Math.min(13,Math.max(0,Math.round(idx)))]; }
function gradeToGradeIdx(g){ const i=GRADE_ORDER_LT.indexOf(g); return i<0?5:i; }
function gradeIdxToIQ(idx){ return 70 + (idx/13)*70; }

// Mini reading passages + 1 question each (gradeIdx: difficulty level)
const LT_READING = [
  // ── K-1 ──
  {id:'r01',gi:0,p:'The cat sat on a mat. It was a fat, happy cat.',q:'Where did the cat sit?',choices:['On a chair','On a mat','In a tree','In water'],a:'On a mat'},
  {id:'r02',gi:0,p:'Tim has a red ball. He plays with it in the yard.',q:'What color is the ball?',choices:['Blue','Green','Red','Yellow'],a:'Red'},
  {id:'r03',gi:1,p:'Sara went to the store with her mom. They bought milk and bread.',q:'What did they buy?',choices:['Juice and eggs','Milk and bread','Cheese and butter','Apples and oranges'],a:'Milk and bread'},
  {id:'r04',gi:1,p:'The dog barked loudly. The mailman walked away quickly.',q:'Why did the mailman walk away?',choices:['He was tired','The dog was barking','He finished work','The house was locked'],a:'The dog was barking'},
  {id:'r05',gi:1,p:'Jake likes to draw. Every day after school he draws animals.',q:'When does Jake draw?',choices:['Before school','During lunch','After school','On weekends only'],a:'After school'},
  // ── Grade 2-3 ──
  {id:'r06',gi:2,p:'Rosa planted seeds in her garden. After two weeks, small green sprouts appeared. She watered them every morning.',q:'What helped the sprouts grow?',choices:['Sunlight only','Watering every morning','Using a gardening book','Asking her neighbor'],a:'Watering every morning'},
  {id:'r07',gi:2,p:'The library closes at 6 p.m. on weekdays and 4 p.m. on weekends. Tom wanted to return his books on Saturday.',q:'What time does the library close on Saturday?',choices:['6 p.m.','5 p.m.','4 p.m.','7 p.m.'],a:'4 p.m.'},
  {id:'r08',gi:3,p:'Luis found a wallet on the sidewalk. Inside were twenty dollars and a driver\'s license. He took the wallet to the police station.',q:'What does this story show about Luis?',choices:['He wanted the money','He was curious about wallets','He was honest and responsible','He was looking for a job'],a:'He was honest and responsible'},
  {id:'r09',gi:3,p:'The monarch butterfly travels up to 3,000 miles every autumn to reach its winter home in Mexico. No single butterfly makes the full round trip — it takes four generations.',q:'What is most remarkable about the monarch migration?',choices:['They travel in large groups','No single butterfly completes the full trip','They only travel in autumn','They live in Mexico year-round'],a:'No single butterfly completes the full trip'},
  {id:'r10',gi:3,p:'Maya\'s science project explained how plants use sunlight to make food. Her teacher said the process is called photosynthesis.',q:'What is photosynthesis?',choices:['How animals find food','How plants make food from sunlight','How water moves through soil','How seeds germinate'],a:'How plants make food from sunlight'},
  // ── Grade 4-5 ──
  {id:'r11',gi:4,p:'The gold rush of 1849 brought thousands of settlers to California. Most never found gold, but the merchants who sold supplies to miners often grew rich.',q:'Who most reliably profited during the gold rush?',choices:['All miners who arrived early','Settlers from Europe','Merchants selling supplies','Government officials'],a:'Merchants selling supplies'},
  {id:'r12',gi:4,p:'"You won\'t make it," said Coach Harris. Maria didn\'t answer. She laced her shoes tighter and stepped to the starting line.',q:'What does Maria\'s action suggest about her?',choices:['She agrees with the coach','She is nervous','She is determined to try anyway','She has given up'],a:'She is determined to try anyway'},
  {id:'r13',gi:5,p:'Ecosystems are networks of living organisms interacting with their environment. When one species disappears, the effects ripple outward — predators lose prey, plants lose pollinators, and the entire web shifts.',q:'What is the main idea of this passage?',choices:['Ecosystems are too complex to understand','Every species in an ecosystem affects others','Predators are the most important species','Plants can survive without pollinators'],a:'Every species in an ecosystem affects others'},
  {id:'r14',gi:5,p:'The word "sincere" may come from the Latin phrase "sine cera" — without wax. Ancient sculptors sometimes hid cracks in marble using wax. A sculpture "sine cera" was one that needed no repairs.',q:'The Latin origin of "sincere" suggests it originally meant?',choices:['Having good intentions','Flawless, requiring no cover-up','Made without tools','Approved by the Romans'],a:'Flawless, requiring no cover-up'},
  {id:'r15',gi:5,p:'In 1903, the Wright Brothers flew for 12 seconds covering 120 feet. By 1969, humans had landed on the Moon. These 66 years represent one of history\'s fastest technological accelerations.',q:'What point does the comparison of dates make?',choices:['Flight technology advanced very slowly','It took 66 years to invent airplanes','Technology accelerated dramatically in a short period','The Wright Brothers inspired the Moon landing directly'],a:'Technology accelerated dramatically in a short period'},
  // ── Grade 6-7 ──
  {id:'r16',gi:6,p:'Propaganda relies not on evidence but on emotional manipulation — fear, pride, outrage. A skilled propagandist knows that most people will accept a claim more readily if it arrives wrapped in strong feeling rather than careful argument.',q:'According to this passage, propaganda works primarily by?',choices:['Presenting overwhelming evidence','Targeting emotions rather than reason','Repeating claims many times','Using simple language'],a:'Targeting emotions rather than reason'},
  {id:'r17',gi:6,p:'The placebo effect demonstrates that the brain can trigger genuine physiological changes based on belief alone. Patients given sugar pills sometimes show measurable improvements — not because of the pill, but because they expect to improve.',q:'What does "physiological" most likely mean in this passage?',choices:['Related to psychology','Related to medicine','Related to the physical body','Related to belief systems'],a:'Related to the physical body'},
  {id:'r18',gi:7,p:'Frederick Douglass wrote: "Power concedes nothing without a demand. It never did and it never will." He meant that oppressive systems do not reform voluntarily — they require sustained pressure.',q:'Douglass\'s statement implies that social change requires?',choices:['Patience and waiting','Active, persistent pressure','Peaceful negotiation only','Leadership from those already in power'],a:'Active, persistent pressure'},
  {id:'r19',gi:7,p:'A paradox is a statement that seems contradictory but reveals a deeper truth. "Less is more" is a paradox — restraint can produce a stronger effect than excess.',q:'Which statement best illustrates a paradox?',choices:['Hard work leads to success','The more you learn, the more you realize you don\'t know','Reading improves vocabulary','Practice makes perfect'],a:'The more you learn, the more you realize you don\'t know'},
  {id:'r20',gi:7,p:'Unlike weather, which describes short-term atmospheric conditions, climate refers to the average patterns of weather over decades. A single cold winter does not contradict a warming climate.',q:'What is the key distinction the passage makes?',choices:['Weather is more dangerous than climate','Climate changes faster than weather','Climate is long-term patterns; weather is short-term','Cold winters prove the climate is not warming'],a:'Climate is long-term patterns; weather is short-term'},
  // ── Grade 8-9 ──
  {id:'r21',gi:8,p:'Hemingway\'s iceberg theory held that the dignity of movement in fiction comes from what is left out. A writer who omits things from knowledge creates a stronger effect than one who omits from ignorance.',q:'Hemingway\'s "iceberg theory" argues that effective writing?',choices:['Uses simple language','Leaves out unimportant details by accident','Gains power from deliberate omission','Requires extensive description'],a:'Gains power from deliberate omission'},
  {id:'r22',gi:8,p:'The invisible hand, as Adam Smith described it, refers to the unintended social benefits produced when individuals pursue their own self-interest in a free market. It is not a literal hand, but a metaphor for the emergent order of markets.',q:'The "invisible hand" is best described as?',choices:['Government regulation of markets','A literal market mechanism','A metaphor for emergent order from self-interest','Adam Smith\'s personal philosophy'],a:'A metaphor for emergent order from self-interest'},
  {id:'r23',gi:9,p:'In quantum mechanics, a particle does not have a definite position until it is observed — it exists in a superposition of all possible positions simultaneously. Observation itself changes the outcome.',q:'What is the most counterintuitive implication of this passage?',choices:['Particles are very small','Physics requires complex mathematics','Observation actively affects the physical world','Quantum mechanics is unpredictable'],a:'Observation actively affects the physical world'},
  {id:'r24',gi:9,p:'"The reasonable man adapts himself to the world. The unreasonable one persists in trying to adapt the world to himself. Therefore all progress depends on the unreasonable man." — George Bernard Shaw',q:'Shaw\'s argument is that progress depends on people who?',choices:['Accept the world as it is','Reason carefully before acting','Refuse to accept existing conditions','Cooperate with authorities'],a:'Refuse to accept existing conditions'},
  // ── Grade 10-11 ──
  {id:'r25',gi:10,p:'The Romantics distrusted Enlightenment rationalism, arguing that reason alone was an insufficient guide to truth and morality. Wordsworth saw in nature a moral teacher that institutions could never replicate.',q:'The Romantics\' primary objection to the Enlightenment was?',choices:['Enlightenment thinkers were morally corrupt','Pure reason fails to capture essential human experience','Science was moving too quickly','Nature was being destroyed by industry'],a:'Pure reason fails to capture essential human experience'},
  {id:'r26',gi:10,p:'A logical fallacy is a flaw in reasoning that makes an argument invalid, even if its conclusion happens to be true. Ad hominem attacks the person making an argument rather than the argument itself.',q:'An ad hominem argument is flawed because?',choices:['It uses too much evidence','It attacks the person instead of the argument','It relies on emotional language','It reaches wrong conclusions'],a:'It attacks the person instead of the argument'},
  {id:'r27',gi:11,p:'Game theory examines strategic interaction between rational actors. In the prisoner\'s dilemma, two suspects each benefit individually from betraying the other, but if both betray, both are worse off than if both had cooperated.',q:'The prisoner\'s dilemma illustrates that?',choices:['Cooperation is always rational','Individual rational choices can produce collectively irrational outcomes','Betrayal always leads to worse outcomes','Rational actors always cooperate'],a:'Individual rational choices can produce collectively irrational outcomes'},
  {id:'r28',gi:11,p:'The concept of "false consciousness," developed by Marx, refers to the internalization by oppressed groups of the values and ideology of their oppressors. People may advocate for systems that actively harm them without recognizing the contradiction.',q:'"False consciousness" describes a situation where?',choices:['People are consciously choosing to be oppressed','People support systems harmful to their own interests without recognizing it','Revolutionary consciousness develops too slowly','Propaganda is spread through media'],a:'People support systems harmful to their own interests without recognizing it'},
  // ── Grade 12-SAT ──
  {id:'r29',gi:12,p:'In contract law, consideration refers to something of value exchanged between parties. A promise to make a gift, unsupported by consideration, is generally unenforceable — the recipient gives nothing in return, so no contract exists.',q:'According to this passage, which situation would NOT form a valid contract?',choices:['A promise to pay for work completed','An agreement to trade goods of equal value','A grandmother\'s promise to give money with no conditions attached','A signed agreement to provide services'],a:'A grandmother\'s promise to give money with no conditions attached'},
  {id:'r30',gi:13,p:'Epistemology asks not what we know, but how we know it. Descartes\' method of radical doubt — stripping away everything that could possibly be doubted — arrived at the irreducible certainty: "I think, therefore I am." Even if everything else is an illusion, the doubting mind itself must exist.',q:'Descartes\'s "I think, therefore I am" functions as?',choices:['A religious argument for God\'s existence','A critique of empiricism','The one certainty that survives radical skepticism','Proof that the physical world is real'],a:'The one certainty that survives radical skepticism'},
  {id:'r31',gi:13,p:'The naturalistic fallacy, identified by G.E. Moore, is the error of concluding that because something IS the case, it OUGHT to be the case. Evolution produced aggression, but this doesn\'t mean aggression is morally justified.',q:'Which argument commits the naturalistic fallacy?',choices:['Murder is illegal, so it is immoral','People have always competed for resources, so competition is morally good','Kindness makes people happy, so we should be kind','Some cultures permit theft, so theft is sometimes acceptable'],a:'People have always competed for resources, so competition is morally good'},
  {id:'r32',gi:12,p:'Satire uses irony, exaggeration, and ridicule to critique human folly. Swift\'s "A Modest Proposal" — in which he "suggests" eating Irish babies to solve poverty — works precisely because readers recognize the horror beneath the reasonable tone.',q:'The power of Swift\'s satire depends on?',choices:['The reader taking the proposal literally','The reader recognizing the ironic gap between tone and content','Swift\'s detailed economic argument','The proposal\'s practical feasibility'],a:'The reader recognizing the ironic gap between tone and content'},
];

// Grammar / writing MC questions for level test
const LT_WRITING = [
  // ── K-1 ──
  {id:'w01',gi:0,q:'Which sentence makes sense?',choices:['Dog the runs fast.','The dog runs fast.','Fast runs the dog.','Runs dog the fast.'],a:'The dog runs fast.'},
  {id:'w02',gi:0,q:'Which word is a noun (a person, place, or thing)?',choices:['run','happy','school','big'],a:'school'},
  {id:'w03',gi:1,q:'Which sentence ends with the right punctuation?',choices:['The cat is soft?','The cat is soft.','The cat is soft!.','The cat, is soft'],a:'The cat is soft.'},
  {id:'w04',gi:1,q:'Which word tells what someone is doing (a verb)?',choices:['jump','blue','the','slowly'],a:'jump'},
  {id:'w05',gi:1,q:'Choose the correctly capitalized sentence.',choices:['my friend is tom.','My friend is tom.','My friend is Tom.','my Friend is Tom.'],a:'My friend is Tom.'},
  // ── Grade 2-3 ──
  {id:'w06',gi:2,q:'Which sentence is correct?',choices:['She goed to school.','She went to school.','She go to school.','She gone to school.'],a:'She went to school.'},
  {id:'w07',gi:2,q:'Where does the comma belong? "After the game we ate pizza."',choices:['After the, game we ate pizza.','After the game, we ate pizza.','After the game we ate, pizza.','After the game we, ate pizza.'],a:'After the game, we ate pizza.'},
  {id:'w08',gi:3,q:'Which sentence uses the correct pronoun?',choices:['Him and I went hiking.','He and me went hiking.','Him and me went hiking.','He and I went hiking.'],a:'He and I went hiking.'},
  {id:'w09',gi:3,q:'Which word correctly completes: "The team ___ their best."?',choices:['done','did','does','do'],a:'did'},
  {id:'w10',gi:3,q:'Choose the sentence with correct subject-verb agreement.',choices:['The dogs barks loudly.','The dogs bark loudly.','The dog bark loudly.','The dogs barking loudly.'],a:'The dogs bark loudly.'},
  // ── Grade 4-5 ──
  {id:'w11',gi:4,q:'Which sentence uses an apostrophe correctly?',choices:['The student\'s books are heavy.','The students book\'s are heavy.','The students\' book are heavy.','The student\'s book\'s are heavy.'],a:'The student\'s books are heavy.'},
  {id:'w12',gi:4,q:'Which is the best topic sentence for a paragraph about recycling?',choices:['Cans can be recycled.','Recycling reduces waste and helps protect the environment.','People throw away too much.','My school has blue bins.'],a:'Recycling reduces waste and helps protect the environment.'},
  {id:'w13',gi:5,q:'Which sentence uses a semicolon correctly?',choices:['I like soccer; but not basketball.','I like soccer; I also enjoy basketball.','I like; soccer and basketball.','I like soccer; and I play it often.'],a:'I like soccer; I also enjoy basketball.'},
  {id:'w14',gi:5,q:'Which word best replaces "said" to show the character is angry?',choices:['whispered','mentioned','snapped','noted'],a:'snapped'},
  {id:'w15',gi:5,q:'Choose the sentence with the correct form of "its/it\'s".',choices:['The dog wagged it\'s tail.','Its raining outside.','The team celebrated its victory.','Its a beautiful day.'],a:'The team celebrated its victory.'},
  // ── Grade 6-7 ──
  {id:'w16',gi:6,q:'Which sentence has correct parallel structure?',choices:['She likes running, to swim, and to hike.','She likes running, swimming, and hiking.','She likes to run, swimming, and hike.','She likes run, swim, and hike.'],a:'She likes running, swimming, and hiking.'},
  {id:'w17',gi:6,q:'Which transition word best shows contrast?',choices:['Furthermore','In addition','However','As a result'],a:'However'},
  {id:'w18',gi:7,q:'Which sentence contains a dangling modifier?',choices:['Running to catch the bus, she dropped her bag.','Running to catch the bus, the bag was dropped.','She dropped her bag while running to catch the bus.','While running, she dropped her bag.'],a:'Running to catch the bus, the bag was dropped.'},
  {id:'w19',gi:7,q:'Which word is spelled correctly?',choices:['accomodate','accommodate','acommodate','accommodaet'],a:'accommodate'},
  {id:'w20',gi:7,q:'Which is the most precise revision of "The book was really very good."?',choices:['The book was good and nice.','The book was exceptionally compelling.','The book was very, very good.','The book was good in many ways.'],a:'The book was exceptionally compelling.'},
  // ── Grade 8-9 ──
  {id:'w21',gi:8,q:'Which sentence avoids the passive voice?',choices:['The ball was kicked by Maria.','Maria was the one who kicked the ball.','Maria kicked the ball.','The ball, kicked by Maria, flew far.'],a:'Maria kicked the ball.'},
  {id:'w22',gi:8,q:'Which rhetorical device is used in: "Ask not what your country can do for you — ask what you can do for your country."?',choices:['Alliteration','Simile','Antithesis','Hyperbole'],a:'Antithesis'},
  {id:'w23',gi:9,q:'Which sentence demonstrates effective use of evidence in an argument?',choices:['Everyone knows that exercise is important.','Studies show that regular exercise reduces heart disease risk by up to 35%.','Exercise is clearly the answer to most health problems.','It is obvious that we should all exercise more.'],a:'Studies show that regular exercise reduces heart disease risk by up to 35%.'},
  {id:'w24',gi:9,q:'What does "ambiguous" mean in: "The contract contained ambiguous language that led to a dispute."?',choices:['Illegal','Having more than one possible meaning','Technical','Complex and long'],a:'Having more than one possible meaning'},
  {id:'w25',gi:9,q:'Which pair of words are antonyms?',choices:['verbose / wordy','benevolent / malevolent','lucid / transparent','arduous / difficult'],a:'benevolent / malevolent'},
  // ── Grade 10-11 ──
  {id:'w26',gi:10,q:'Which sentence uses "whom" correctly?',choices:['Who did you speak to?','Whom is coming to the party?','To whom should I address the letter?','Whom do you think will win?'],a:'To whom should I address the letter?'},
  {id:'w27',gi:10,q:'Which term describes a comparison using "like" or "as"?',choices:['Metaphor','Simile','Personification','Allusion'],a:'Simile'},
  {id:'w28',gi:11,q:'In argument writing, a "concession" means:',choices:['Proving the opposing side is wrong','Acknowledging the validity of the opposing viewpoint before refuting it','Ending the argument with a strong conclusion','Providing additional evidence for your claim'],a:'Acknowledging the validity of the opposing viewpoint before refuting it'},
  {id:'w29',gi:11,q:'Which sentence contains a logical fallacy?',choices:['Exercise reduces stress according to multiple studies.','We should ban cars because my neighbor was in a car accident.','Climate change is supported by 97% of climate scientists.','The study followed 10,000 participants over 20 years.'],a:'We should ban cars because my neighbor was in a car accident.'},
  {id:'w30',gi:11,q:'What is the effect of using short, declarative sentences in a tense narrative moment?',choices:['It slows the reader down to reflect','It creates a fast, urgent pace','It provides more detailed description','It makes the writing less formal'],a:'It creates a fast, urgent pace'},
  // ── Grade 12-SAT ──
  {id:'w31',gi:12,q:'Which revision of "Due to the fact that she studied hard, she passed" is most concise?',choices:['Because she studied hard, she passed.','She passed as a result of the fact that she studied hard.','She passed, due to studying hard.','She studied hard, so she passed the test.'],a:'Because she studied hard, she passed.'},
  {id:'w32',gi:12,q:'The phrase "begs the question" technically means:',choices:['Raises an important question','Invites further inquiry','Assumes the conclusion in the premise','Demands an answer'],a:'Assumes the conclusion in the premise'},
  {id:'w33',gi:13,q:'In academic writing, "hedging" language (e.g., "may," "suggests," "appears") is used to:',choices:['Weaken the argument by showing uncertainty','Show appropriate epistemic humility and avoid overstating findings','Confuse the reader with vague claims','Replace the need for evidence'],a:'Show appropriate epistemic humility and avoid overstating findings'},
  {id:'w34',gi:13,q:'Which best describes the purpose of a thesis statement in an analytical essay?',choices:['To summarize the entire essay in one paragraph','To present a debatable, specific claim that the essay will defend','To introduce background information on the topic','To list the evidence the writer will use'],a:'To present a debatable, specific claim that the essay will defend'},
  {id:'w35',gi:13,q:'Choose the sentence with no grammatical errors.',choices:['Between you and I, the results were surprising.','Neither the manager nor the employees was informed.','The data suggests a clear trend in consumer behavior.','Each of the students must submit their assignments.'],a:'The data suggests a clear trend in consumer behavior.'},
];

// Generate a spelling MC question for a given grade
function generateSpellingMC(grade) {
  const words = getSpellingWords(grade);
  const word = words[rnd(0, words.length - 1)];
  const misses = makeMisspellings(word);
  return mp(`Which spelling is correct?`, word, misses[0], misses[1], misses[2]);
}

function makeMisspellings(word) {
  const w = word;
  const result = new Set();
  const add = (v) => { if (v && v !== w && v.length > 1) result.add(v); };

  // swap two adjacent chars
  if (w.length >= 3) { const i=rnd(0,w.length-2); add(w.slice(0,i)+w[i+1]+w[i]+w.slice(i+2)); }
  // double a letter incorrectly
  { const i=rnd(0,w.length-1); add(w.slice(0,i)+w[i]+w[i]+w.slice(i+1)); }
  // drop a letter
  if (w.length >= 4) { const i=rnd(1,w.length-2); add(w.slice(0,i)+w.slice(i+1)); }
  // ie/ei swap
  if (w.includes('ie')) add(w.replace('ie','ei'));
  else if (w.includes('ei')) add(w.replace('ei','ie'));
  // ance/ence
  if (w.includes('ance')) add(w.replace('ance','ence'));
  else if (w.includes('ence')) add(w.replace('ence','ance'));
  // able/ible
  if (w.includes('able')) add(w.replace('able','ible'));
  else if (w.includes('ible')) add(w.replace('ible','able'));
  // tion/sion
  if (w.includes('tion')) add(w.replace('tion','sion'));
  else if (w.includes('sion')) add(w.replace('sion','tion'));

  // Fallback: replace last letter
  const alpha = 'bcdfghjklmnpqrstvwxyz';
  let fi = 0;
  while (result.size < 3 && fi < alpha.length) {
    add(w.slice(0,-1) + alpha[fi]); fi++;
  }
  return [...result].slice(0,3);
}

// Get a level-appropriate question for the level test
// Returns { question, answer, choices, gradeIdx } or null if pool exhausted
function getLevelTestQ(subject, gradeIdx, usedIds) {
  const targetIdx = Math.max(0, Math.min(13, Math.round(gradeIdx)));
  const grade = gradeIdxToGrade(gradeIdx);

  if (subject === 'math') {
    const p = generateMathProblem(grade, gradeIdx > 8);
    return { ...p, gradeIdx: targetIdx };
  }
  if (subject === 'science') {
    const pool = getScienceData(grade);
    const unused = pool.filter(q => !usedIds.includes(q.q.slice(0,20)));
    const src = unused.length > 0 ? unused : pool;
    const q = src[rnd(0, src.length-1)];
    return { question: q.q, answer: q.answer, choices: shuffle([...q.choices]), gradeIdx: targetIdx };
  }
  if (subject === 'spelling') {
    const p = generateSpellingMC(grade);
    return { ...p, gradeIdx: targetIdx };
  }
  if (subject === 'reading') {
    const range = 2;
    let pool = LT_READING.filter(q =>
      q.gi >= targetIdx - range && q.gi <= targetIdx + range && !usedIds.includes(q.id)
    );
    if (!pool.length) pool = LT_READING.filter(q => !usedIds.includes(q.id));
    if (!pool.length) pool = LT_READING;
    const q = pool[rnd(0, pool.length-1)];
    return { question: q.q, passageText: q.p, answer: q.a, choices: shuffle([q.a,...q.choices.filter(c=>c!==q.a)]), gradeIdx: q.gi, _id: q.id };
  }
  if (subject === 'writing') {
    const range = 2;
    let pool = LT_WRITING.filter(q =>
      q.gi >= targetIdx - range && q.gi <= targetIdx + range && !usedIds.includes(q.id)
    );
    if (!pool.length) pool = LT_WRITING.filter(q => !usedIds.includes(q.id));
    if (!pool.length) pool = LT_WRITING;
    const q = pool[rnd(0, pool.length-1)];
    return { question: q.q, answer: q.a, choices: shuffle([q.a,...q.choices.filter(c=>c!==q.a)]), gradeIdx: q.gi, _id: q.id };
  }
  return null;
}
