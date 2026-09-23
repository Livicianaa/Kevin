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
rag.grab('leftArm');
for (let i = 0; i < 150; i++) {
  rag.setGrabPoint(5, 18, 1 / 60);
  rag.step(1 / 60);
}
const deg = (b) => (2 * Math.atan2(b.quaternion.z, b.quaternion.w) * 180) / Math.PI;
console.log(
  'RAGDOLL koldan asili: govde y =', rag.bodies.body.position.y.toFixed(1),
  '| kafa y =', rag.bodies.head.position.y.toFixed(1),
  '| bacak y =', rag.bodies.leftLeg.position.y.toFixed(1),
);
const angles = ['body', 'head', 'leftLeg', 'rightArm'].map((n) => Math.abs(deg(rag.bodies[n])));
console.log('RAGDOLL eklem acilari sinirda mi (hepsi < 140):', angles.every((a) => a < 140), angles.map((a) => a.toFixed(0)).join(', '));

rag.grab('leftArm');
const before = deg(rag.bodies.leftLeg);
for (let i = 0; i < 50; i++) { rag.setGrabPoint(5 + i * 2, 18, 1 / 60); rag.step(1 / 60); }
console.log('RAGDOLL hizli sallaninca bacak savruldu mu:', Math.abs(deg(rag.bodies.leftLeg) - before) > 3);

rag.release();
for (let i = 0; i < 300; i++) rag.step(1 / 60);
console.log('RAGDOLL birakildi, zemine indi mi:', rag.bodies.body.position.y < 0);
