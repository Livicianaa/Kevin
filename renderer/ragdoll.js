// Kevin'in ragdoll'u: acisal zincir cozucusu.
//
// Neden fizik motoru degil: cannon-es ile kurulan kisit tabanli ragdoll bu
// olcekte (kucuk kutle, sert yay, 60 Hz) kararli calismadi - uzuvlar govdeden
// kopuyor ya da titriyordu. Burada uzuvlar TANIM GEREGI bagli: her uzvun tek
// bir acisi var, konumlar ileri kinematikle hesaplaniyor. Kopma imkansiz,
// aci sinirlari dogrudan uygulanabiliyor.
//
// Olcu birimi skinview3d ile ayni (1 birim = 1 Minecraft pikseli).

const LIMBS = {
  head: { joint: [0, 0], length: 4, rest: 0, limit: 0.5, inertia: 1.0, meshOffset: [0, 4] },
  leftArm: { joint: [5, -2], length: 6, rest: 0, limit: 2.7, inertia: 0.55, meshOffset: [0, -4] },
  rightArm: { joint: [-5, -2], length: 6, rest: 0, limit: 2.7, inertia: 0.55, meshOffset: [0, -4] },
  leftLeg: { joint: [1.9, -12], length: 6, rest: 0, limit: 1.0, inertia: 0.8, meshOffset: [0, -6] },
  rightLeg: { joint: [-1.9, -12], length: 6, rest: 0, limit: 1.0, inertia: 0.8, meshOffset: [0, -6] },
};

// Uzvun tutuldugu nokta (kendi ekseninde): kol ELDEN, bacak AYAKTAN,
// kafa ve govde ust ucundan.
const GRAB_POINT = {
  head: [0, 4],
  body: [0, 6],
  leftArm: [0, -11],
  rightArm: [0, -11],
  leftLeg: [0, -12],
  rightLeg: [0, -12],
};

const BODY_CENTER = [0, -6];
const GRAVITY = 16;
const GROUND_Y = -24;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function rotate(x, y, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return [x * c - y * s, x * s + y * c];
}

export class Ragdoll {
  constructor() {
    this.bodyAngle = 0;
    this.bodyVel = 0;
    this.bodyPos = [0, BODY_CENTER[1]];
    this.bodyDrop = 0;
    this.limbs = {};
    for (const name of Object.keys(LIMBS)) {
      this.limbs[name] = { angle: 0, vel: 0 };
    }
    this.grabbed = null;
    this.target = [0, 0];
    this.muscle = 1;
  }

  rest() {
    this.bodyAngle = 0;
    this.bodyVel = 0;
    this.bodyPos = [0, BODY_CENTER[1]];
    this.bodyDrop = 0;
    for (const limb of Object.values(this.limbs)) {
      limb.angle = 0;
      limb.vel = 0;
    }
  }

  grab(partName) {
    this.rest();
    this.grabbed = GRAB_POINT[partName] ? partName : 'body';
    // Bacaktan tutulmak kararsiz denge: kucuk bir sapma olmadan ters donmez.
    this.bodyAngle = 0.12;
  }

  // Govdenin asildigi eklem (govde merkezine gore kaldirac kolu).
  hangPivot() {
    if (this.grabbed === 'body' || !LIMBS[this.grabbed]) return [0, 6];
    const j = LIMBS[this.grabbed].joint;
    return [j[0] - BODY_CENTER[0], j[1] - BODY_CENTER[1]];
  }

  release() {
    this.grabbed = null;
  }

  setMuscle(value) {
    this.muscle = clamp(value, 0.05, 1);
  }

  setGrabPoint(x, y) {
    this.target = [x, y];
  }

  // Tutulan noktanin govde merkezine gore konumu (govde acisi dahil).
  grabOffset() {
    const name = this.grabbed;
    const point = GRAB_POINT[name];
    if (name === 'body') return rotate(point[0], point[1], this.bodyAngle);

    const spec = LIMBS[name];
    const limbAngle = this.bodyAngle + this.limbs[name].angle;
    const jointLocal = rotate(spec.joint[0], spec.joint[1] - BODY_CENTER[1], this.bodyAngle);
    const alongLimb = rotate(0, point[1] + spec.length, limbAngle);
    return [jointLocal[0] + alongLimb[0], jointLocal[1] + alongLimb[1]];
  }

  step(dt) {
    const h = Math.min(dt, 1 / 30);
    const m = this.muscle;

    if (this.grabbed) {
      // Govde asildigi eklemin altina donmeye calisiyor: agirlik merkezinden
      // eklem noktasina olan kaldiracin yatay bileseni tork uretiyor.
      const pivot = this.hangPivot();
      const lever = rotate(-pivot[0], -pivot[1], this.bodyAngle);
      const hangTorque = -lever[0] * GRAVITY * 0.32;
      const spring = -this.bodyAngle * (0.6 + 7 * m);
      const damp = -this.bodyVel * (3.2 + 2.5 * m);
      this.bodyVel = clamp(this.bodyVel + (hangTorque + spring + damp) * h, -9, 9);
      this.bodyAngle = clamp(this.bodyAngle + this.bodyVel * h, -2.4, 2.4);
      this.bodyDrop = 0;
    } else {
      // Serbest dusus sirasinda govde gevsek sallaniyor.
      const spring = -this.bodyAngle * 12;
      const damp = -this.bodyVel * 5;
      this.bodyVel = clamp(this.bodyVel + (spring + damp) * h, -9, 9);
      this.bodyAngle = clamp(this.bodyAngle + this.bodyVel * h, -2.4, 2.4);
    }

    for (const [name, spec] of Object.entries(LIMBS)) {
      if (name === this.grabbed) {
        // Tutulan uzuv: govdenin agirligi onu duzeltiyor
        const limb = this.limbs[name];
        const spring = -limb.angle * 22;
        const damp = -limb.vel * 6;
        limb.vel = clamp(limb.vel + (spring + damp) * h, -10, 10);
        limb.angle = clamp(limb.angle + limb.vel * h, -spec.limit, spec.limit);
        continue;
      }

      const limb = this.limbs[name];
      const worldAngle = this.bodyAngle + limb.angle;
      // Uzvun kutle merkezi eklemin altinda: yercekimi onu dikey yapmaya calisiyor
      const gravityTorque = -Math.sin(worldAngle) * GRAVITY * spec.inertia;
      const spring = -limb.angle * (2 + 26 * m) * spec.inertia;
      const damp = -limb.vel * (4 + 3 * m);

      limb.vel = clamp(limb.vel + (gravityTorque + spring + damp) * h, -12, 12);
      limb.angle = clamp(limb.angle + limb.vel * h, -spec.limit, spec.limit);
    }

    // Tutulan nokta tam farede olsun: govde konumunu ona gore yerlestiriyoruz.
    if (this.grabbed) {
      const offset = this.grabOffset();
      this.bodyPos = [this.target[0] - offset[0], this.target[1] - offset[1]];
    } else {
      this.bodyPos = [0, BODY_CENTER[1]];
    }
  }

  applyTo(skin) {
    const [bx, by] = this.bodyPos;

    if (skin.body) {
      skin.body.position.set(bx, by, 0);
      skin.body.rotation.set(0, 0, this.bodyAngle);
    }

    for (const [name, spec] of Object.entries(LIMBS)) {
      const part = skin[name];
      if (!part) continue;

      const limbAngle = this.bodyAngle + this.limbs[name].angle;
      const jointOffset = rotate(spec.joint[0], spec.joint[1] - BODY_CENTER[1], this.bodyAngle);
      const jointX = bx + jointOffset[0];
      const jointY = by + jointOffset[1];

      // Parca gruplarinin origin'i eklemde; mesh offset'i aci ile birlikte doner.
      part.position.set(jointX, jointY, 0);
      part.rotation.set(0, 0, limbAngle);
    }
  }

  get settled() {
    let energy = this.bodyVel * this.bodyVel;
    for (const limb of Object.values(this.limbs)) energy += limb.vel * limb.vel;
    return energy < 0.05;
  }

  // Tasima ataleti: fare hizlandiginda uzuvlar geride kaliyor.
  setInertia(ax, ay) {
    const push = clamp(-ax / 900, -1.2, 1.2);
    for (const [name, spec] of Object.entries(LIMBS)) {
      if (name === this.grabbed) continue;
      this.limbs[name].vel += push * spec.inertia;
    }
    this.bodyVel += push * 0.5;
  }
}

export const RAGDOLL_PARTS = ['body', ...Object.keys(LIMBS)];
