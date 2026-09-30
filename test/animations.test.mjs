import { KevinAnimator } from '../renderer/animations.js';

function fakePlayer() {
  const part = () => ({
    rotation: { x: 0, y: 0, z: 0 },
    position: { x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
    quaternion: { x: 0, y: 0, z: 0, w: 1, set(x, y, z, w) { this.x = x; this.y = y; this.z = z; this.w = w; } },
  });
  return {
    position: { y: 0 },
    rotation: { x: 0, y: 0, z: 0 },
    skin: { head: part(), body: part(), leftArm: part(), rightArm: part(), leftLeg: part(), rightLeg: part() },
  };
}

function run(setup, steps, dt = 0.05) {
  const a = new KevinAnimator();
  const p = fakePlayer();
  setup(a);
  const rows = [];
  for (let i = 0; i < steps; i++) {
    a.update(p, dt);
    rows.push({
      t: +(i * dt).toFixed(2),
      state: a.state,
      rootY: +p.position.y.toFixed(2),
      rArmZ: +p.skin.rightArm.rotation.z.toFixed(2),
      lArmZ: +p.skin.leftArm.rotation.z.toFixed(2),
      legX: +p.skin.leftLeg.rotation.x.toFixed(2),
      headX: +p.skin.head.rotation.x.toFixed(2),
      facing: +p.rotation.y.toFixed(2),
    });
  }
  return rows;
}

const jump = run((a) => a.play('jump'), 20);
const peak = Math.max(...jump.map((r) => r.rootY));
console.log('JUMP  tepe rootY =', peak, '| bitis durumu =', jump[jump.length - 1].state);

const wave = run((a) => a.play('wave'), 30);
console.log('WAVE  maks sol kol z =', Math.max(...wave.map((r) => r.lArmZ)));

const sit = run((a) => a.setSitting(true), 20);
console.log('SIT   son bacak x =', sit[sit.length - 1].legX, '| rootY =', sit[sit.length - 1].rootY);

const nod = run((a) => a.play('nod-yes'), 24);
console.log('NOD   kafa x araligi =', Math.min(...nod.map((r) => r.headX)), '..', Math.max(...nod.map((r) => r.headX)));

const blend = run((a) => { a.setState('think'); }, 6);
console.log('BLEND think ilk 6 kare sag kol z =', blend.map((r) => r.rArmZ).join(' '));

const back = run((a) => { a.setState('talk'); a.play('jump'); }, 24);
console.log('DONUS jump sonrasi durum =', back[back.length - 1].state, '(talk olmali)');

const face = run((a) => { a.setState('walk'); a.setFacing(Math.PI / 2); }, 20);
console.log('YON   hedef 1.57 -> ilk kare', face[0].facing, '| son kare', face[face.length - 1].facing);

const climb = run((a) => a.setState('climb'), 10);
console.log('CLIMB kol x araligi =', Math.min(...climb.map((r) => r.rArmZ)).toFixed(2), '| durum =', climb[9].state);

const sitEdge = run((a) => a.setState('sit-edge'), 20);
const legs = sitEdge.map((r) => r.legX);
console.log('SIT-EDGE bacak sallanma araligi =', Math.min(...legs).toFixed(2), '..', Math.max(...legs).toFixed(2));


// --- Ragdoll ---
const { Ragdoll } = await import('../renderer/ragdoll.js');

const rag = new Ragdoll();
const degOf = (a) => Number(((a * 180) / Math.PI).toFixed(0));

function hang(part, muscle) {
  rag.grab(part);
  rag.setMuscle(muscle);
  for (let i = 0; i < 400; i++) {
    rag.setGrabPoint(0, 16);
    rag.step(1 / 60);
  }
  const samples = [];
  for (let i = 0; i < 120; i++) {
    rag.setGrabPoint(0, 16);
    rag.step(1 / 60);
    samples.push((rag.bodyAngle * 180) / Math.PI);
  }
  return { angle: degOf(rag.bodyAngle), jitter: Math.max(...samples) - Math.min(...samples) };
}

const fromHead = hang('head', 0.22);
const fromArm = hang('leftArm', 0.22);
const fromRightArm = hang('rightArm', 0.22);
const fromLeg = hang('leftLeg', 0.22);

console.log('RAGDOLL kafadan tutunca dik mi:', Math.abs(fromHead.angle) < 10, `(${fromHead.angle} derece)`);
console.log('RAGDOLL koldan tutunca sarkiyor mu:', Math.abs(fromArm.angle) > 25, `(${fromArm.angle} derece)`);
console.log('RAGDOLL sag/sol kol simetrik mi:', Math.abs(fromArm.angle + fromRightArm.angle) < 5);
console.log('RAGDOLL bacaktan tutunca bas asagi mi:', Math.abs(fromLeg.angle) > 100, `(${fromLeg.angle} derece)`);
const worstJitter = Math.max(fromHead.jitter, fromArm.jitter, fromLeg.jitter);
console.log('RAGDOLL titreme yok mu:', worstJitter < 0.5, `(en kotu ${worstJitter.toFixed(3)} derece)`);

rag.grab('leftArm');
const beforeSwing = rag.limbs.leftLeg.vel;
rag.setInertia(-900, 0);
console.log('RAGDOLL ani hareket uzuvlara ivme veriyor mu:', rag.limbs.leftLeg.vel !== beforeSwing);

// --- 3B: derinlikte savrulma ---
const rag3d = new Ragdoll();
rag3d.grab('leftArm');
for (let i = 0; i < 200; i++) { rag3d.setGrabPoint(0, 16, 0); rag3d.step(1 / 60); }
const depthBefore = rag3d.limbs.leftLeg.angleX;
for (let i = 0; i < 20; i++) { rag3d.setInertia(1800, 900); rag3d.step(1 / 60); }
const depthSwing = Math.abs(rag3d.limbs.leftLeg.angleX - depthBefore);
console.log('3B surukleyince bacak DERINLIKTE savruluyor mu:', depthSwing > 0.05, `(${((depthSwing * 180) / Math.PI).toFixed(1)} derece)`);

for (let i = 0; i < 400; i++) { rag3d.setGrabPoint(0, 16, 0); rag3d.step(1 / 60); }
console.log('3B derinlik salinimi sonra duruluyor mu:', Math.abs(rag3d.bodyVelX) < 0.05);

const fakeSkin = {};
for (const n of ['head', 'body', 'leftArm', 'rightArm', 'leftLeg', 'rightLeg']) {
  fakeSkin[n] = {
    position: { set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
    rotation: { set(x, y, z) { this.x = x; this.y = y; this.z = z; } },
  };
}
fakeSkin.rotation = { y: 0 };
rag3d.setSpin(1.2);
rag3d.applyTo(fakeSkin);
console.log('3B karakter kendi ekseninde donuyor mu:', Math.abs(fakeSkin.rotation.y - 1.2) < 1e-9);
