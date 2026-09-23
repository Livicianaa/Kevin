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

// Eklem noktalari (yerel uzay) ve acisal serbestlik (koni yari acisi, radyan).
// Acisal sinir tork ile uygulanmaya calisilinca eklem kisiti onu eziyordu;
// ConeTwistConstraint bunu motorun icinde gercek bir sinir olarak cozuyor.
const JOINTS = [
  ['body', 'head', [0, 0, 0], 0.5],
  ['body', 'leftArm', [5, -2, 0], 1.5],
  ['body', 'rightArm', [-5, -2, 0], 1.5],
  ['body', 'leftLeg', [1.9, -12, 0], 0.7],
  ['body', 'rightLeg', [-1.9, -12, 0], 0.7],
];

const GRAVITY = -220;
const GROUND_Y = -34;

// PointToPoint eklemleri acisal sinir koymuyor; uzuvlar serbestce 180 derece
// donebiliyordu. Her uzvu kendi dinlenme acisina ceken bir yay + sinir ekliyoruz.
// "Aktif ragdoll": govde ve kafa kendilerini dik tutmaya calisiyor (kas kuvveti),
// kollar serbest sarkiyor. Tamamen pasif birakilinca karakter yercekimiyle
// omuz ekleminde yatay yayiliyordu - fiziksel olarak dogru ama cirkin.
const JOINT_STIFFNESS = {
  head: 420,
  body: 520,
  leftArm: 26,
  rightArm: 26,
  leftLeg: 190,
  rightLeg: 190,
};

const UPRIGHT_DAMPING = {
  head: 26,
  body: 30,
  leftArm: 3,
  rightArm: 3,
  leftLeg: 16,
  rightLeg: 16,
};

// Insan eklemi gibi dar sinirlar. Genis birakilinca govde omuz ekleminde
// 87 dereceye kadar donup karakter yatay yayiliyordu.
const JOINT_LIMIT = {
  head: 0.45,
  body: 0.4,
  leftArm: 2.6,
  rightArm: 2.6,
  leftLeg: 0.75,
  rightLeg: 0.75,
};

export class Ragdoll {
  constructor() {
    this.world = new CANNON.World({ gravity: new CANNON.Vec3(0, GRAVITY, 0) });
    this.world.allowSleep = false;
    this.world.solver.iterations = 40;
    this.world.solver.tolerance = 0.0005;

    this.bodies = {};
    this.constraints = [];
    this.grabbed = null;
    this.grabConstraint = null;
    // Kas gucu: 1 = direniyor/debeleniyor, dusuk = gevsemis sarkiyor
    this.muscle = 1;

    // Farenin kendisi kutlesiz bir govde: tutulan uzuv buna bir noktadan bagli,
    // boylece uzuv serbestce donuyor ama tutulan nokta farede kaliyor.
    this.pointer = new CANNON.Body({ mass: 0, type: CANNON.Body.KINEMATIC });
    this.world.addBody(this.pointer);

    for (const [name, spec] of Object.entries(PART_SPEC)) {
      const body = new CANNON.Body({
        mass: spec.mass,
        shape: new CANNON.Box(new CANNON.Vec3(...spec.half)),
        position: new CANNON.Vec3(...spec.center),
        linearDamping: 0.35,
        angularDamping: 0.55,
      });
      // Karakter tek duzlemde kalsin: z'de otelenme ve x/y'de donme kapali.
      // Bunu motorun kendi mekanizmasiyla yapiyoruz; pozisyon/quaternion'a elle
      // mudahale etmek eklem cozumunu bozuyor ve uzuvlar govdeden kopuyordu.
      body.linearFactor.set(1, 1, 0);
      body.angularFactor.set(0, 0, 1);
      this.bodies[name] = body;
      this.world.addBody(body);
    }

    for (const [parent, child, point, angle] of JOINTS) {
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
      const joint = new CANNON.ConeTwistConstraint(a, b, {
        pivotA,
        pivotB,
        axisA: new CANNON.Vec3(0, 1, 0),
        axisB: new CANNON.Vec3(0, 1, 0),
        angle,
        twistAngle: 0.05,
        maxForce: 1e8,
      });
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
    }
    if (this.grabConstraint) {
      this.world.removeConstraint(this.grabConstraint);
      this.grabConstraint = null;
    }
    this.grabbed = null;
  }

  // Bir uzvun UST UCUNDAN tutar: uzuv o noktadan asili kalir, serbestce doner,
  // govdenin geri kalani ondan sarkar.
  grab(partName) {
    const name = this.bodies[partName] ? partName : 'body';
    this.rest();
    this.grabbed = name;

    const body = this.bodies[name];
    const spec = PART_SPEC[name];
    // Kol ELDEN, bacak AYAKTAN, kafa/govde ust ucundan tutuluyor.
    const fromBottom = name.endsWith('Arm') || name.endsWith('Leg');
    const localPoint = new CANNON.Vec3(0, spec.half[1] * (fromBottom ? -0.85 : 0.85), 0);

    const worldPoint = body.pointToWorldFrame(localPoint, new CANNON.Vec3());
    this.pointer.position.copy(worldPoint);

    this.grabConstraint = new CANNON.PointToPointConstraint(
      body,
      localPoint,
      this.pointer,
      new CANNON.Vec3(),
      1e6,
    );
    this.world.addConstraint(this.grabConstraint);
  }

  release() {
    if (this.grabConstraint) {
      this.world.removeConstraint(this.grabConstraint);
      this.grabConstraint = null;
    }
    this.grabbed = null;
  }

  setMuscle(value) {
    this.muscle = Math.max(0.05, Math.min(1, value));
  }

  // Tutma noktasi (ragdoll yerel uzayinda).
  setGrabPoint(x, y) {
    this.pointer.position.set(x, y, 0);
  }

  applyJointForces(dt) {
    for (const name of Object.keys(PART_SPEC)) {
      if (name === this.grabbed) continue;
      const body = this.bodies[name];
      const q = body.quaternion;
      const angle = 2 * Math.atan2(q.z, q.w);
      const stiffness = JOINT_STIFFNESS[name] || 0;

      const damping = UPRIGHT_DAMPING[name] || 0;
      const m = this.muscle;
      body.angularVelocity.z -= (angle * stiffness * m + body.angularVelocity.z * damping * m) * dt;
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
    this.world.step(1 / 120, dt, 6);
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
