import { PlayerAnimation } from 'skinview3d';
import { CEM_PARTS } from './cem.js';

// Bizim uzuv adlarimiz <-> CEM (Minecraft) adlari
const CEM_NAME = {
  head: 'head',
  body: 'body',
  leftArm: 'left_arm',
  rightArm: 'right_arm',
  leftLeg: 'left_leg',
  rightLeg: 'right_leg',
};
const CEM_TO_OURS = Object.fromEntries(Object.entries(CEM_NAME).map(([k, v]) => [v, k]));

const PARTS = ['head', 'body', 'leftArm', 'rightArm', 'leftLeg', 'rightLeg'];
const ARM_REST = Math.PI * 0.02;
const BLEND_TIME = 0.25;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function envelope(p) {
  return Math.sin(clamp(p, 0, 1) * Math.PI);
}

function breathe(t, amount = 0.012) {
  return Math.sin(t * 2) * amount;
}

function restingArms(t, pose, calm = 1) {
  pose.leftArm.z = Math.cos(t * 2) * 0.03 * calm + ARM_REST;
  pose.rightArm.z = Math.cos(t * 2 + Math.PI) * 0.03 * calm - ARM_REST;
}

function emptyPose() {
  const pose = { rootY: 0 };
  for (const part of PARTS) pose[part] = { x: 0, y: 0, z: 0 };
  return pose;
}

const POSES = {
  idle(t, pose) {
    restingArms(t, pose);
    pose.body.x = breathe(t);
    pose.head.y = Math.sin(t * 0.5) * 0.05;
  },

  'idle-bakinma'(t, pose) {
    restingArms(t, pose);
    pose.body.x = breathe(t);
    pose.head.y = Math.sin(t * 1.5) * 0.5;
    pose.head.x = Math.sin(t * 0.8) * 0.08;
  },

  'idle-gerinme'(t, pose, dur) {
    const e = envelope(t / dur);
    pose.leftArm.z = ARM_REST + e * 2.8;
    pose.rightArm.z = -ARM_REST - e * 2.8;
    pose.leftArm.x = -e * 0.2;
    pose.rightArm.x = -e * 0.2;
    pose.head.x = -e * 0.3;
    pose.body.x = -e * 0.12;
  },

  'idle-esneme'(t, pose, dur) {
    const e = envelope(t / dur);
    pose.head.x = -e * 0.35;
    pose.rightArm.x = -e * 1.6;
    pose.rightArm.z = -ARM_REST - e * 0.9;
    pose.body.x = -e * 0.06;
    restingArms(t, pose, 0.4);
    pose.rightArm.x = -e * 1.6;
    pose.rightArm.z = -ARM_REST - e * 0.9;
  },

  'idle-kasima'(t, pose, dur) {
    const e = envelope(t / dur);
    restingArms(t, pose, 0.3);
    pose.rightArm.x = -e * (1.9 + Math.sin(t * 16) * 0.08);
    pose.rightArm.z = -ARM_REST - e * 0.45;
    pose.head.x = e * 0.12;
    pose.head.z = -e * 0.08;
  },

  walk(t, pose) {
    const w = t * 8;
    pose.leftLeg.x = Math.sin(w) * 0.5;
    pose.rightLeg.x = Math.sin(w + Math.PI) * 0.5;
    pose.leftArm.x = Math.sin(w + Math.PI) * 0.5;
    pose.rightArm.x = Math.sin(w) * 0.5;
    pose.leftArm.z = Math.cos(w) * 0.03 + ARM_REST;
    pose.rightArm.z = Math.cos(w + Math.PI) * 0.03 - ARM_REST;
    pose.head.y = Math.sin(w / 4) * 0.2;
    pose.head.x = Math.sin(w / 5) * 0.1;
  },

  talk(t, pose) {
    pose.head.x = Math.sin(t * 6) * 0.07;
    pose.head.y = Math.sin(t * 4.3) * 0.13;
    pose.body.y = Math.sin(t * 3) * 0.05;
    pose.leftArm.z = ARM_REST + 0.1 + Math.sin(t * 5) * 0.14;
    pose.rightArm.z = -ARM_REST - 0.1 - Math.sin(t * 5 + 1) * 0.14;
    pose.leftArm.x = Math.sin(t * 5 + 0.5) * 0.18;
    pose.rightArm.x = Math.sin(t * 5 + 2) * 0.18;
  },

  listen(t, pose) {
    restingArms(t, pose, 0.35);
    pose.head.z = 0.18;
    pose.head.y = 0.14;
    pose.head.x = -0.06;
    pose.body.x = breathe(t, 0.008);
  },

  think(t, pose) {
    pose.head.x = 0.2;
    pose.head.y = -0.18;
    pose.head.z = 0.06;
    pose.rightArm.x = -1.55 + Math.sin(t * 1.4) * 0.05;
    pose.rightArm.z = 0.22;
    pose.leftArm.x = -0.25;
    pose.leftArm.z = 0.42;
    pose.body.x = breathe(t, 0.008);
  },

  sleep(t, pose) {
    pose.head.x = 0.45;
    pose.head.z = 0.12;
    pose.leftArm.z = ARM_REST * 1.5;
    pose.rightArm.z = -ARM_REST * 1.5;
    pose.body.x = Math.sin(t * 0.8) * 0.02;
  },

  'night-sleepy'(t, pose) {
    const drift = Math.max(0, Math.sin(t * 0.35));
    restingArms(t, pose, 0.3);
    pose.head.x = 0.08 + drift * 0.3;
    pose.head.z = 0.05;
    pose.body.x = Math.sin(t * 0.9) * 0.015;
  },

  wake(t, pose, dur) {
    const p = clamp(t / dur, 0, 1);
    const rise = 1 - p;
    const stretch = envelope(p);
    pose.head.x = 0.45 * rise - stretch * 0.3;
    pose.leftArm.z = ARM_REST + stretch * 2.4;
    pose.rightArm.z = -ARM_REST - stretch * 2.4;
    pose.body.x = -stretch * 0.1;
  },

  jump(t, pose, dur) {
    const p = clamp(t / dur, 0, 1);
    const lift = Math.sin(p * Math.PI);
    pose.rootY = lift * 7;
    pose.leftLeg.x = -lift * 0.5;
    pose.rightLeg.x = -lift * 0.5;
    pose.leftArm.z = ARM_REST + lift * 1.3;
    pose.rightArm.z = -ARM_REST - lift * 1.3;
    pose.head.x = -lift * 0.15;
  },

  tickle(t, pose, dur) {
    const e = envelope(t / dur);
    pose.body.z = Math.sin(t * 22) * 0.06 * e;
    pose.head.z = Math.sin(t * 20) * 0.12 * e;
    pose.leftArm.x = -e * (0.7 + Math.sin(t * 18) * 0.4);
    pose.rightArm.x = -e * (0.7 + Math.sin(t * 18 + 1) * 0.4);
    pose.leftArm.z = ARM_REST + e * 0.4;
    pose.rightArm.z = -ARM_REST - e * 0.4;
  },

  'nod-yes'(t, pose, dur) {
    const e = envelope(t / dur);
    restingArms(t, pose, 0.3);
    pose.head.x = Math.sin(t * 9) * 0.3 * e;
  },

  'nod-no'(t, pose, dur) {
    const e = envelope(t / dur);
    restingArms(t, pose, 0.3);
    pose.head.y = Math.sin(t * 8) * 0.38 * e;
  },

  wave(t, pose, dur) {
    const p = clamp(t / dur, 0, 1);
    const e = Math.sin(clamp(p * 2.5, 0, 1) * Math.PI * 0.5) * (p > 0.8 ? (1 - p) / 0.2 : 1);
    pose.leftArm.z = ARM_REST + e * (2.75 + Math.sin(t * 9) * 0.25);
    pose.rightArm.z = -ARM_REST;
    pose.head.z = -e * 0.1;
    pose.head.y = e * 0.1;
  },

  dance(t, pose) {
    const b = t * 5;
    pose.rootY = Math.abs(Math.sin(b)) * 2.2;
    pose.body.y = Math.sin(b / 2) * 0.25;
    pose.body.z = Math.sin(b) * 0.06;
    pose.head.y = Math.sin(b / 2) * 0.3;
    pose.head.x = Math.sin(b) * 0.12;
    pose.leftArm.z = ARM_REST + 1.9 + Math.sin(b) * 0.5;
    pose.rightArm.z = -ARM_REST - 1.9 - Math.sin(b + Math.PI) * 0.5;
    pose.leftArm.x = Math.sin(b) * 0.4;
    pose.rightArm.x = Math.sin(b + Math.PI) * 0.4;
    pose.leftLeg.x = Math.sin(b + Math.PI) * 0.25;
    pose.rightLeg.x = Math.sin(b) * 0.25;
  },

  climb(t, pose) {
    const c = t * 5;
    pose.leftArm.x = -2.6 + Math.sin(c) * 0.55;
    pose.rightArm.x = -2.6 + Math.sin(c + Math.PI) * 0.55;
    pose.leftArm.z = ARM_REST + 0.12;
    pose.rightArm.z = -ARM_REST - 0.12;
    pose.leftLeg.x = -0.55 + Math.sin(c + Math.PI) * 0.4;
    pose.rightLeg.x = -0.55 + Math.sin(c) * 0.4;
    pose.body.x = -0.12;
    pose.head.x = -0.2;
  },

  'climb-hold'(t, pose) {
    pose.leftArm.x = -2.7;
    pose.rightArm.x = -2.7;
    pose.leftArm.z = ARM_REST + 0.12;
    pose.rightArm.z = -ARM_REST - 0.12;
    pose.leftLeg.x = -0.5 + Math.sin(t * 1.5) * 0.06;
    pose.rightLeg.x = -0.6 + Math.sin(t * 1.5 + 1) * 0.06;
    pose.body.x = -0.1;
    pose.head.x = -0.15 + Math.sin(t * 0.9) * 0.05;
  },

  peek(t, pose) {
    pose.leftArm.x = -2.7;
    pose.rightArm.x = -2.7;
    pose.leftArm.z = ARM_REST + 0.12;
    pose.rightArm.z = -ARM_REST - 0.12;
    pose.leftLeg.x = -0.5;
    pose.rightLeg.x = -0.6;
    pose.body.x = -0.1;
    pose.head.x = Math.sin(t * 1.1) * 0.35;
    pose.head.y = Math.sin(t * 0.6) * 0.15;
  },

  'sit-edge'(t, pose) {
    pose.leftLeg.x = -1.35 + Math.sin(t * 3) * 0.45;
    pose.rightLeg.x = -1.35 + Math.sin(t * 3 + Math.PI) * 0.45;
    pose.leftArm.x = 0.35;
    pose.rightArm.x = 0.35;
    pose.leftArm.z = ARM_REST + 0.2;
    pose.rightArm.z = -ARM_REST - 0.2;
    pose.body.x = breathe(t, 0.01);
    pose.head.y = Math.sin(t * 0.5) * 0.18;
    pose.head.x = 0.08;
  },

  fall(t, pose) {
    pose.leftArm.z = ARM_REST + 2.6 + Math.sin(t * 12) * 0.25;
    pose.rightArm.z = -ARM_REST - 2.6 - Math.sin(t * 12 + 1) * 0.25;
    pose.leftLeg.x = -0.35 + Math.sin(t * 9) * 0.25;
    pose.rightLeg.x = -0.2 + Math.sin(t * 9 + Math.PI) * 0.25;
    pose.body.x = -0.15;
    pose.head.x = -0.3;
  },

  land(t, pose, dur) {
    const e = envelope(t / dur);
    pose.leftLeg.x = -e * 0.55;
    pose.rightLeg.x = -e * 0.55;
    pose.body.x = e * 0.35;
    pose.head.x = e * 0.2;
    pose.leftArm.x = -e * 0.7;
    pose.rightArm.x = -e * 0.7;
    pose.leftArm.z = ARM_REST + e * 0.5;
    pose.rightArm.z = -ARM_REST - e * 0.5;
  },

  'scroll-gesture'(t, pose, dur) {
    const e = envelope(t / dur);
    pose.leftArm.x = -2.7;
    pose.leftArm.z = ARM_REST + 0.12;
    pose.leftLeg.x = -0.5;
    pose.rightLeg.x = -0.6;
    pose.body.x = -0.1;
    pose.rightArm.x = -1.5 - e * (0.5 + Math.sin(t * 7) * 0.5);
    pose.rightArm.z = -ARM_REST - 0.3;
    pose.head.x = 0.12;
  },

  held(t, pose) {
    pose.leftArm.z = ARM_REST + 2.5 + Math.sin(t * 4) * 0.15;
    pose.rightArm.z = -ARM_REST - 2.5 - Math.sin(t * 4 + 0.5) * 0.15;
    pose.leftLeg.x = Math.sin(t * 3) * 0.18;
    pose.rightLeg.x = Math.sin(t * 3 + 0.6) * 0.18;
    pose.body.z = Math.sin(t * 2.5) * 0.08;
    pose.head.x = -0.12;
  },

  'held-wheee'(t, pose) {
    pose.leftArm.z = ARM_REST + 2.7 + Math.sin(t * 9) * 0.4;
    pose.rightArm.z = -ARM_REST - 2.7 - Math.sin(t * 9 + 1.2) * 0.4;
    pose.leftLeg.x = Math.sin(t * 7) * 0.45;
    pose.rightLeg.x = Math.sin(t * 7 + Math.PI) * 0.45;
    pose.body.z = Math.sin(t * 6) * 0.14;
    pose.head.x = -0.25;
    pose.head.y = Math.sin(t * 5) * 0.25;
  },
};

const ONE_SHOT = {
  land: { duration: 0.5 },
  'scroll-gesture': { duration: 2.2 },
  'idle-bakinma': { duration: 3.5 },
  'idle-gerinme': { duration: 3.0 },
  'idle-esneme': { duration: 2.8 },
  'idle-kasima': { duration: 2.4 },
  wake: { duration: 1.6 },
  jump: { duration: 0.75 },
  tickle: { duration: 1.8 },
  'nod-yes': { duration: 1.2 },
  'nod-no': { duration: 1.2 },
  wave: { duration: 2.4 },
};

const IDLE_VARIANTS = ['idle-bakinma', 'idle-gerinme', 'idle-esneme', 'idle-kasima'];
const IDLE_VARIANT_MIN = 9;
const IDLE_VARIANT_MAX = 22;

const SIT_LEG_X = -Math.PI / 2;
const SIT_ROOT_Y = -4;

export class KevinAnimator extends PlayerAnimation {
  constructor() {
    super();
    this.state = 'idle';
    this.t = 0;
    this.prevState = null;
    this.prevT = 0;
    this.blend = 1;
    this.oneShot = null;
    this.returnTo = 'idle';
    this.sitting = false;
    this.sitBlend = 0;
    this.facing = 0;
    this.facingCurrent = 0;
    this.cem = null;
    this.cemContext = null;
    this.lookYaw = 0;
    this.lookPitch = 0;
    this.rootRotation = 0;
    this.rootRotationCurrent = 0;
    this.idleVariantIn = this.randomIdleDelay();
    this.baseY = null;
    this.poseA = emptyPose();
    this.poseB = emptyPose();
    this.poseOut = emptyPose();
    this.prevDuration = 0;
  }

  randomIdleDelay() {
    return IDLE_VARIANT_MIN + Math.random() * (IDLE_VARIANT_MAX - IDLE_VARIANT_MIN);
  }

  setState(name) {
    if (!POSES[name] || ONE_SHOT[name]) return;
    this.returnTo = name;
    if (this.oneShot) return;
    this.switchTo(name);
  }

  play(name) {
    const spec = ONE_SHOT[name];
    if (!spec) return;
    this.oneShot = { name, duration: spec.duration };
    this.switchTo(name);
  }

  setSitting(value) {
    this.sitting = !!value;
  }

  setFacing(radians) {
    this.facing = radians;
  }

  // Fresh Moves gibi bir CEM paketi yuklendiginde, bizim urettigimiz poz
  // "vanilla" katman oluyor; paket onun uzerine kendi animasyonunu yaziyor.
  setCemAnimator(cem) {
    this.cem = cem;
  }

  setCemContext(context) {
    this.cemContext = context;
  }

  // Karakterin fareye bakmasi: poza eklenen kafa acisi.
  // CEM paketi head.rx/ry'yi okuyup uzerine yazdigi icin bu deger korunuyor.
  setLook(yaw, pitch) {
    this.lookYaw = yaw;
    this.lookPitch = pitch;
  }

  setRootRotation(z) {
    this.rootRotation = z;
  }

  cemPose(pose) {
    const input = {};
    for (const [ours, cemName] of Object.entries(CEM_NAME)) {
      const p = pose[ours] || { x: 0, y: 0, z: 0 };
      input[cemName] = { rx: p.x, ry: p.y, rz: p.z, tx: 0, ty: 0, tz: 0 };
    }
    return this.cem.apply(input, this.cemContext || {});
  }

  switchTo(name) {
    if (this.state === name) return;
    this.prevState = this.state;
    this.prevT = this.t;
    this.prevDuration = this.durationOf(this.state);
    this.state = name;
    this.t = 0;
    this.blend = 0;
  }

  durationOf(name) {
    if (this.oneShot && this.oneShot.name === name) return this.oneShot.duration;
    const spec = ONE_SHOT[name];
    return spec ? spec.duration : 0;
  }

  fillPose(name, t, pose, duration) {
    for (const part of PARTS) {
      const p = pose[part];
      p.x = 0;
      p.y = 0;
      p.z = 0;
    }
    pose.rootY = 0;
    POSES[name](t, pose, duration);
  }

  animate(player, delta) {
    this.t += delta;
    this.prevT += delta;

    if (this.oneShot && this.t >= this.oneShot.duration) {
      const back = this.returnTo;
      this.oneShot = null;
      this.switchTo(back);
      this.idleVariantIn = this.randomIdleDelay();
    }

    if (!this.oneShot && this.state === 'idle') {
      this.idleVariantIn -= delta;
      if (this.idleVariantIn <= 0) {
        this.play(IDLE_VARIANTS[Math.floor(Math.random() * IDLE_VARIANTS.length)]);
      }
    }

    this.fillPose(this.state, this.t, this.poseA, this.durationOf(this.state));
    this.poseA.head.y += this.lookYaw;
    this.poseA.head.x += this.lookPitch;

    let pose = this.poseA;
    if (this.blend < 1 && this.prevState) {
      this.blend = Math.min(1, this.blend + delta / BLEND_TIME);
      this.fillPose(this.prevState, this.prevT, this.poseB, this.prevDuration);
      pose = this.mix(this.poseB, this.poseA, this.blend);
    } else if (this.blend >= 1) {
      this.prevState = null;
    }

    const sitTarget = this.sitting ? 1 : 0;
    this.sitBlend += clamp(sitTarget - this.sitBlend, -delta / 0.4, delta / 0.4);

    const turn = delta / 0.35;
    this.facingCurrent += clamp(this.facing - this.facingCurrent, -turn * Math.PI, turn * Math.PI);

    const flip = delta / 0.45;
    this.rootRotationCurrent += clamp(
      this.rootRotation - this.rootRotationCurrent,
      -flip * Math.PI,
      flip * Math.PI,
    );

    this.apply(player, pose);
  }

  mix(a, b, k) {
    const out = this.poseOut;
    for (const part of PARTS) {
      out[part].x = a[part].x + (b[part].x - a[part].x) * k;
      out[part].y = a[part].y + (b[part].y - a[part].y) * k;
      out[part].z = a[part].z + (b[part].z - a[part].z) * k;
    }
    out.rootY = a.rootY + (b.rootY - a.rootY) * k;
    return out;
  }

  apply(player, pose) {
    const s = this.sitBlend;
    if (this.baseY === null) this.baseY = player.position.y;

    let resolved = pose;
    if (this.cem) {
      try {
        const cemResult = this.cemPose(pose);
        // .jem'deki parcalar "invertAxis": "xy" ile tanimli: x ve y eksenleri ters.
        resolved = { rootY: pose.rootY };
        for (const name of CEM_PARTS) {
          const ours = CEM_TO_OURS[name];
          const r = cemResult[name];
          resolved[ours] = { x: -r.rx, y: -r.ry, z: r.rz };
        }
      } catch {
        resolved = pose;
      }
    }

    for (const part of PARTS) {
      const target = player.skin[part];
      const value = resolved[part];
      target.rotation.x = value.x;
      target.rotation.y = value.y;
      target.rotation.z = value.z;
    }
    pose = resolved;

    if (s > 0) {
      player.skin.leftLeg.rotation.x = pose.leftLeg.x * (1 - s) + SIT_LEG_X * s;
      player.skin.rightLeg.rotation.x = pose.rightLeg.x * (1 - s) + SIT_LEG_X * s;
      player.skin.leftLeg.rotation.z = pose.leftLeg.z * (1 - s) + 0.08 * s;
      player.skin.rightLeg.rotation.z = pose.rightLeg.z * (1 - s) - 0.08 * s;
    }

    player.position.y = this.baseY + pose.rootY + SIT_ROOT_Y * s;
    player.rotation.y = this.facingCurrent;
    player.rotation.z = this.rootRotationCurrent;
  }
}

export const ANIMATION_STATES = Object.keys(POSES);
