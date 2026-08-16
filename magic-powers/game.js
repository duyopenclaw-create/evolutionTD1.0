/* ==========================================================================
   MAGIC POWERS — full client-side 3D action RPG
   Three.js scene, WebAudio synth sfx/music, localStorage save.
   ========================================================================== */
(function(){
"use strict";

/* ---------------------------------------------------------------------- */
/*  CONSTANTS / DATA TABLES                                                */
/* ---------------------------------------------------------------------- */
const SAVE_KEY = "magicPowersSave_v1";
const MAX_LEVEL = 100;
const START_SLOTS = 4;
const SLOT_CAPACITY = 5;

const ELEMENTS = [
  { key:"fire",      name:"Fire",      icon:"🔥", color:0xff5522, glow:0xff8844 },
  { key:"water",     name:"Water",     icon:"💧", color:0x2299ff, glow:0x66ccff },
  { key:"earth",     name:"Earth",     icon:"🪨", color:0x8a6d3b, glow:0xc2a15a },
  { key:"lightning", name:"Lightning", icon:"⚡", color:0xffee55, glow:0xfff9b0 },
  { key:"wind",      name:"Wind",      icon:"🌪️", color:0xaaffee, glow:0xe0fff9 },
  { key:"obsidian",  name:"Obsidian",  icon:"🖤", color:0x6a1fd0, glow:0xb066ff },
];

const MILESTONE_NAMES = {
  fire:      ["Ember Burst","Wildfire","Inferno Core","Meteor Call","Phoenix Rebirth"],
  water:     ["Tidal Wave","Frost Bite","Healing Spring","Maelstrom","Leviathan's Grace"],
  earth:     ["Stone Skin","Quake Slam","Mountain's Grip","Crystal Armor","Titan's Wrath"],
  lightning: ["Static Field","Chain Bolt","Thunderclap","Storm Call","Zeus's Fury"],
  wind:      ["Gale Force","Cyclone","Featherfall","Tempest","Sky Sovereign"],
  obsidian:  ["Void Touch","Shadow Blade","Null Field","Abyssal Grasp","Oblivion's Edge"],
};
function milestoneName(elKey, level){
  const idx = Math.floor(level/5) - 1;
  const named = MILESTONE_NAMES[elKey];
  if (idx >= 0 && idx < named.length) return named[idx];
  return elKey.charAt(0).toUpperCase()+elKey.slice(1)+" Mastery Lv."+level;
}

const REALMS = [
  { name:"Fire Realm",      element:"fire",      sky:0x220a05, fog:0x552011, ground:0x3a1408, wall:0x6b2a12 },
  { name:"Water Realm",     element:"water",     sky:0x03121e, fog:0x0e3b55, ground:0x0a2438, wall:0x145375 },
  { name:"Earth Realm",     element:"earth",     sky:0x150f06, fog:0x3a2c12, ground:0x2b2010, wall:0x53401e },
  { name:"Lightning Realm", element:"lightning", sky:0x14121e, fog:0x3a355c, ground:0x232042, wall:0x413a72 },
  { name:"Wind Realm",      element:"wind",      sky:0x081418, fog:0x1f4a4c, ground:0x0e2c2e, wall:0x1d5658 },
  { name:"Obsidian Realm",  element:"obsidian",  sky:0x0a0410, fog:0x1c0a2e, ground:0x140a20, wall:0x2b1240 },
];

const DIFFICULTIES = {
  easy:      { label:"Easy",       hp:0.55, dmg:0.55, coin:1.35, spawn:0.7,  short:"Relaxed" },
  medium:    { label:"Medium",     hp:1.0,  dmg:1.0,  coin:1.0,  spawn:1.0,  short:"Balanced" },
  hard:      { label:"Hard",       hp:1.7,  dmg:1.4,  coin:1.15, spawn:1.25, short:"Tough" },
  expert:    { label:"Expert",     hp:2.6,  dmg:2.1,  coin:1.3,  spawn:1.5,  short:"Brutal" },
  impossible:{ label:"Impossible", hp:4.2,  dmg:3.3,  coin:1.6,  spawn:1.85, short:"Barely Possible" },
};

const WEAPONS = [
  { id:"w1", name:"Wooden Dagger",   tier:1, dmg:6,  weight:1, price:0 },
  { id:"w2", name:"Iron Sword",      tier:2, dmg:11, weight:2, price:350 },
  { id:"w3", name:"Steel Claymore",  tier:3, dmg:17, weight:3, price:900 },
  { id:"w4", name:"Storm Spear",     tier:4, dmg:24, weight:3, price:1800 },
  { id:"w5", name:"Gale Bow",        tier:5, dmg:31, weight:2, price:3200 },
  { id:"w6", name:"Obsidian Reaper", tier:6, dmg:42, weight:4, price:5200 },
];
const SHIELDS = [
  { id:"s1", name:"Wood Buckler",   tier:1, def:3,  weight:2, price:250 },
  { id:"s2", name:"Iron Wall",      tier:2, def:6,  weight:2, price:700 },
  { id:"s3", name:"Stone Bulwark",  tier:3, def:10, weight:3, price:1500 },
  { id:"s4", name:"Storm Aegis",    tier:4, def:15, weight:3, price:2800 },
  { id:"s5", name:"Wind Ward",      tier:5, def:20, weight:2, price:4200 },
  { id:"s6", name:"Obsidian Bastion",tier:6,def:28, weight:4, price:6500 },
];
const ARMORS = [
  { id:"a1", name:"Cloth Robe",   tier:1, def:2,  hp:10,  weight:1, price:300 },
  { id:"a2", name:"Leather Garb", tier:2, def:5,  hp:25,  weight:2, price:800 },
  { id:"a3", name:"Iron Plate",   tier:3, def:9,  hp:45,  weight:3, price:1700 },
  { id:"a4", name:"Storm Mail",   tier:4, def:14, hp:70,  weight:3, price:3000 },
  { id:"a5", name:"Wind Cloak",   tier:5, def:18, hp:100, weight:2, price:4500 },
  { id:"a6", name:"Obsidian Plate",tier:6,def:26, hp:150, weight:4, price:7000 },
];

function toRoman(num){
  const map=[[1000,"M"],[900,"CM"],[500,"D"],[400,"CD"],[100,"C"],[90,"XC"],[50,"L"],[40,"XL"],
    [10,"X"],[9,"IX"],[5,"V"],[4,"IV"],[1,"I"]];
  let out="";
  for (const [v,s] of map){ while(num>=v){ out+=s; num-=v; } }
  return out;
}
function rand(a,b){ return a + Math.random()*(b-a); }
function randi(a,b){ return Math.floor(rand(a,b+1)); }
function clamp(v,a,b){ return Math.max(a,Math.min(b,v)); }
function pick(arr){ return arr[Math.floor(Math.random()*arr.length)]; }

/* ---------------------------------------------------------------------- */
/*  AUDIO ENGINE (all synthesized, no external files)                     */
/* ---------------------------------------------------------------------- */
const Audio_ = (function(){
  let ctx=null, master=null, musicGain=null, sfxGain=null;
  let musicNodes=[], musicTimer=null, currentRealm=-1, bossMode=false;
  function ensure(){
    if (ctx) return;
    ctx = new (window.AudioContext||window.webkitAudioContext)();
    master = ctx.createGain(); master.connect(ctx.destination);
    musicGain = ctx.createGain(); musicGain.gain.value = 0.55; musicGain.connect(master);
    sfxGain = ctx.createGain(); sfxGain.gain.value = 0.7; sfxGain.connect(master);
  }
  function setMusicVol(v){ ensure(); musicGain.gain.value = v; }
  function setSfxVol(v){ ensure(); sfxGain.gain.value = v; }
  function tone(freq, dur, type, gain, when, sweepTo){
    ensure();
    const t0 = ctx.currentTime + (when||0);
    const osc = ctx.createOscillator(); osc.type = type||"sine";
    osc.frequency.setValueAtTime(freq, t0);
    if (sweepTo) osc.frequency.exponentialRampToValueAtTime(Math.max(20,sweepTo), t0+dur);
    const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain||0.3, t0+0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t0+dur);
    osc.connect(g); g.connect(sfxGain);
    osc.start(t0); osc.stop(t0+dur+0.05);
  }
  function noiseBurst(dur, gain, when){
    ensure();
    const t0 = ctx.currentTime + (when||0);
    const bufSize = ctx.sampleRate*dur;
    const buf = ctx.createBuffer(1,bufSize,ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i=0;i<bufSize;i++) data[i] = (Math.random()*2-1) * (1-i/bufSize);
    const src = ctx.createBufferSource(); src.buffer = buf;
    const g = ctx.createGain(); g.gain.setValueAtTime(gain||0.3, t0);
    g.gain.exponentialRampToValueAtTime(0.001, t0+dur);
    src.connect(g); g.connect(sfxGain);
    src.start(t0);
  }
  const sfx = {
    hit(){ tone(180,0.09,"square",0.25); noiseBurst(0.06,0.15); },
    crit(){ tone(340,0.14,"sawtooth",0.3,0,120); noiseBurst(0.08,0.2); },
    enemyDeath(){ tone(220,0.25,"sawtooth",0.28,0,60); },
    playerHurt(){ tone(120,0.2,"sawtooth",0.3,0,60); },
    coin(){ tone(880,0.08,"square",0.18); tone(1180,0.09,"square",0.18,0.05); },
    chest(){ tone(440,0.12,"triangle",0.25); tone(660,0.14,"triangle",0.25,0.1); tone(880,0.18,"triangle",0.25,0.2); },
    levelup(){ [440,554,659,880].forEach((f,i)=>tone(f,0.18,"triangle",0.28,i*0.09)); },
    milestone(){ [440,554,659,880,1108].forEach((f,i)=>tone(f,0.22,"sine",0.3,i*0.08)); },
    click(){ tone(600,0.05,"square",0.15); },
    spell(elKey){
      const freqs={fire:180,water:520,earth:110,lightning:760,wind:420,obsidian:80};
      const f=freqs[elKey]||300;
      tone(f,0.22,"sawtooth",0.3,0,f*0.4); noiseBurst(0.15,0.18);
    },
    bossRoar(){ tone(70,0.6,"sawtooth",0.4,0,30); noiseBurst(0.5,0.35); },
    victory(){ [440,554,659,880,1108,1320].forEach((f,i)=>tone(f,0.3,"triangle",0.3,i*0.12)); },
    death(){ tone(200,0.5,"sawtooth",0.35,0,50); },
  };
  function stopMusic(){
    musicNodes.forEach(n=>{ try{n.stop();}catch(e){} });
    musicNodes=[];
    if (musicTimer){ clearInterval(musicTimer); musicTimer=null; }
  }
  function startMusic(realmIdx, boss){
    ensure();
    if (currentRealm===realmIdx && bossMode===!!boss && musicTimer) return;
    stopMusic();
    currentRealm = realmIdx; bossMode = !!boss;
    const roots=[130.8,146.8,164.8,174.6,196,220]; // per-realm root pitch
    const root = roots[realmIdx%roots.length];
    const chordSets = boss ? [[1,1.2,1.5],[1,1.19,1.5]] : [[1,1.25,1.5],[1,1.2,1.5],[0.9,1.25,1.5]];
    let step=0;
    const playChord = ()=>{
      const chord = chordSets[step%chordSets.length]; step++;
      chord.forEach((mult,i)=>{
        const o = ctx.createOscillator(); o.type = boss? "sawtooth":"sine";
        o.frequency.value = root*mult*(boss?1: (i===0?0.5:1));
        const g = ctx.createGain(); g.gain.value=0.0001;
        const t0=ctx.currentTime;
        g.gain.linearRampToValueAtTime(boss?0.09:0.07, t0+0.4);
        g.gain.linearRampToValueAtTime(0.0001, t0+(boss?1.6:3.2));
        o.connect(g); g.connect(musicGain);
        o.start(t0); o.stop(t0+(boss?1.7:3.3));
        musicNodes.push(o);
      });
      if (boss){
        noiseBurst(0.08,0.12,0.05);
      }
    };
    playChord();
    musicTimer = setInterval(playChord, boss?900:2600);
  }
  return { ensure, setMusicVol, setSfxVol, sfx, startMusic, stopMusic };
})();

/* ---------------------------------------------------------------------- */
/*  GAME STATE                                                             */
/* ---------------------------------------------------------------------- */
function freshElements(){
  const o={};
  ELEMENTS.forEach(e=> o[e.key] = { level:0 });
  return o;
}
function defaultState(){
  return {
    difficulty:"medium",
    coins:0,
    magicPoints:1,
    mpSpent:0,
    chapter:1, segment:1,
    elements: freshElements(),
    backpackSlots: START_SLOTS,
    backpack: [], // {uid,itemId,type}
    equipped: { weapon1:null, weapon2:null, shield:null, armor:null },
    hp: 100, maxHpBase:100,
    stats:{ kills:0, chestsOpened:0, deaths:0, playtime:0 },
    settings:{ music:0.55, sfx:0.7, forceTouch:false },
    createdAt: null,
  };
}
let S = defaultState();

function saveGame(){
  try{
    localStorage.setItem(SAVE_KEY, JSON.stringify(S));
    flashSaved();
  }catch(e){ console.warn("save failed", e); }
}
function loadGame(){
  try{
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return false;
    const data = JSON.parse(raw);
    S = Object.assign(defaultState(), data);
    S.elements = Object.assign(freshElements(), data.elements||{});
    S.equipped = Object.assign({weapon1:null,weapon2:null,shield:null,armor:null}, data.equipped||{});
    S.stats = Object.assign({kills:0,chestsOpened:0,deaths:0,playtime:0}, data.stats||{});
    S.settings = Object.assign({music:0.55,sfx:0.7,forceTouch:false}, data.settings||{});
    return true;
  }catch(e){ return false; }
}
function hasSave(){
  return !!localStorage.getItem(SAVE_KEY);
}
function flashSaved(){
  const el = document.getElementById("saveFlash");
  el.style.opacity=1;
  clearTimeout(flashSaved._t);
  flashSaved._t = setTimeout(()=>{ el.style.opacity=0; }, 1200);
}

/* derived helpers */
function maxHp(){
  let hp = S.maxHpBase;
  const armor = getEquippedItem("armor");
  if (armor) hp += armor.def_item.hp||0;
  hp += (S.elements.earth.level*1.2);
  return Math.round(hp);
}
function totalDef(){
  let def=0;
  ["shield","armor"].forEach(slot=>{
    const it = getEquippedItem(slot);
    if (it) def += it.def_item.def||0;
  });
  def += S.elements.earth.level*0.35;
  return def;
}
function weaponDamage(){
  let dmg=0; let count=0;
  ["weapon1","weapon2"].forEach(slot=>{
    const it = getEquippedItem(slot);
    if (it){ dmg += it.def_item.dmg||0; count++; }
  });
  if (count===0) dmg = 4; // bare fists
  return dmg;
}
function getEquippedItem(slot){
  const uid = S.equipped[slot];
  if (!uid) return null;
  const inv = S.backpack.find(i=>i.uid===uid);
  if (!inv) return null;
  const def_item = itemDefFor(inv);
  if (!def_item) return null;
  return { inv, def_item };
}
function itemDefFor(invItem){
  if (invItem.type==="weapon") return WEAPONS.find(w=>w.id===invItem.itemId);
  if (invItem.type==="shield") return SHIELDS.find(w=>w.id===invItem.itemId);
  if (invItem.type==="armor") return ARMORS.find(w=>w.id===invItem.itemId);
  return null;
}
function bagUsed(){
  let used=0;
  S.backpack.forEach(it=>{ const d=itemDefFor(it); if(d) used += d.weight; });
  return used;
}
function bagCap(){ return S.backpackSlots*SLOT_CAPACITY; }

function realmIndex(chapter){ return Math.min(5, Math.floor((chapter-1)/10)); }
function isBossSegment(seg){ return seg>=10; }

function elementMilestonesReached(level){ return Math.floor(level/5); }
function elementDamageMult(level){ return 1 + level*0.14 + elementMilestonesReached(level)*0.12; }
function nextLevelCost(level){ // cost to go from `level` to `level+1`
  const next = level+1;
  return (next%5===0) ? 2 : 1;
}

/* ---------------------------------------------------------------------- */
/*  THREE.JS SCENE                                                        */
/* ---------------------------------------------------------------------- */
let renderer, scene, camera, clock;
let worldGroup, playerObj, groundMesh;
let enemies=[], chests=[], projectiles=[], particles=[], obstacles=[];
let playerFacing = new THREE.Vector3(0,0,-1);
let cameraYawOffset = 0;

function initThree(){
  const canvas = document.getElementById("gameCanvas");
  renderer = new THREE.WebGLRenderer({canvas, antialias:true, powerPreference:"high-performance"});
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio||1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  resizeRenderer();

  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(62, window.innerWidth/window.innerHeight, 0.1, 300);

  clock = new THREE.Clock();
  window.addEventListener("resize", resizeRenderer);
  requestAnimationFrame(loop);
}
function resizeRenderer(){
  const w=window.innerWidth, h=window.innerHeight;
  renderer.setSize(w,h,false);
  if (camera){ camera.aspect=w/h; camera.updateProjectionMatrix(); }
}

function clearWorld(){
  if (worldGroup) scene.remove(worldGroup);
  enemies.forEach(e=>disposeObj(e.mesh)); enemies=[];
  chests.forEach(c=>disposeObj(c.mesh)); chests=[];
  projectiles.forEach(p=>disposeObj(p.mesh)); projectiles=[];
  particles.forEach(p=>disposeObj(p.points)); particles=[];
  obstacles=[];
}
function disposeObj(obj){
  if (!obj) return;
  obj.traverse && obj.traverse(o=>{ if(o.geometry) o.geometry.dispose(); });
  if (obj.parent) obj.parent.remove(obj);
}

function buildArena(){
  clearWorld();
  const realm = REALMS[realmIndex(S.chapter)];
  scene.fog = new THREE.Fog(realm.fog, 18, 62);
  scene.background = new THREE.Color(realm.sky);

  worldGroup = new THREE.Group();
  scene.add(worldGroup);

  // lights
  const amb = new THREE.AmbientLight(0xffffff, 0.45);
  worldGroup.add(amb);
  const dir = new THREE.DirectionalLight(0xfff2d8, 0.9);
  dir.position.set(10,18,8);
  dir.castShadow = true;
  dir.shadow.mapSize.set(1024,1024);
  dir.shadow.camera.left=-30; dir.shadow.camera.right=30; dir.shadow.camera.top=30; dir.shadow.camera.bottom=-30;
  worldGroup.add(dir);
  const point = new THREE.PointLight(realm.wall, 0.7, 40);
  point.position.set(0,6,0);
  worldGroup.add(point);

  // arena size grows a bit with chapter
  const boss = isBossSegment(S.segment);
  const size = clamp(16 + S.chapter*0.15 + (boss?6:0), 16, 34);

  const groundGeo = new THREE.PlaneGeometry(size*2, size*2);
  const groundMat = new THREE.MeshStandardMaterial({color:realm.ground, roughness:0.95});
  groundMesh = new THREE.Mesh(groundGeo, groundMat);
  groundMesh.rotation.x = -Math.PI/2;
  groundMesh.receiveShadow = true;
  worldGroup.add(groundMesh);

  // walls
  const wallMat = new THREE.MeshStandardMaterial({color:realm.wall, roughness:0.8});
  const wallH = 6;
  const wallDefs = [
    [size, wallH, 1, 0, wallH/2, -size],
    [size, wallH, 1, 0, wallH/2, size],
    [1, wallH, size, -size, wallH/2, 0],
    [1, wallH, size, size, wallH/2, 0],
  ];
  wallDefs.forEach(([w,h,d,x,y,z])=>{
    const m = new THREE.Mesh(new THREE.BoxGeometry(w,h,d), wallMat);
    m.position.set(x,y,z); m.castShadow=true; m.receiveShadow=true;
    worldGroup.add(m);
  });

  // pillars/obstacles
  const pillarCount = clamp(Math.floor(S.chapter/8)+ (boss?1:2), 2, 6);
  for (let i=0;i<pillarCount;i++){
    const px = rand(-size*0.6, size*0.6), pz = rand(-size*0.6, size*0.6);
    if (Math.abs(px)<4 && Math.abs(pz)<4) continue;
    const h = rand(3,5.5);
    const geo = new THREE.CylinderGeometry(1.1,1.3,h,8);
    const mesh = new THREE.Mesh(geo, wallMat);
    mesh.position.set(px, h/2, pz);
    mesh.castShadow=true; mesh.receiveShadow=true;
    worldGroup.add(mesh);
    obstacles.push({x:px,z:pz,r:1.3});
  }

  arenaBounds = size*0.94;

  // spawn chests
  const chestCount = boss ? 1 : randi(1,3);
  for (let i=0;i<chestCount;i++){
    spawnChest(boss);
  }

  // spawn enemies
  spawnWave(boss);

  return { size, boss, realm };
}
let arenaBounds = 15;

function safeSpawnPos(size, minDistFromCenter){
  let x,z,tries=0;
  do{
    x = rand(-size*0.75, size*0.75);
    z = rand(-size*0.75, size*0.75);
    tries++;
  } while (Math.hypot(x,z) < (minDistFromCenter||3) && tries<30);
  return {x,z};
}

/* ---------- player mesh ---------- */
function buildPlayerMesh(){
  const g = new THREE.Group();
  const robeMat = new THREE.MeshStandardMaterial({color:0x3355cc, roughness:0.7});
  const skinMat = new THREE.MeshStandardMaterial({color:0xe8b58c, roughness:0.6});
  const hatMat = new THREE.MeshStandardMaterial({color:0x1f2a66, roughness:0.6});

  const robe = new THREE.Mesh(new THREE.ConeGeometry(0.55,1.3,10), robeMat);
  robe.position.y = 0.85; robe.castShadow=true;
  g.add(robe);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.32,12,12), skinMat);
  head.position.y = 1.65; head.castShadow=true;
  g.add(head);

  const hat = new THREE.Mesh(new THREE.ConeGeometry(0.36,0.6,10), hatMat);
  hat.position.y = 2.05; hat.castShadow=true;
  g.add(hat);

  const armGeo = new THREE.CapsuleGeometry ? new THREE.CapsuleGeometry(0.1,0.5,4,6) : new THREE.CylinderGeometry(0.1,0.1,0.6,6);
  const armL = new THREE.Mesh(armGeo, robeMat); armL.position.set(-0.5,1.05,0.1); armL.rotation.z=0.5; g.add(armL);
  const armR = new THREE.Mesh(armGeo, robeMat); armR.position.set(0.5,1.05,0.1); armR.rotation.z=-0.5; g.add(armR);

  const staff = new THREE.Mesh(new THREE.CylinderGeometry(0.05,0.05,1.3,6), new THREE.MeshStandardMaterial({color:0x5a3a1e}));
  staff.position.set(0.62,1.1,0.25); staff.rotation.z=-0.15; g.add(staff);
  const orb = new THREE.Mesh(new THREE.SphereGeometry(0.13,10,10), new THREE.MeshStandardMaterial({color:0x66ccff, emissive:0x2299ff, emissiveIntensity:0.8}));
  orb.position.set(0.62,1.78,0.25); g.add(orb);
  g.userData.orb = orb;

  return g;
}

/* ---------- enemy mesh factory ---------- */
function buildEnemyMesh(elKey, boss){
  const meta = ELEMENTS.find(e=>e.key===elKey) || ELEMENTS[0];
  const g = new THREE.Group();
  const scale = boss? 2.1 : 1;
  const bodyMat = new THREE.MeshStandardMaterial({color:meta.color, emissive:meta.glow, emissiveIntensity:boss?0.55:0.25, roughness:0.55});
  const body = new THREE.Mesh(new THREE.DodecahedronGeometry(0.55*scale,0), bodyMat);
  body.position.y = 0.9*scale; body.castShadow=true;
  g.add(body);
  const eyeMat = new THREE.MeshStandardMaterial({color:0xffffff, emissive:0xff2222, emissiveIntensity:1});
  const eyeL = new THREE.Mesh(new THREE.SphereGeometry(0.08*scale,6,6), eyeMat); eyeL.position.set(-0.2*scale,1.0*scale,0.42*scale); g.add(eyeL);
  const eyeR = eyeL.clone(); eyeR.position.x = 0.2*scale; g.add(eyeR);
  const legMat = new THREE.MeshStandardMaterial({color:0x1a1a1a});
  for (let i=0;i<4;i++){
    const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.06*scale,0.06*scale,0.5*scale,6), legMat);
    const ang = (i/4)*Math.PI*2;
    leg.position.set(Math.cos(ang)*0.35*scale, 0.3*scale, Math.sin(ang)*0.35*scale);
    g.add(leg);
  }
  if (boss){
    const crown = new THREE.Mesh(new THREE.ConeGeometry(0.4,0.5,6), new THREE.MeshStandardMaterial({color:0xffd166,emissive:0xffaa00,emissiveIntensity:0.6}));
    crown.position.y = 1.65*scale; g.add(crown);
  }
  g.userData.bodyMesh = body;
  return g;
}

function buildChestMesh(kind){
  const colors = { wooden:0x7a4a24, golden:0xd4af37, diamond:0x8be7ff };
  const mat = new THREE.MeshStandardMaterial({color:colors[kind], emissive:colors[kind], emissiveIntensity: kind==="wooden"?0.05:0.35, roughness:0.4, metalness:kind==="wooden"?0.1:0.6});
  const g = new THREE.Group();
  const base = new THREE.Mesh(new THREE.BoxGeometry(0.8,0.5,0.55), mat);
  base.position.y=0.25; base.castShadow=true; g.add(base);
  const lid = new THREE.Mesh(new THREE.BoxGeometry(0.85,0.25,0.6), mat);
  lid.position.y=0.63; lid.castShadow=true; g.add(lid);
  const light = new THREE.PointLight(colors[kind], kind==="wooden"?0.2:0.9, 4);
  light.position.y=0.6; g.add(light);
  return g;
}

/* ---------------------------------------------------------------------- */
/*  ENTITIES                                                               */
/* ---------------------------------------------------------------------- */
function spawnChest(boss){
  const size = arenaBounds;
  const pos = safeSpawnPos(size, 4);
  let kind;
  const r = Math.random();
  if (boss){ kind = r<0.6? "golden":"diamond"; }
  else { kind = r<0.68 ? "wooden" : (r<0.93 ? "golden" : "diamond"); }
  const mesh = buildChestMesh(kind);
  mesh.position.set(pos.x,0,pos.z);
  worldGroup.add(mesh);
  chests.push({ mesh, kind, opened:false, spin:Math.random()*10 });
}

function difficultyMult(){ return DIFFICULTIES[S.difficulty]; }

function spawnWave(boss){
  const dm = difficultyMult();
  const realm = REALMS[realmIndex(S.chapter)];
  if (boss){
    const hp = Math.round((260 + S.chapter*46 + S.segment*4) * dm.hp * (S.chapter>=60?1.9:1));
    const dmg = Math.round((14 + S.chapter*1.6) * dm.dmg * (S.chapter>=60?1.3:1));
    const pos = {x:0, z: -arenaBounds*0.55};
    const mesh = buildEnemyMesh(realm.element, true);
    mesh.position.set(pos.x,0,pos.z);
    worldGroup.add(mesh);
    const isFinal = (S.chapter>=60);
    enemies.push({
      mesh, hp, maxHp:hp, dmg, boss:true, isFinal,
      speed: 2.1 + S.chapter*0.008,
      atkCd:0, phaseTimer: rand(1.5,2.5),
      name: isFinal ? "THE OBSIDIAN SOVEREIGN" : (realm.name.replace(" Realm","")+" Warlord"),
      hitFlash:0, alive:true, radius:0.9,
    });
    showBossBanner(enemies[enemies.length-1].name);
    Audio_.sfx.bossRoar();
    Audio_.startMusic(realmIndex(S.chapter), true);
  } else {
    const count = clamp(Math.round((2 + S.segment*0.35 + S.chapter*0.06) * dm.spawn), 2, 9);
    for (let i=0;i<count;i++){
      const hp = Math.round((16 + S.chapter*7 + S.segment*2.4) * dm.hp);
      const dmg = Math.round((3 + S.chapter*1.05) * dm.dmg);
      const pos = safeSpawnPos(arenaBounds, 6);
      const mesh = buildEnemyMesh(realm.element, false);
      mesh.position.set(pos.x,0,pos.z);
      worldGroup.add(mesh);
      enemies.push({
        mesh, hp, maxHp:hp, dmg, boss:false,
        speed: rand(1.6,2.6),
        atkCd: rand(0,1), hitFlash:0, alive:true, radius:0.55,
      });
    }
    Audio_.startMusic(realmIndex(S.chapter), false);
  }
}

function showBossBanner(name){
  const el = document.getElementById("bossBanner");
  el.textContent = "⚠ "+name+" ⚠";
  el.style.opacity=1;
  clearTimeout(showBossBanner._t);
  showBossBanner._t = setTimeout(()=>{ el.style.opacity=0; }, 2600);
}

/* ---------------------------------------------------------------------- */
/*  PARTICLES / PROJECTILES / FLOAT TEXT                                  */
/* ---------------------------------------------------------------------- */
function spawnParticles(pos, color, count, spread, life){
  const geo = new THREE.BufferGeometry();
  const positions = new Float32Array(count*3);
  const velocities = [];
  for (let i=0;i<count;i++){
    positions[i*3]=pos.x; positions[i*3+1]=pos.y+0.6; positions[i*3+2]=pos.z;
    velocities.push(new THREE.Vector3(rand(-1,1),rand(0.3,1.6),rand(-1,1)).multiplyScalar(spread));
  }
  geo.setAttribute("position", new THREE.BufferAttribute(positions,3));
  const mat = new THREE.PointsMaterial({color, size:0.16, transparent:true, opacity:1});
  const points = new THREE.Points(geo, mat);
  worldGroup.add(points);
  particles.push({ points, velocities, life:life||0.6, t:0 });
}

function spawnProjectile(from, to, color, dmg, kind, splash){
  const geo = new THREE.SphereGeometry(kind==="obsidian"?0.28:0.18, 8,8);
  const mat = new THREE.MeshStandardMaterial({color, emissive:color, emissiveIntensity:1.2});
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.copy(from); mesh.position.y=0.9;
  const light = new THREE.PointLight(color,1.2,5); mesh.add(light);
  worldGroup.add(mesh);
  const dir = new THREE.Vector3(to.x-from.x,0,to.z-from.z).normalize();
  projectiles.push({ mesh, dir, speed:16, dmg, kind, splash, t:0, maxT:2.2, from:"player" });
}

function floatText(text, color){
  const el = document.getElementById("floatText");
  el.textContent = text;
  el.style.color = color || "#ffd166";
  el.style.opacity=1;
  clearTimeout(floatText._t);
  floatText._t = setTimeout(()=>{ el.style.opacity=0; }, 1100);
}
let comboCount=0, comboTimer=0;
function bumpCombo(){
  comboCount++;
  comboTimer = 2.2;
  const el = document.getElementById("comboText");
  if (comboCount>=3){
    el.textContent = comboCount+"x COMBO!";
    el.style.opacity=1;
  }
}

/* ---------------------------------------------------------------------- */
/*  PLAYER STATE (runtime, separate from persisted S)                     */
/* ---------------------------------------------------------------------- */
let runtime = {
  pos: new THREE.Vector3(0,0,6),
  hp: 100,
  atkCd: 0,
  spellCd: [0,0,0,0,0,0],
  invuln: 0,
};

function resetRuntimeForSegment(){
  runtime.pos.set(0,0, arenaBounds*0.55);
  playerObj.position.copy(runtime.pos);
}

/* ---------------------------------------------------------------------- */
/*  INPUT                                                                  */
/* ---------------------------------------------------------------------- */
const keys = {};
let moveVec = {x:0,y:0}; // from joystick, -1..1
let wantAttack=false;
let attackHoldTimer=0;

window.addEventListener("keydown", e=>{
  keys[e.code]=true;
  if (gameMode!=="playing") return;
  if (e.code==="Escape") togglePause();
  if (e.code==="KeyB") toggleModal("bookPanel");
  if (e.code==="KeyI") toggleModal("bagPanel");
  if (e.code==="Space") wantAttack=true;
  const num = {Digit1:0,Digit2:1,Digit3:2,Digit4:3,Digit5:4,Digit6:5}[e.code];
  if (num!==undefined) tryCastSpell(num);
});
window.addEventListener("keyup", e=>{ keys[e.code]=false; });

function isTouchDevice(){
  return S.settings.forceTouch || ("ontouchstart" in window) || navigator.maxTouchPoints>0;
}
function setupTouch(){
  document.body.classList.toggle("touch", isTouchDevice());
  const outer = document.getElementById("joyOuter");
  const inner = document.getElementById("joyInner");
  let dragging=false, originX=0, originY=0;
  const maxR = 40;
  function start(e){
    dragging=true;
    const r = outer.getBoundingClientRect();
    originX = r.left+r.width/2; originY = r.top+r.height/2;
  }
  function move(e){
    if (!dragging) return;
    const t = e.touches? e.touches[0] : e;
    let dx=t.clientX-originX, dy=t.clientY-originY;
    const dist = Math.hypot(dx,dy);
    if (dist>maxR){ dx=dx/dist*maxR; dy=dy/dist*maxR; }
    inner.style.left = (35+dx)+"px";
    inner.style.top = (35+dy)+"px";
    moveVec.x = dx/maxR; moveVec.y = dy/maxR;
  }
  function end(){
    dragging=false; moveVec.x=0; moveVec.y=0;
    inner.style.left="35px"; inner.style.top="35px";
  }
  outer.addEventListener("touchstart", e=>{start(e); move(e);}, {passive:true});
  outer.addEventListener("touchmove", move, {passive:true});
  outer.addEventListener("touchend", end);
  outer.addEventListener("mousedown", e=>{start(e); move(e);
    const mm=(ev)=>move(ev), mu=()=>{end(); window.removeEventListener("mousemove",mm); window.removeEventListener("mouseup",mu);};
    window.addEventListener("mousemove",mm); window.addEventListener("mouseup",mu);
  });
  const atkBtn = document.getElementById("atkBtn");
  const press = ()=>{ wantAttack=true; };
  atkBtn.addEventListener("touchstart", e=>{e.preventDefault(); press();}, {passive:false});
  atkBtn.addEventListener("mousedown", press);
}
document.getElementById("gameCanvas").addEventListener("mousedown", e=>{
  if (gameMode==="playing" && !isTouchDevice()) wantAttack=true;
});

/* ---------------------------------------------------------------------- */
/*  SPELLS                                                                 */
/* ---------------------------------------------------------------------- */
const SPELL_BASE_CD = {fire:2.4, water:3.0, earth:3.4, lightning:2.8, wind:2.6, obsidian:5.0};

function nearestEnemy(maxDist){
  let best=null, bestD=Infinity;
  enemies.forEach(en=>{
    if (!en.alive) return;
    const d = en.mesh.position.distanceTo(playerObj.position);
    if (d<bestD && (!maxDist || d<=maxDist)){ bestD=d; best=en; }
  });
  return best;
}

function tryCastSpell(idx){
  const meta = ELEMENTS[idx];
  const lvl = S.elements[meta.key].level;
  if (lvl<=0) { floatText("Locked!","#888"); return; }
  if (runtime.spellCd[idx]>0) return;
  const cd = Math.max(0.8, SPELL_BASE_CD[meta.key] - lvl*0.018);
  runtime.spellCd[idx]=cd;
  castSpell(meta.key, lvl);
}

function castSpell(elKey, level){
  Audio_.ensure();
  Audio_.sfx.spell(elKey);
  const mult = elementDamageMult(level);
  const meta = ELEMENTS.find(e=>e.key===elKey);
  const p = playerObj.position;
  switch(elKey){
    case "fire": {
      const target = nearestEnemy(20);
      const baseDmg = 14*mult;
      if (target){
        spawnProjectile(p, target.mesh.position, meta.color, baseDmg, "fire", elementMilestonesReached(level)>=1);
      } else {
        spawnParticles(p, meta.color, 20, 3, 0.5);
      }
      break;
    }
    case "water": {
      const baseDmg = 8*mult;
      let hitAny=false;
      enemies.forEach(en=>{
        if (!en.alive) return;
        const d = en.mesh.position.distanceTo(p);
        if (d<6+level*0.03){
          damageEnemy(en, baseDmg);
          en.slowT = 3; hitAny=true;
        }
      });
      spawnParticles(p, meta.color, 26, 2.4, 0.6);
      if (elementMilestonesReached(level)>=2){ // healing spring milestone
        runtime.hp = Math.min(maxHp(), runtime.hp + 6 + level*0.3);
        floatText("+"+Math.round(6+level*0.3)+" HP","#66ffcc");
      }
      break;
    }
    case "earth": {
      const baseDmg = 20*mult;
      const radius = 5.5 + level*0.04;
      enemies.forEach(en=>{
        if (!en.alive) return;
        const d = en.mesh.position.distanceTo(p);
        if (d<radius) damageEnemy(en, baseDmg);
      });
      spawnParticles(p, meta.color, 34, 3.4, 0.7);
      shakeCamera(0.25);
      break;
    }
    case "lightning": {
      const baseDmg = 12*mult;
      let chain = 2 + Math.floor(level/20);
      const targets = enemies.filter(e=>e.alive).sort((a,b)=>a.mesh.position.distanceTo(p)-b.mesh.position.distanceTo(p)).slice(0,chain);
      targets.forEach(t=>{
        damageEnemy(t, baseDmg);
        spawnParticles(t.mesh.position, meta.color, 14, 2.2, 0.4);
      });
      break;
    }
    case "wind": {
      const baseDmg = 9*mult;
      const radius = 7 + level*0.05;
      enemies.forEach(en=>{
        if (!en.alive) return;
        const d = en.mesh.position.distanceTo(p);
        if (d<radius){
          damageEnemy(en, baseDmg);
          const push = new THREE.Vector3(en.mesh.position.x-p.x,0,en.mesh.position.z-p.z).normalize().multiplyScalar(3+level*0.03);
          en.mesh.position.add(push);
        }
      });
      spawnParticles(p, meta.color, 30, 4.2, 0.6);
      break;
    }
    case "obsidian": {
      const target = nearestEnemy(24);
      const baseDmg = 46*mult;
      if (target){
        damageEnemy(target, baseDmg, true);
        spawnParticles(target.mesh.position, meta.color, 40, 3.6, 0.8);
      } else {
        spawnParticles(p, meta.color, 30, 3, 0.6);
      }
      shakeCamera(0.35);
      break;
    }
  }
}

/* ---------------------------------------------------------------------- */
/*  COMBAT                                                                 */
/* ---------------------------------------------------------------------- */
let camShake=0;
function shakeCamera(amt){ camShake = Math.max(camShake, amt); }

function damageEnemy(en, dmg, crit){
  if (!en.alive) return;
  en.hp -= dmg;
  en.hitFlash = 0.15;
  if (crit) Audio_.sfx.crit(); else Audio_.sfx.hit();
  floatText((crit?"CRIT ":"")+"-"+Math.round(dmg), crit?"#ff5b5b":"#ffd166");
  spawnParticles(en.mesh.position, 0xffffff, 6, 1.4, 0.3);
  if (en.hp<=0 && en.alive){
    en.alive=false;
    killEnemy(en);
  }
}
function killEnemy(en){
  Audio_.sfx.enemyDeath();
  spawnParticles(en.mesh.position, 0xff8844, 22, 3, 0.7);
  disposeObj(en.mesh);
  S.stats.kills++;
  bumpCombo();
  const dm = difficultyMult();
  const coinDrop = Math.round(rand(2,8) * (1+S.chapter*0.12) * dm.coin) * (en.boss?6:1);
  S.coins += coinDrop;
  updateHud();
  if (en.boss){
    floatText(en.isFinal? "THE SOVEREIGN FALLS!" : "BOSS DEFEATED!", "#ff8844");
    onBossDefeated();
  }
}

function playerAttack(){
  if (runtime.atkCd>0) return;
  runtime.atkCd = 0.55;
  const dmg = weaponDamage() * (1+S.chapter*0.02);
  const range = 2.4;
  let hitSomething=false;
  enemies.forEach(en=>{
    if (!en.alive) return;
    const d = en.mesh.position.distanceTo(playerObj.position);
    if (d<range){
      damageEnemy(en, dmg);
      hitSomething=true;
      const dir = new THREE.Vector3(en.mesh.position.x-playerObj.position.x,0,en.mesh.position.z-playerObj.position.z).normalize();
      playerFacing.copy(dir);
    }
  });
  // swing particle
  const swingPos = playerObj.position.clone().add(playerFacing.clone().multiplyScalar(1.2));
  spawnParticles(swingPos, 0xffffff, 8, 1.6, 0.25);
}

function enemyAttackPlayer(en, dmg){
  if (runtime.invuln>0) return;
  const def = totalDef();
  const dmgTaken = Math.max(1, dmg - def*0.6);
  runtime.hp -= dmgTaken;
  runtime.invuln = 0.5;
  Audio_.sfx.playerHurt();
  shakeCamera(0.18);
  floatText("-"+Math.round(dmgTaken)+" HP", "#ff5566");
  if (runtime.hp<=0){ onPlayerDeath(); }
}

/* ---------------------------------------------------------------------- */
/*  CHESTS                                                                 */
/* ---------------------------------------------------------------------- */
function openChest(ch){
  if (ch.opened) return;
  ch.opened = true;
  S.stats.chestsOpened++;
  Audio_.sfx.chest();
  spawnParticles(ch.mesh.position, ch.kind==="diamond"?0x8be7ff:(ch.kind==="golden"?0xd4af37:0x9a6a34), 26, 2.4, 0.8);
  let coinGain=0, mpGain=0;
  if (ch.kind==="wooden"){ coinGain = randi(10,100); }
  else if (ch.kind==="golden"){ coinGain = randi(50,250); mpGain = randi(1,2); }
  else { coinGain = randi(100,500); mpGain = randi(3,8); }
  coinGain = Math.round(coinGain * difficultyMult().coin);
  S.coins += coinGain;
  S.magicPoints += mpGain;
  floatText("+"+coinGain+"🪙"+(mpGain?" +"+mpGain+"✨":""), "#ffd166");
  // chance to drop gear item too
  if (Math.random() < (ch.kind==="wooden"?0.12:ch.kind==="golden"?0.35:0.6)){
    maybeDropGear();
  }
  disposeObj(ch.mesh);
  updateHud();
}
function maybeDropGear(){
  const tierMax = clamp(Math.ceil(S.chapter/10), 1, 6);
  const tier = randi(1, tierMax);
  const roll = Math.random();
  let pool, type;
  if (roll<0.5){ pool=WEAPONS; type="weapon"; }
  else if (roll<0.75){ pool=ARMORS; type="armor"; }
  else { pool=SHIELDS; type="shield"; }
  const options = pool.filter(i=>i.tier===tier);
  const item = options.length? pick(options) : pool[0];
  addToBackpack(item.id, type);
}
function addToBackpack(itemId, type){
  const used = bagUsed();
  const def_ = type==="weapon"?WEAPONS.find(w=>w.id===itemId):type==="shield"?SHIELDS.find(w=>w.id===itemId):ARMORS.find(w=>w.id===itemId);
  if (!def_) return false;
  if (used + def_.weight > bagCap()){
    floatText("Backpack Full!", "#ff5566");
    return false;
  }
  S.backpack.push({ uid: "i"+Date.now()+Math.floor(Math.random()*10000), itemId, type });
  floatText("Found: "+def_.name+"!", "#8ecbff");
  return true;
}

/* ---------------------------------------------------------------------- */
/*  SEGMENT / CHAPTER PROGRESSION                                          */
/* ---------------------------------------------------------------------- */
let gameMode = "menu"; // menu, playing, paused, modal, dead, victory
let segmentCleared=false;

function startSegment(){
  segmentCleared=false;
  runtime.hp = clamp(runtime.hp, 1, maxHp());
  const info = buildArena();
  resetRuntimeForSegment();
  camShake=0;
  updateHud();
}

function checkSegmentClear(){
  if (segmentCleared) return;
  if (enemies.length>0 && enemies.every(e=>!e.alive)) {
    segmentCleared = true;
    setTimeout(()=> onSegmentClear(), 400);
  }
}

function onSegmentClear(){
  const boss = isBossSegment(S.segment);
  const dm = difficultyMult();
  const coinReward = Math.round(rand(20,60) * (1+S.chapter*0.08) * dm.coin) * (boss?3:1);
  S.coins += coinReward;
  S.magicPoints += 1;
  floatText("SEGMENT CLEARED! +1✨ +"+coinReward+"🪙", "#ffd166");
  saveGame();
  updateHud();
  if (boss){
    openChapterComplete(coinReward);
  } else {
    S.segment += 1;
    setTimeout(()=> startSegment(), 900);
  }
}
function onBossDefeated(){ /* handled by checkSegmentClear -> onSegmentClear */ }

function openChapterComplete(coinReward){
  gameMode="modal";
  document.getElementById("ccTitle").textContent =
    (S.chapter>=60) ? "🏆 FINAL BOSS DEFEATED!" : "Chapter "+toRoman(S.chapter)+" Complete!";
  document.getElementById("ccRewards").textContent = "+1 Magic Point, +"+coinReward+" coins";
  document.getElementById("chapterCompletePanel").classList.remove("hidden");
  if (S.chapter>=60){
    document.getElementById("btnCcContinue").textContent = "🏁 Claim Victory";
  } else {
    document.getElementById("btnCcContinue").textContent = "➡ Continue";
  }
}
document.getElementById("btnCcShop").addEventListener("click", ()=>{ openShop(); });
document.getElementById("btnCcContinue").addEventListener("click", ()=>{
  document.getElementById("chapterCompletePanel").classList.add("hidden");
  if (S.chapter>=60){
    triggerVictory();
    return;
  }
  const prevRealm = realmIndex(S.chapter);
  S.chapter += 1; S.segment = 1;
  const newRealm = realmIndex(S.chapter);
  gameMode="playing";
  if (newRealm!==prevRealm){
    showBossBanner("Entering "+REALMS[newRealm].name+"!");
  }
  startSegment();
  saveGame();
});

function onPlayerDeath(){
  gameMode="modal";
  S.stats.deaths++;
  S.coins = Math.round(S.coins*0.9);
  Audio_.sfx.death();
  updateHud();
  document.getElementById("downPanel").classList.remove("hidden");
}
document.getElementById("btnRespawn").addEventListener("click", ()=>{
  document.getElementById("downPanel").classList.add("hidden");
  runtime.hp = maxHp();
  gameMode="playing";
  startSegment();
});

function triggerVictory(){
  gameMode="victory";
  document.getElementById("vCoins").textContent = S.coins;
  document.getElementById("vMp").textContent = S.mpSpent;
  document.getElementById("victoryPanel").classList.remove("hidden");
  document.getElementById("hud").classList.add("hidden");
  Audio_.sfx.victory();
  Audio_.stopMusic();
}
document.getElementById("btnVictoryMenu").addEventListener("click", ()=>{
  document.getElementById("victoryPanel").classList.add("hidden");
  goToMainMenu();
});

/* ---------------------------------------------------------------------- */
/*  MAIN LOOP                                                              */
/* ---------------------------------------------------------------------- */
function loop(){
  requestAnimationFrame(loop);
  const dt = Math.min(0.05, clock.getDelta());
  if (gameMode==="playing"){
    updatePlaying(dt);
  }
  if (renderer) renderer.render(scene, camera);
}

function updatePlaying(dt){
  S.stats.playtime += dt;

  // movement input
  let mx=0, mz=0;
  if (keys["KeyW"]||keys["ArrowUp"]) mz-=1;
  if (keys["KeyS"]||keys["ArrowDown"]) mz+=1;
  if (keys["KeyA"]||keys["ArrowLeft"]) mx-=1;
  if (keys["KeyD"]||keys["ArrowRight"]) mx+=1;
  mx += moveVec.x; mz += moveVec.y;
  const len = Math.hypot(mx,mz);
  if (len>0.001){
    mx/=Math.max(len,1); mz/=Math.max(len,1);
    const speed = 5.4;
    let nx = playerObj.position.x + mx*speed*dt;
    let nz = playerObj.position.z + mz*speed*dt;
    nx = clamp(nx, -arenaBounds, arenaBounds);
    nz = clamp(nz, -arenaBounds, arenaBounds);
    // obstacle collision
    let blocked=false;
    for (const ob of obstacles){
      if (Math.hypot(nx-ob.x, nz-ob.z) < ob.r+0.5){ blocked=true; break; }
    }
    if (!blocked){
      playerObj.position.x = nx; playerObj.position.z = nz;
      playerFacing.set(mx,0,mz).normalize();
    }
    const targetAngle = Math.atan2(playerFacing.x, playerFacing.z);
    playerObj.rotation.y += (targetAngle - playerObj.rotation.y) * clamp(dt*10,0,1);
  }

  // timers
  runtime.atkCd = Math.max(0, runtime.atkCd-dt);
  runtime.invuln = Math.max(0, runtime.invuln-dt);
  for (let i=0;i<6;i++) runtime.spellCd[i] = Math.max(0, runtime.spellCd[i]-dt);
  comboTimer -= dt;
  if (comboTimer<=0 && comboCount>0){
    comboCount=0;
    document.getElementById("comboText").style.opacity=0;
  }

  if (wantAttack){ playerAttack(); wantAttack=false; }

  // orb bob
  if (playerObj.userData.orb) playerObj.userData.orb.position.y = 1.78 + Math.sin(performance.now()*0.004)*0.05;

  // enemies AI
  enemies.forEach(en=>{
    if (!en.alive) return;
    en.hitFlash = Math.max(0, en.hitFlash-dt);
    en.mesh.material && null;
    if (en.mesh.userData.bodyMesh){
      en.mesh.userData.bodyMesh.material.emissiveIntensity = en.hitFlash>0 ? 1.4 : (en.boss?0.55:0.25);
      en.mesh.rotation.y += dt*0.6;
    }
    en.slowT = Math.max(0, (en.slowT||0)-dt);
    const speedMult = en.slowT>0 ? 0.4 : 1;
    const toPlayer = new THREE.Vector3(playerObj.position.x-en.mesh.position.x,0,playerObj.position.z-en.mesh.position.z);
    const dist = toPlayer.length();
    en.atkCd = Math.max(0, en.atkCd-dt);
    if (en.boss){
      updateBoss(en, dt, dist, toPlayer);
    } else {
      if (dist>1.3){
        toPlayer.normalize();
        en.mesh.position.x += toPlayer.x*en.speed*speedMult*dt;
        en.mesh.position.z += toPlayer.z*en.speed*speedMult*dt;
      } else if (en.atkCd<=0){
        en.atkCd = 1.1;
        enemyAttackPlayer(en, en.dmg);
      }
    }
  });

  // projectiles
  for (let i=projectiles.length-1;i>=0;i--){
    const pr = projectiles[i];
    pr.t += dt;
    pr.mesh.position.x += pr.dir.x*pr.speed*dt;
    pr.mesh.position.z += pr.dir.z*pr.speed*dt;
    let hit=false;
    enemies.forEach(en=>{
      if (hit || !en.alive) return;
      if (en.mesh.position.distanceTo(pr.mesh.position)<0.9){
        damageEnemy(en, pr.dmg);
        if (pr.splash){
          enemies.forEach(e2=>{ if (e2!==en && e2.alive && e2.mesh.position.distanceTo(en.mesh.position)<3.5) damageEnemy(e2, pr.dmg*0.5); });
          spawnParticles(en.mesh.position, 0xff8844, 20, 3, 0.5);
        }
        hit=true;
      }
    });
    if (hit || pr.t>pr.maxT){ disposeObj(pr.mesh); projectiles.splice(i,1); }
  }

  // particles
  for (let i=particles.length-1;i>=0;i--){
    const p = particles[i];
    p.t += dt;
    const posAttr = p.points.geometry.attributes.position;
    for (let j=0;j<p.velocities.length;j++){
      posAttr.array[j*3]   += p.velocities[j].x*dt;
      posAttr.array[j*3+1] += (p.velocities[j].y - 2.2*p.t)*dt;
      posAttr.array[j*3+2] += p.velocities[j].z*dt;
    }
    posAttr.needsUpdate = true;
    p.points.material.opacity = clamp(1 - p.t/p.life, 0, 1);
    if (p.t>=p.life){ disposeObj(p.points); particles.splice(i,1); }
  }

  // chest interaction (auto-open when near)
  chests.forEach(ch=>{
    if (ch.opened) return;
    ch.spin += dt;
    ch.mesh.rotation.y = ch.spin;
    ch.mesh.position.y = Math.sin(performance.now()*0.002+ch.spin)*0.08;
    if (ch.mesh.position.distanceTo(playerObj.position) < 1.4){
      openChest(ch);
    }
  });

  checkSegmentClear();

  // camera follow (fixed chase angle)
  const camDist = 9, camHeight = 7.5;
  const desired = new THREE.Vector3(
    playerObj.position.x*0.15,
    camHeight,
    playerObj.position.z + camDist
  );
  camera.position.lerp(desired, clamp(dt*3.5,0,1));
  let lookTarget = playerObj.position.clone(); lookTarget.y+=1;
  if (camShake>0.001){
    lookTarget.x += rand(-camShake,camShake); lookTarget.y += rand(-camShake,camShake);
    camShake *= 0.85;
  }
  camera.lookAt(lookTarget);

  // hp regen trickle from water passively at higher levels, and hud sync
  if (runtime.hp>0){
    document.getElementById("hpText").textContent = Math.max(0,Math.round(runtime.hp))+"/"+maxHp();
    document.getElementById("hpFill").style.width = clamp(runtime.hp/maxHp()*100,0,100)+"%";
  }

  // periodic light autosave handled by interval separately
}

function updateBoss(en, dt, dist, toPlayer){
  en.phaseTimer -= dt;
  if (dist>1.8){
    const dir = toPlayer.clone().normalize();
    en.mesh.position.x += dir.x*en.speed*0.6*dt;
    en.mesh.position.z += dir.z*en.speed*0.6*dt;
  }
  if (en.phaseTimer<=0){
    en.phaseTimer = rand(2.2,3.4);
    const pattern = Math.random();
    if (pattern<0.5 && dist<3.2){
      enemyAttackPlayer(en, en.dmg*1.6);
      shakeCamera(0.3);
      spawnParticles(en.mesh.position, 0xff5555, 24, 3.5, 0.6);
    } else {
      // ranged volley
      for (let i=-1;i<=1;i++){
        const spreadDir = toPlayer.clone().normalize();
        const angle = i*0.25;
        const rx = spreadDir.x*Math.cos(angle)-spreadDir.z*Math.sin(angle);
        const rz = spreadDir.x*Math.sin(angle)+spreadDir.z*Math.cos(angle);
        const target = new THREE.Vector3(en.mesh.position.x+rx*10, 0, en.mesh.position.z+rz*10);
        spawnProjectile(en.mesh.position, target, 0xff4444, en.dmg*0.7, "boss", false);
      }
    }
  }
  // boss projectile-vs-player checked in projectile loop below via 'from' tag; simplified: check directly here
  projectiles.forEach(pr=>{
    if (pr.kind==="boss" && pr.mesh.position.distanceTo(playerObj.position)<1){
      enemyAttackPlayer(en, pr.dmg);
      pr.t = 999; // mark for removal
    }
  });
}

/* ---------------------------------------------------------------------- */
/*  UI: HUD / BOOK / BACKPACK / SHOP                                       */
/* ---------------------------------------------------------------------- */
function updateHud(){
  document.getElementById("coinTxt").textContent = S.coins;
  document.getElementById("mpTxt").textContent = S.magicPoints;
  document.getElementById("chapterLbl").textContent = toRoman(S.chapter)+"-"+S.segment;
  document.getElementById("realmLbl").textContent = REALMS[realmIndex(S.chapter)].name + (isBossSegment(S.segment)?" · BOSS":"");
  renderSpellBar();
}
function renderSpellBar(){
  const bar = document.getElementById("spellBar");
  const ring = document.getElementById("spellRing");
  bar.innerHTML=""; ring.innerHTML="";
  ELEMENTS.forEach((meta, idx)=>{
    const lvl = S.elements[meta.key].level;
    const locked = lvl<=0;
    const cd = runtime.spellCd[idx];
    const slot = document.createElement("div");
    slot.className = "spellSlot"+(locked?" locked":"");
    slot.style.borderColor = "#"+meta.color.toString(16).padStart(6,"0");
    slot.innerHTML = meta.icon + (locked?"":"<div class='lvl'>"+lvl+"</div>") + (cd>0.05?"<div class='cd'>"+cd.toFixed(1)+"</div>":"");
    slot.addEventListener("click", ()=>tryCastSpell(idx));
    bar.appendChild(slot);
    const tbtn = document.createElement("div");
    tbtn.className="iconBtn"; tbtn.style.opacity = locked?0.35:1;
    tbtn.textContent = meta.icon;
    tbtn.addEventListener("touchstart",(e)=>{e.preventDefault(); tryCastSpell(idx);},{passive:false});
    ring.appendChild(tbtn);
  });
}

/* ---- BOOK ---- */
function renderBook(){
  document.getElementById("bookMp").textContent = S.magicPoints;
  const list = document.getElementById("elemList");
  list.innerHTML="";
  ELEMENTS.forEach(meta=>{
    const st = S.elements[meta.key];
    const locked = st.level<=0;
    const cost = locked ? 1 : nextLevelCost(st.level);
    const maxed = st.level>=MAX_LEVEL;
    const card = document.createElement("div");
    card.className="elemCard";
    const pct = st.level/MAX_LEVEL*100;
    const reachedMilestone = Math.floor(st.level/5)*5;
    const metaLine = locked ? "Not unlocked"
      : reachedMilestone>0 ? "Ability: "+milestoneName(meta.key, reachedMilestone)
      : "Next milestone at Lv.5";
    card.innerHTML = `
      <div class="elemIcon" style="background:#${meta.color.toString(16).padStart(6,'0')}22;">${meta.icon}</div>
      <div class="elemBody">
        <div class="elemName">${meta.name} <span class="muted">Lv.${st.level}/${MAX_LEVEL}</span></div>
        <div class="elemMeta">${metaLine}</div>
        <div class="progWrap"><div style="width:${pct}%;background:#${meta.color.toString(16).padStart(6,'0')}"></div></div>
      </div>
      <div>
        <button class="btn small ${maxed?'':'gold'}" ${maxed?'disabled':''} data-el="${meta.key}">
          ${maxed? "MAX" : (locked? "Unlock (1✨)" : "Level Up ("+cost+"✨)")}
        </button>
      </div>`;
    list.appendChild(card);
  });
  list.querySelectorAll("button[data-el]").forEach(btn=>{
    btn.addEventListener("click", ()=>{
      const key = btn.getAttribute("data-el");
      const st = S.elements[key];
      const locked = st.level<=0;
      const cost = locked?1:nextLevelCost(st.level);
      if (st.level>=MAX_LEVEL) return;
      if (S.magicPoints<cost){ floatText("Not enough Magic Points!","#ff5566"); return; }
      S.magicPoints -= cost;
      S.mpSpent += cost;
      st.level += 1;
      Audio_.ensure();
      if (st.level%5===0) Audio_.sfx.milestone(); else Audio_.sfx.levelup();
      floatText((locked?"Unlocked ":"Leveled ")+ELEMENTS.find(e=>e.key===key).name+" → Lv."+st.level, "#8ecbff");
      renderBook(); updateHud(); saveGame();
    });
  });
}

/* ---- BACKPACK ---- */
function itemIcon(type){ return type==="weapon"?"⚔️":type==="shield"?"🛡️":"🥋"; }
function renderBackpack(){
  document.getElementById("bagCapTxt").textContent = bagUsed()+"/"+bagCap();
  document.getElementById("bagCapFill").style.width = clamp(bagUsed()/bagCap()*100,0,100)+"%";
  const eqRow = document.getElementById("equippedRow");
  eqRow.innerHTML="";
  [["weapon1","Weapon 1"],["weapon2","Weapon 2"],["shield","Shield"],["armor","Armor"]].forEach(([slot,label])=>{
    const it = getEquippedItem(slot);
    const div = document.createElement("div");
    div.className="invItem"+(it?" equipped":"");
    div.style.minWidth="100px";
    div.innerHTML = `<div class="ic">${it?itemIcon(it.inv.type):"➖"}</div><div>${label}</div><div class="muted">${it?it.def_item.name:"empty"}</div>`;
    if (it){
      const un = document.createElement("button");
      un.className="btn small red"; un.textContent="Unequip"; un.style.marginTop="4px";
      un.addEventListener("click", ()=>{ S.equipped[slot]=null; renderBackpack(); updateHud(); saveGame(); });
      div.appendChild(un);
    }
    eqRow.appendChild(div);
  });
  const grid = document.getElementById("bagGrid");
  grid.innerHTML="";
  S.backpack.forEach(inv=>{
    const def_ = itemDefFor(inv);
    if (!def_) return;
    const isEquipped = Object.values(S.equipped).includes(inv.uid);
    const div = document.createElement("div");
    div.className="invItem"+(isEquipped?" equipped":"");
    const statTxt = inv.type==="weapon" ? "DMG "+def_.dmg : inv.type==="shield" ? "DEF "+def_.def : "DEF "+def_.def+" HP+"+def_.hp;
    div.innerHTML = `<div class="ic">${itemIcon(inv.type)}</div><div>${def_.name}</div><div class="muted">${statTxt}</div>`;
    div.addEventListener("click", ()=>{
      if (isEquipped) return;
      if (inv.type==="weapon"){
        const slot = !S.equipped.weapon1 ? "weapon1" : (!S.equipped.weapon2 ? "weapon2" : "weapon1");
        S.equipped[slot]=inv.uid;
      } else if (inv.type==="shield"){ S.equipped.shield = inv.uid; }
      else { S.equipped.armor = inv.uid; }
      Audio_.sfx.click();
      renderBackpack(); updateHud(); saveGame();
    });
    grid.appendChild(div);
  });
  if (S.backpack.length===0){ grid.innerHTML = "<div class='muted'>Empty — find gear in chests!</div>"; }
}

/* ---- SHOP ---- */
function renderGearCard(container, it, type){
  const owned = S.backpack.some(b=>b.itemId===it.id);
  const statTxt = type==="weapon"?("DMG "+it.dmg):type==="shield"?("DEF "+it.def):("DEF "+it.def+" HP+"+it.hp);
  const card = document.createElement("div");
  card.className="elemCard";
  card.innerHTML = `<div class="elemIcon">${itemIcon(type)}</div>
    <div class="elemBody"><div class="elemName">${it.name} <span class="muted">T${it.tier}</span></div><div class="elemMeta">${statTxt} · wt ${it.weight}</div></div>
    <button class="btn small ${owned?'':'green'}" ${owned?'disabled':''}>${owned?'Owned':it.price+'🪙'}</button>`;
  card.querySelector("button").addEventListener("click", ()=>{
    if (S.coins<it.price) { floatText("Not enough coins!","#ff5566"); return; }
    if (bagUsed()+it.weight>bagCap()){ floatText("Backpack Full!","#ff5566"); return; }
    S.coins-=it.price;
    addToBackpack(it.id, type);
    Audio_.sfx.coin();
    renderShop(); updateHud(); saveGame();
  });
  container.appendChild(card);
}
function renderShop(){
  document.getElementById("shopCoins").textContent = S.coins;
  const gen = document.getElementById("tabGeneral");
  gen.innerHTML = `
    <div class="elemCard"><div class="elemIcon">✨</div><div class="elemBody"><div class="elemName">Magic Point</div><div class="elemMeta">1000 coins each</div></div>
      <button class="btn gold small" id="buyMp">Buy</button></div>
    <div class="elemCard"><div class="elemIcon">🎒</div><div class="elemBody"><div class="elemName">Backpack Slot</div><div class="elemMeta">+5 capacity — 1000 coins (own ${S.backpackSlots})</div></div>
      <button class="btn gold small" id="buySlot">Buy</button></div>`;
  document.getElementById("buyMp").addEventListener("click", ()=>{
    if (S.coins<1000){ floatText("Not enough coins!","#ff5566"); return; }
    S.coins-=1000; S.magicPoints+=1; Audio_.sfx.coin(); renderShop(); updateHud(); saveGame();
  });
  document.getElementById("buySlot").addEventListener("click", ()=>{
    if (S.coins<1000){ floatText("Not enough coins!","#ff5566"); return; }
    S.coins-=1000; S.backpackSlots+=1; Audio_.sfx.coin(); renderShop(); updateHud(); saveGame();
  });

  const tierMax = clamp(Math.ceil(S.chapter/10),1,6);
  const weaponsTab = document.getElementById("tabWeapons"); weaponsTab.innerHTML="";
  WEAPONS.filter(it=>it.tier<=tierMax+1).forEach(it=>renderGearCard(weaponsTab, it, "weapon"));

  const armorTab = document.getElementById("tabArmor"); armorTab.innerHTML="";
  SHIELDS.filter(it=>it.tier<=tierMax+1).forEach(it=>renderGearCard(armorTab, it, "shield"));
  ARMORS.filter(it=>it.tier<=tierMax+1).forEach(it=>renderGearCard(armorTab, it, "armor"));
}

function openShop(){ renderShop(); openModalRaw("shopPanel"); }

/* ---------------------------------------------------------------------- */
/*  MODAL / MENU PLUMBING                                                  */
/* ---------------------------------------------------------------------- */
function openModalRaw(id){
  document.getElementById(id).classList.remove("hidden");
  gameMode="modal";
}
function closeModalRaw(id){
  document.getElementById(id).classList.add("hidden");
  gameMode="playing";
}
function toggleModal(id){
  const el = document.getElementById(id);
  Audio_.ensure(); Audio_.sfx.click();
  if (el.classList.contains("hidden")){
    if (id==="bookPanel") renderBook();
    if (id==="bagPanel") renderBackpack();
    openModalRaw(id);
  } else {
    closeModalRaw(id);
  }
}
document.querySelectorAll("[data-close]").forEach(btn=>{
  btn.addEventListener("click", ()=>{
    const id = btn.getAttribute("data-close");
    document.getElementById(id).classList.add("hidden");
    if (["bookPanel","bagPanel","shopPanel","howPanel","settingsPanel"].includes(id) && gameMode==="modal" && (S.createdAt)){
      gameMode="playing";
    }
  });
});
document.getElementById("btnBookHud").addEventListener("click", ()=>toggleModal("bookPanel"));
document.getElementById("btnBagHud").addEventListener("click", ()=>toggleModal("bagPanel"));
document.getElementById("btnShopHud").addEventListener("click", ()=>{ Audio_.sfx.click(); openShop(); });
document.getElementById("btnPauseHud").addEventListener("click", ()=>togglePause());

function togglePause(){
  Audio_.ensure(); Audio_.sfx.click();
  const el = document.getElementById("pausePanel");
  if (el.classList.contains("hidden")){
    el.classList.remove("hidden"); gameMode="modal";
  } else {
    el.classList.add("hidden"); gameMode="playing";
  }
}
document.getElementById("btnResume").addEventListener("click", ()=>{ document.getElementById("pausePanel").classList.add("hidden"); gameMode="playing"; });
document.getElementById("btnSaveNow").addEventListener("click", ()=>{ saveGame(); });
document.getElementById("btnOpenSettings").addEventListener("click", ()=>{ document.getElementById("settingsPanel").classList.remove("hidden"); });
document.getElementById("btnQuitMenu").addEventListener("click", ()=>{
  saveGame();
  document.getElementById("pausePanel").classList.add("hidden");
  goToMainMenu();
});

/* ---------------------------------------------------------------------- */
/*  MAIN MENU / DIFFICULTY / SETTINGS WIRING                               */
/* ---------------------------------------------------------------------- */
const DIFF_ORDER = ["easy","medium","hard","expert","impossible"];
let selectedDifficulty = "medium";
function renderDiffGrid(){
  const grid = document.getElementById("diffGrid");
  grid.innerHTML="";
  DIFF_ORDER.forEach(key=>{
    const d = DIFFICULTIES[key];
    const div = document.createElement("div");
    div.className="diffBtn"+(selectedDifficulty===key?" sel":"");
    div.innerHTML = d.label+"<small>"+d.short+"</small>";
    div.addEventListener("click", ()=>{ selectedDifficulty=key; renderDiffGrid(); });
    grid.appendChild(div);
  });
}

function goToMainMenu(){
  gameMode="menu";
  Audio_.stopMusic();
  document.getElementById("hud").classList.add("hidden");
  document.getElementById("mainMenu").classList.remove("hidden");
  document.getElementById("btnContinue").disabled = !hasSave();
  renderDiffGrid();
}

document.getElementById("btnNewGame").addEventListener("click", ()=>{
  Audio_.ensure(); Audio_.sfx.click();
  const musicV = S.settings.music, sfxV = S.settings.sfx, touchPref = S.settings.forceTouch;
  S = defaultState();
  S.difficulty = selectedDifficulty;
  S.settings.music = musicV; S.settings.sfx = sfxV; S.settings.forceTouch = touchPref;
  S.createdAt = 1;
  beginPlaying(true);
});
document.getElementById("btnContinue").addEventListener("click", ()=>{
  Audio_.ensure(); Audio_.sfx.click();
  if (!loadGame()){ floatText("No save found","#ff5566"); return; }
  selectedDifficulty = S.difficulty;
  beginPlaying(false);
});
document.getElementById("btnHow").addEventListener("click", ()=>{ document.getElementById("howPanel").classList.remove("hidden"); });
document.getElementById("btnWipe").addEventListener("click", ()=>{
  if (confirm("Erase your save permanently?")){
    localStorage.removeItem(SAVE_KEY);
    document.getElementById("btnContinue").disabled = true;
    floatText("Save erased","#ff5566");
  }
});

function beginPlaying(isNew){
  document.getElementById("mainMenu").classList.add("hidden");
  document.getElementById("hud").classList.remove("hidden");
  runtime.hp = isNew ? maxHp() : clamp(S.hp||maxHp(), 1, maxHp());
  runtime.pos.set(0,0,6);
  gameMode="playing";
  if (!playerObj){
    playerObj = buildPlayerMesh();
    scene.add(playerObj);
  }
  startSegment();
  updateHud();
  setupTouch();
}

/* settings wiring (both menu sliders + in-pause sliders stay in sync) */
function wireVolumeControls(){
  const mv = document.getElementById("musicVol"), sv = document.getElementById("sfxVol");
  const mv2 = document.getElementById("musicVol2"), sv2 = document.getElementById("sfxVol2");
  function applyMusic(v){ S.settings.music=v/100; Audio_.setMusicVol(S.settings.music); mv.value=v; mv2.value=v; }
  function applySfx(v){ S.settings.sfx=v/100; Audio_.setSfxVol(S.settings.sfx); sv.value=v; sv2.value=v; }
  mv.addEventListener("input", e=>applyMusic(e.target.value));
  mv2.addEventListener("input", e=>applyMusic(e.target.value));
  sv.addEventListener("input", e=>{ applySfx(e.target.value); });
  sv2.addEventListener("input", e=>applySfx(e.target.value));
  applyMusic(Math.round(S.settings.music*100));
  applySfx(Math.round(S.settings.sfx*100));
  document.getElementById("touchToggle").addEventListener("change", e=>{
    S.settings.forceTouch = e.target.checked;
    document.body.classList.toggle("touch", isTouchDevice());
  });
}

/* shop tabs */
document.querySelectorAll(".tabBtn").forEach(btn=>{
  btn.addEventListener("click", ()=>{
    document.querySelectorAll(".tabBtn").forEach(b=>b.classList.remove("active"));
    document.querySelectorAll(".tabPane").forEach(p=>p.classList.remove("active"));
    btn.classList.add("active");
    document.getElementById(btn.getAttribute("data-tab")).classList.add("active");
  });
});

/* ---------------------------------------------------------------------- */
/*  AUTOSAVE + INIT                                                        */
/* ---------------------------------------------------------------------- */
setInterval(()=>{
  if (gameMode==="playing" || gameMode==="modal"){
    S.hp = runtime.hp;
    saveGame();
  }
}, 10000);

window.addEventListener("beforeunload", ()=>{
  if (S.createdAt){ S.hp = runtime.hp; saveGame(); }
});

function init(){
  initThree();
  wireVolumeControls();
  document.getElementById("btnContinue").disabled = !hasSave();
  renderDiffGrid();
  document.getElementById("mainMenu").classList.remove("hidden");
}
init();

})();
