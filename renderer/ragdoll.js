import * as CANNON from 'cannon-es';

// Minecraft rig'i icin gercek bir ragdoll: 6 rijit govde, eklemlerle bagli.
// Karakter bir uzvundan tutuldugunda o uzuv fareye kinematik olarak bagli,
// geri kalan govde yercekimiyle sarkiyor ve fare hareketinden ivme aliyor.
//
// Olcu birimi skinview3d ile ayni (1 birim = 1 Minecraft pikseli).
// Konumlar skin grubunun yerel uzayinda.

const PART_SPEC = {
  head: { half: [4, 4, 4], center: [0, 4, 0], meshOffset: [0, 4, 0], mass: 3 },
  body: { half: [4, 6, 2], center: [0, -6, 0], meshOffset: [0, 0, 0], mass: 8 },
  leftArm: { half: [2, 6, 2], center: [5, -6, 0], meshOffset: [0, -4, 0], mass: 2 },
  rightArm: { half: [2, 6, 2], center: [-5, -6, 0], meshOffset: [0, -4, 0], mass: 2 },
  leftLeg: { half: [2, 6, 2], center: [1.9, -18, 0], meshOffset: [0, -6, 0], mass: 3 },
  rightLeg: { half: [2, 6, 2], center: [-1.9, -18, 0], meshOffset: [0, -6, 0], mass: 3 },
};

// Eklem noktalari (yerel uzay): hangi iki parca nerede birlesiyor
const JOINTS = [
  ['body', 'head', [0, 0, 0]],
  ['body', 'leftArm', [5, -2, 0]],
  ['body', 'rightArm', [-5, -2, 0]],
  ['body', 'leftLeg', [1.9, -12, 0]],
  ['body', 'rightLeg', [-1.9, -12, 0]],
];

const GRAVITY = -220;
const GROUND_Y = -34;

// PointToPoint eklemleri acisal sinir koymuyor; uzuvlar serbestce 180 derece
// donebiliyordu. Her uzvu kendi dinlenme acisina ceken bir yay + sinir ekliyoruz.
const JOINT_STIFFNESS = {
  head: 70,
  body: 14,
  leftArm: 16,
  rightArm: 16,
  leftLeg: 34,
  rightLeg: 34,
};

const JOINT_LIMIT = {
  head: 0.7,
  body: 1.6,
  leftArm: 2.4,
  rightArm: 2.4,
  leftLeg: 1.1,
  rightLeg: 1.1,
};

export class Ragdoll {
  constructor() {
    this.world = new CANNON.World({ gravity: new CANNON.Vec3(0, GRAVITY, 0) });
    this.world.allowSleep = false;
    this.world.solver.iterations = 12;

    this.bodies = {};
    this.constraints = [];
    this.grabbed = null;
    this.grabTarget = new CANNON.Vec3();

    for (const [name, spec] of Object.entries(PART_SPEC)) {
      const body = new CANNON.Body({
        mass: spec.mass,
        shape: new CANNON.Box(new CANNON.Vec3(...spec.half)),
        position: new CANNON.Vec3(...spec.center),
        linearDamping: 0.22,
        angularDamping: 0.35,
      });
      this.bodies[name] = body;
      this.world.addBody(body);
    }

    for (const [parent, child, point] of JOINTS) {
      const a = this.bodies[parent];
      const b = this.bodies[child];
      const pivotA = new CANNON.Vec3(
        point[0] - a.position.x,
        point[1] - a.position.y,
        point[2] - a.position.z,
      );
      const pivotB = new CANNON.Vec3(
        point[0] - b.position.x,
        point[1] - b.position.y,
        point[2] - b.position.z,
      );
      const joint = new CANNON.PointToPointConstraint(a, pivotA, b, pivotB);
      this.constraints.push(joint);
      this.world.addConstraint(joint);
    }

    const ground = new CANNON.Body({
      mass: 0,
      shape: new CANNON.Plane(),
      position: new CANNON.Vec3(0, GROUND_Y, 0),
    });
    ground.quaternion.setFromEuler(-Math.PI / 2, 0, 0);
    this.world.addBody(ground);

    this.rest();
  }

  // Ragdoll'u dik durusa sifirla
  rest() {
    for (const [name, spec] of Object.entries(PART_SPEC)) {
      const body = this.bodies[name];
      body.position.set(...spec.center);
      body.quaternion.set(0, 0, 0, 1);
      body.velocity.setZero();
      body.angularVelocity.setZero();
      body.type = CANNON.Body.DYNAMIC;
      body.updateMassProperties();
    }
    this.grabbed = null;
  }

  // Bir uzvu fareye baglar: o uzuv kinematik olur, gerisi ondan sarkar.
  grab(partName) {
    const name = this.bodies[partName] ? partName : 'body';
    this.rest();
    this.grabbed = name;
    const body = this.bodies[name];
    body.type = CANNON.Body.KINEMATIC;
    body.velocity.setZero();
    body.angularVelocity.setZero();
    this.grabTarget.copy(body.position);
  }

  release() {
    if (!this.grabbed) return;
    this.bodies[this.grabbed].type = CANNON.Body.DYNAMIC;
    this.bodies[this.grabbed].updateMassProperties();
    this.grabbed = null;
  }

  // Tutulan uzvun hedef noktasi. Hiz constraint'lere ivme olarak geciyor.
  setGrabPoint(x, y, dt) {
    if (!this.grabbed) return;
    const body = this.bodies[this.grabbed];
    const step = Math.max(dt, 1 / 120);
    body.velocity.set((x - body.position.x) / step, (y - body.position.y) / step, 0);
    this.grabTarget.set(x, y, 0);
  }

  applyJointForces(dt) {
    for (const name of Object.keys(PART_SPEC)) {
      if (name === this.grabbed) continue;
      const body = this.bodies[name];
      const q = body.quaternion;
      const angle = 2 * Math.atan2(q.z, q.w);
      const stiffness = JOINT_STIFFNESS[name] || 0;
      const limit = JOINT_LIMIT[name] ?? Math.PI;

      body.angularVelocity.z -= angle * stiffness * dt;

      if (Math.abs(angle) > limit) {
        const clamped = Math.sign(angle) * limit;
        const half = clamped / 2;
        q.z = Math.sin(half);
        q.w = Math.cos(half);
        body.angularVelocity.z *= 0.25;
      }
    }
  }

  // Fare hizlandiginda govde geride kalir: tasima ataleti.
  setInertia(ax, ay) {
    const limit = 600;
    const cx = Math.max(-limit, Math.min(limit, -ax));
    const cy = Math.max(-limit, Math.min(limit, -ay));
    this.world.gravity.set(cx, GRAVITY + cy, 0);
  }

  step(dt) {
    this.applyJointForces(dt);
    this.world.step(1 / 60, dt, 3);
    if (this.grabbed) {
      const body = this.bodies[this.grabbed];
      body.position.x = this.grabTarget.x;
      body.position.y = this.grabTarget.y;
      body.position.z = 0;
    }
    // Duzlemde kal: z ekseninde savrulma karakteri ekrandan cikariyor
    for (const name of Object.keys(PART_SPEC)) {
      const body = this.bodies[name];
      body.position.z = 0;
      body.velocity.z = 0;
      body.angularVelocity.x = 0;
      body.angularVelocity.y = 0;
      const q = body.quaternion;
      q.x = 0;
      q.y = 0;
      const len = Math.hypot(q.z, q.w) || 1;
      q.z /= len;
      q.w /= len;
    }
  }

  // Fizik sonucunu skinview3d parcalarina yaz.
  applyTo(skin) {
    for (const [name, spec] of Object.entries(PART_SPEC)) {
      const body = this.bodies[name];
      const part = skin[name];
      if (!part) continue;

      part.quaternion.set(body.quaternion.x, body.quaternion.y, body.quaternion.z, body.quaternion.w);

      // Parca gruplarinin origin'i eklem noktasinda, mesh ise offsetli duruyor.
      // group.position = ragdollMerkezi - q * meshOffset
      const o = spec.meshOffset;
      const rotated = new CANNON.Vec3(o[0], o[1], o[2]);
      body.quaternion.vmult(rotated, rotated);
      part.position.set(
        body.position.x - rotated.x,
        body.position.y - rotated.y,
        body.position.z - rotated.z,
      );
    }
  }

  get settled() {
    let energy = 0;
    for (const name of Object.keys(PART_SPEC)) {
      energy += this.bodies[name].velocity.lengthSquared();
    }
    return energy < 4;
  }
}

export const RAGDOLL_PARTS = Object.keys(PART_SPEC);
