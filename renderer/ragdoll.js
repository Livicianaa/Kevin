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
const MAX_SHIFT = 7;
const GROUND_Y = -24;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

// Z ekseni etrafinda (ekran duzleminde) donus
function rotateZ(v, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]];
}

// X ekseni etrafinda (derinlik) donus
function rotateX(v, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return [v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c];
}

// Uzvun yonu: once z, sonra x - Three.js'in XYZ Euler sirasiyla uyumlu
function rotateLimb(v, ax, az) {
  return rotateX(rotateZ(v, az), ax);
}

export class Ragdoll {
  constructor() {
    // Govde ve her uzuv IKI eksende doner: az ekran duzleminde, ax derinlikte.
    this.bodyAngle = 0;
    this.bodyVel = 0;
    this.bodyAngleX = 0;
    this.bodyVelX = 0;
    this.bodyPos = [0, BODY_CENTER[1], 0];
    this.bodyDrop = 0;
    this.limbs = {};
    for (const name of Object.keys(LIMBS)) {
      this.limbs[name] = { angle: 0, vel: 0, angleX: 0, velX: 0 };
    }
    this.grabbed = null;
    this.target = [0, 0, 0];
    this.muscle = 1;
    this.spin = 0;
  }

  rest() {
    this.bodyAngle = 0;
    this.bodyVel = 0;
    this.bodyAngleX = 0;
    this.bodyVelX = 0;
    this.bodyPos = [0, BODY_CENTER[1], 0];
    this.bodyDrop = 0;
    for (const limb of Object.values(this.limbs)) {
      limb.angle = 0;
      limb.vel = 0;
      limb.angleX = 0;
      limb.velX = 0;
    }
  }

  grab(partName) {
    this.rest();
    this.grabbed = GRAB_POINT[partName] ? partName : 'body';
    // Tutma noktasi, uzvun TUTULDUGU ANDAKI kendi yeri: karakter tutuldugu an
    // yerinden sicramiyor, sadece oradan sarkmaya basliyor.
    const offset = this.grabOffset();
    this.target = [
      this.bodyPos[0] + offset[0],
      this.bodyPos[1] + offset[1],
      this.bodyPos[2] + offset[2],
    ];
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

  setGrabPoint(x, y, z = 0) {
    this.target = [x, y, z];
  }

  // Karakterin kendi ekseni etrafindaki donusu (3B oldugunu gosteren sey).
  setSpin(radians) {
    this.spin = radians;
  }

  // Tutulan noktanin govde merkezine gore konumu (govde acisi dahil).
  grabOffset() {
    const name = this.grabbed;
    const point = GRAB_POINT[name];
    if (name === 'body') {
      return rotateLimb([point[0], point[1], 0], this.bodyAngleX, this.bodyAngle);
    }

    const spec = LIMBS[name];
    const limb = this.limbs[name];
    const jointLocal = rotateLimb(
      [spec.joint[0], spec.joint[1] - BODY_CENTER[1], 0],
      this.bodyAngleX,
      this.bodyAngle,
    );
    const alongLimb = rotateLimb(
      [0, point[1] + spec.length, 0],
      this.bodyAngleX + limb.angleX,
      this.bodyAngle + limb.angle,
    );
    return [
      jointLocal[0] + alongLimb[0],
      jointLocal[1] + alongLimb[1],
      jointLocal[2] + alongLimb[2],
    ];
  }

  // Tek eksende sarkac: yercekimi + dinlenmeye cekme yayi + sonumleme.
  // Adim basina hiz ve aci sinirli oldugu icin salinim olusamiyor.
  integrate(angle, vel, gravityTorque, stiffness, damping, limit, h) {
    let next = clamp(vel + (gravityTorque - angle * stiffness - vel * damping) * h, -12, 12);
    let a = angle + next * h;
    // Limite carpinca hiz da sifirlanmali: sadece aciyi kirpmak hizi biriktiriyor
    // ve uzuv sinirda yapisip kaliyordu (derinlikte 74 derecede takiliyordu).
    if (a > limit) {
      a = limit;
      if (next > 0) next = 0;
    } else if (a < -limit) {
      a = -limit;
      if (next < 0) next = 0;
    }
    return [a, next];
  }

  step(dt) {
    const h = Math.min(dt, 1 / 30);
    const m = this.muscle;

    if (this.grabbed) {
      const pivot = this.hangPivot();
      const lever = rotateLimb([-pivot[0], -pivot[1], 0], this.bodyAngleX, this.bodyAngle);
      // Ekran duzleminde: agirlik merkezi asildigi eklemin altina donuyor
      const hangZ = -lever[0] * GRAVITY * 0.32;
      // Derinlikte: agirlik merkezi one/arkaya sapmissa geri sallaniyor
      const hangX = -lever[2] * GRAVITY * 0.32;

      [this.bodyAngle, this.bodyVel] = this.integrate(
        this.bodyAngle, this.bodyVel, hangZ, 0.6 + 7 * m, 3.2 + 2.5 * m, 2.4, h,
      );
      [this.bodyAngleX, this.bodyVelX] = this.integrate(
        this.bodyAngleX, this.bodyVelX, hangX, 1.2 + 7 * m, 3.0 + 2.5 * m, 1.3, h,
      );
      this.bodyDrop = 0;
    } else {
      [this.bodyAngle, this.bodyVel] = this.integrate(this.bodyAngle, this.bodyVel, 0, 12, 5, 2.4, h);
      [this.bodyAngleX, this.bodyVelX] = this.integrate(this.bodyAngleX, this.bodyVelX, 0, 12, 5, 1.3, h);
    }

    for (const [name, spec] of Object.entries(LIMBS)) {
      const limb = this.limbs[name];

      if (name === this.grabbed) {
        [limb.angle, limb.vel] = this.integrate(limb.angle, limb.vel, 0, 22, 6, spec.limit, h);
        [limb.angleX, limb.velX] = this.integrate(limb.angleX, limb.velX, 0, 22, 6, spec.limit, h);
        continue;
      }

      const worldZ = this.bodyAngle + limb.angle;
      const worldX = this.bodyAngleX + limb.angleX;
      const stiffness = (2 + 26 * m) * spec.inertia;
      const damping = 4 + 3 * m;

      [limb.angle, limb.vel] = this.integrate(
        limb.angle, limb.vel, -Math.sin(worldZ) * GRAVITY * spec.inertia,
        stiffness, damping, spec.limit, h,
      );
      [limb.angleX, limb.velX] = this.integrate(
        limb.angleX, limb.velX, -Math.sin(worldX) * GRAVITY * spec.inertia,
        stiffness, damping, spec.limit, h,
      );
    }

    if (this.grabbed) {
      const offset = this.grabOffset();
      // Govde, tutma noktasi sabit kalacak sekilde yerlestiriliyor - ama pencere
      // disina tasmasin diye dinlenme konumundan en fazla MAX_SHIFT uzaklasiyor.
      // Sarkmayi zaten acilar gosteriyor; konum sadece cerceve icinde kalmali.
      this.bodyPos = [
        clamp(this.target[0] - offset[0], -MAX_SHIFT, MAX_SHIFT),
        clamp(this.target[1] - offset[1], BODY_CENTER[1] - MAX_SHIFT, BODY_CENTER[1] + MAX_SHIFT),
        clamp(this.target[2] - offset[2], -MAX_SHIFT, MAX_SHIFT),
      ];
    } else {
      this.bodyPos = [0, BODY_CENTER[1], 0];
    }
  }

  applyTo(skin) {
    const [bx, by, bz] = this.bodyPos;

    // Karakterin kendi ekseni etrafinda donmesi: 3B oldugunu en cok bu gosteriyor
    skin.rotation.y = this.spin;

    if (skin.body) {
      skin.body.position.set(bx, by, bz);
      skin.body.rotation.set(this.bodyAngleX, 0, this.bodyAngle);
    }

    for (const [name, spec] of Object.entries(LIMBS)) {
      const part = skin[name];
      if (!part) continue;

      const limb = this.limbs[name];
      const joint = rotateLimb(
        [spec.joint[0], spec.joint[1] - BODY_CENTER[1], 0],
        this.bodyAngleX,
        this.bodyAngle,
      );

      part.position.set(bx + joint[0], by + joint[1], bz + joint[2]);
      part.rotation.set(this.bodyAngleX + limb.angleX, 0, this.bodyAngle + limb.angle);
    }
  }

  get settled() {
    let energy = this.bodyVel * this.bodyVel + this.bodyVelX * this.bodyVelX;
    for (const limb of Object.values(this.limbs)) {
      energy += limb.vel * limb.vel + limb.velX * limb.velX;
    }
    return energy < 0.05;
  }

  // Tasima ataleti: fare hizlandiginda uzuvlar geride kaliyor.
  // Tasima ataleti: fare hizlandiginda uzuvlar geride kaliyor. Yatay ivme
  // ekran duzleminde, dikey ivme DERINLIKTE savurma yapiyor - boylece karakter
  // surulurken one-arkaya da sallaniyor, duz bir kagit gibi kalmiyor.
  setInertia(ax, ay) {
    const pushZ = clamp(-ax / 900, -1.2, 1.2);
    const pushX = clamp(ay / 2400, -0.35, 0.35) + clamp(Math.abs(ax) / 6000, 0, 0.18);
    for (const [name, spec] of Object.entries(LIMBS)) {
      if (name === this.grabbed) continue;
      this.limbs[name].vel += pushZ * spec.inertia;
      this.limbs[name].velX += pushX * spec.inertia;
    }
    this.bodyVel += pushZ * 0.5;
    this.bodyVelX += pushX * 0.3;
  }
}

export const RAGDOLL_PARTS = ['body', ...Object.keys(LIMBS)];
