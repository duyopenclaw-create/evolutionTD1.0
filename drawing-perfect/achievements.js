// Shared achievement catalog — loaded by both server.js (require) and the browser (script tag).
// 295 regular achievements (visible criteria, unlocked by hitting a stat threshold)
// + 5 secret achievements (hidden criteria — see SECRET ACHIEVEMENTS below).

const SECRET_ICONS = {
  clown: { id: 'clown', emoji: '🤡', name: 'Clown' },
  clover: { id: 'clover', emoji: '🍀', name: 'Four-Leaf Clover' },
};

// Produce `n` strictly-increasing integer thresholds, roughly exponential up to `max`.
function scaleThresholds(n, max) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 1 : i / (n - 1);
    const raw = Math.round(1 + t * t * (max - 1));
    const last = out.length ? out[out.length - 1] : 0;
    out.push(Math.max(raw, last + 1));
  }
  return out;
}

// Regular (visible-criteria) achievement categories. Tier counts sum to exactly 295.
const CATEGORIES = [
  { key: 'wordsDrawn', tiers: 15, max: 500, title: 'Prolific Artist', desc: n => `Draw ${n} word${n === 1 ? '' : 's'} total.` },
  { key: 'gamesPlayed', tiers: 15, max: 500, title: 'Regular Player', desc: n => `Finish ${n} game${n === 1 ? '' : 's'}.` },
  { key: 'gamesWon', tiers: 15, max: 500, title: 'Champion', desc: n => `Win ${n} game${n === 1 ? '' : 's'}.` },
  { key: 'votesReceived', tiers: 15, max: 500, title: 'Fan Favorite', desc: n => `Receive ${n} vote${n === 1 ? '' : 's'} total.` },
  { key: 'votesCast', tiers: 15, max: 500, title: 'Art Critic', desc: n => `Cast ${n} vote${n === 1 ? '' : 's'}.` },
  { key: 'chatMessages', tiers: 15, max: 500, title: 'Chatterbox', desc: n => `Send ${n} chat message${n === 1 ? '' : 's'}.` },
  { key: 'coinsEarned', tiers: 15, max: 20000, title: 'Coin Collector', desc: n => `Earn ${n} coins total.` },
  { key: 'coinsSpent', tiers: 15, max: 15000, title: 'Big Spender', desc: n => `Spend ${n} coins in the shop.` },
  { key: 'wordsDrawn_normal', tiers: 15, max: 300, title: 'Normal Mode Regular', desc: n => `Draw ${n} words in Normal mode.` },
  { key: 'wordsDrawn_challenge', tiers: 15, max: 300, title: 'Challenge Accepted', desc: n => `Draw ${n} words in Challenge mode.` },
  { key: 'wordsDrawn_perfectionist', tiers: 15, max: 300, title: 'Perfectionist', desc: n => `Draw ${n} words in Perfectionist mode.` },
  { key: 'wordsDrawn_foggy', tiers: 15, max: 300, title: 'Blind Sketcher', desc: n => `Draw ${n} words in Foggy mode.` },
  { key: 'wordsDrawn_additive', tiers: 15, max: 300, title: 'Team Player', desc: n => `Draw ${n} words in Additive mode.` },
  { key: 'wordsDrawn_humanbody', tiers: 15, max: 300, title: 'Body Builder', desc: n => `Draw ${n} words in Human Body mode.` },
  { key: 'wordsDrawn_copyit', tiers: 15, max: 300, title: 'Copy Cat', desc: n => `Draw ${n} words in Copy It mode.` },
  { key: 'wordsDrawn_custom', tiers: 10, max: 200, title: 'Freestyler', desc: n => `Draw ${n} custom words.` },
  { key: 'modesPlayed', tiers: 8, max: 8, title: 'Mode Explorer', desc: n => `Play ${n} different game mode${n === 1 ? '' : 's'}.` },
  { key: 'iconsOwned', tiers: 10, max: 14, title: 'Collector', desc: n => `Own ${n} icon${n === 1 ? '' : 's'}.` },
  { key: 'friendsAdded', tiers: 10, max: 50, title: 'Social Butterfly', desc: n => `Add ${n} friend${n === 1 ? '' : 's'}.` },
  { key: 'modPromotions', tiers: 8, max: 25, title: 'Trusted', desc: n => `Get made a mod ${n} time${n === 1 ? '' : 's'}.` },
  { key: 'copyitHighMatches', tiers: 10, max: 50, title: 'Sharp Eye', desc: n => `Score an 80%+ match ${n} time${n === 1 ? '' : 's'} in Copy It.` },
  { key: 'copyitPerfectMatches', tiers: 8, max: 25, title: 'Photocopier', desc: n => `Score a 100% match ${n} time${n === 1 ? '' : 's'} in Copy It.` },
  { key: 'roomsHosted', tiers: 6, max: 12, title: 'Host with the Most', desc: n => `Host ${n} room${n === 1 ? '' : 's'}.` },
];

const ACHIEVEMENTS = (() => {
  const list = [];

  CATEGORIES.forEach(cat => {
    const thresholds = scaleThresholds(cat.tiers, cat.max);
    thresholds.forEach((threshold, i) => {
      list.push({
        id: `${cat.key}_${i + 1}`,
        secret: false,
        statKey: cat.key,
        threshold,
        name: `${cat.title} ${i + 1}`,
        description: cat.desc(threshold),
        reward: null,
      });
    });
  });

  // ---------- SECRET ACHIEVEMENTS (hidden criteria until unlocked) ----------
  list.push({
    id: 'secret_drawingperfect',
    secret: true,
    name: 'The Chosen Name',
    description: 'Name yourself exactly DRAWINGPERFECT (all caps, no spaces).',
    reward: { coins: 1000 },
  });
  list.push({
    id: 'secret_hacker_776',
    secret: true,
    name: "Hacker's Number",
    description: 'Type the code 776 while waiting in the lobby.',
    reward: { unlock: 'hackerCommands' },
  });
  list.push({
    id: 'secret_circus_clown',
    secret: true,
    name: 'Circus Dance',
    description: 'Type two clown emojis (🤡🤡) in chat.',
    reward: { icon: 'clown' },
  });
  list.push({
    id: 'secret_lucky_777',
    secret: true,
    name: 'Lucky Number',
    description: 'Suggest a game mode change and type 777.',
    reward: { icon: 'clover' },
  });
  list.push({
    id: 'secret_owl_midnight',
    secret: true,
    name: 'Night Owl',
    description: 'Play continuously from 11 PM to midnight, straight through.',
    reward: { unlock: 'darkMode' },
  });

  return list;
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { ACHIEVEMENTS, SECRET_ICONS };
}
