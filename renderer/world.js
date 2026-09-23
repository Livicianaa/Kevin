const GRAVITY = 2200;
const TERMINAL_SPEED = 1500;
const WALK_SPEED = 62;
const CLIMB_SPEED = 70;
const EDGE_PADDING = 6;

const FACE_FRONT = 0;
const FACE_SIDE = 0.95;
const FACE_WALL = Math.PI / 2;

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

export class KevinWorld {
  constructor(info) {
    this.info = info;
    this.left = info.reserved.left + EDGE_PADDING;
    this.right = info.width - info.reserved.right - EDGE_PADDING;
    this.ceiling = info.reserved.top;
    this.ground = info.ground;

    this.x = (this.left + this.right) / 2;
    this.y = this.ground;
    this.vy = 0;
    this.dir = 1;

    this.mode = 'idle';
    this.timer = rand(1.5, 4);
    this.target = null;
    this.wall = null;
    this.climbGoal = null;
    this.paused = false;
  }

  get animation() {
    switch (this.mode) {
      case 'walk': return 'walk';
      case 'climb': return 'climb';
      case 'hold': return 'climb-hold';
      case 'peek': return 'peek';
      case 'scroll': return 'scroll-gesture';
      case 'sit': return 'sit-edge';
      case 'fall': return 'fall';
      default: return 'idle';
    }
  }

  get facing() {
    switch (this.mode) {
      case 'walk': return this.dir * FACE_SIDE;
      case 'climb':
      case 'hold':
      case 'scroll': return this.dir * FACE_WALL;
      case 'sit': return this.dir * 0.45;
      case 'peek':
      case 'fall': return FACE_FRONT;
      default: return FACE_FRONT;
    }
  }

  // Sohbet / konusma sirasinda dunya donuyor ama karakter yerinde kaliyor.
  setPaused(value) {
    this.paused = !!value;
    if (this.paused && (this.mode === 'climb' || this.mode === 'hold' || this.mode === 'peek' || this.mode === 'scroll')) {
      this.release();
    }
  }

  release() {
    this.mode = 'fall';
    this.vy = 0;
    this.wall = null;
  }

  groundedIdle(min = 1.5, max = 5) {
    this.mode = 'idle';
    this.timer = rand(min, max);
    this.target = null;
  }

  planNext() {
    const shell = this.info.shell;
    const options = ['walk', 'walk', 'walk', 'idle'];
    if (this.right - this.left > 260) options.push('climb', 'climb');
    if (shell.edge === 'top' && this.ceiling > 30) options.push('shell');
    if (shell.edge === 'left' || shell.edge === 'right') options.push('shell');

    const choice = pick(options);

    if (choice === 'idle') {
      this.groundedIdle(2, 6);
      return;
    }

    if (choice === 'walk') {
      this.target = rand(this.left + 40, this.right - 40);
      this.dir = this.target > this.x ? 1 : -1;
      this.mode = 'walk';
      return;
    }

    const wall = choice === 'shell' && (shell.edge === 'left' || shell.edge === 'right')
      ? shell.edge
      : pick(['left', 'right']);

    this.wall = wall;
    this.target = wall === 'left' ? this.left : this.right;
    this.dir = wall === 'left' ? -1 : 1;
    this.mode = 'walk';
    this.climbGoal = choice === 'shell'
      ? this.ceiling + 34
      : rand(this.ground - (this.ground - this.ceiling) * 0.7, this.ground - (this.ground - this.ceiling) * 0.35);
  }

  update(dt) {
    if (this.paused) {
      if (this.mode !== 'sit') this.mode = 'idle';
      return;
    }

    switch (this.mode) {
      case 'idle':
        this.timer -= dt;
        if (this.timer <= 0) this.planNext();
        break;

      case 'walk': {
        const step = WALK_SPEED * dt * this.dir;
        this.x += step;
        const reached = this.dir > 0 ? this.x >= this.target : this.x <= this.target;
        if (reached) {
          this.x = this.target;
          if (this.wall) {
            this.mode = 'climb';
          } else {
            this.groundedIdle();
          }
        }
        break;
      }

      case 'climb':
        this.y -= CLIMB_SPEED * dt;
        if (this.y <= this.climbGoal) {
          this.y = this.climbGoal;
          if (this.climbGoal <= this.ceiling + 40) {
            this.mode = 'sit';
            this.timer = rand(8, 20);
          } else {
            this.mode = 'hold';
            this.timer = rand(0.6, 1.4);
          }
        }
        break;

      case 'hold':
        this.timer -= dt;
        if (this.timer <= 0) {
          this.mode = 'peek';
          this.timer = rand(2.5, 5);
        }
        break;

      case 'peek':
        this.timer -= dt;
        if (this.timer <= 0) {
          if (Math.random() < 0.45) {
            this.mode = 'scroll';
            this.timer = 2.2;
          } else if (Math.random() < 0.5) {
            this.release();
          } else {
            this.climbGoal = this.ceiling + 34;
            this.mode = 'climb';
          }
        }
        break;

      case 'scroll':
        this.timer -= dt;
        if (this.timer <= 0) {
          if (Math.random() < 0.5) this.release();
          else {
            this.mode = 'hold';
            this.timer = rand(0.5, 1.2);
          }
        }
        break;

      case 'sit':
        this.timer -= dt;
        if (this.timer <= 0) this.release();
        break;

      case 'fall':
        this.vy = Math.min(this.vy + GRAVITY * dt, TERMINAL_SPEED);
        this.y += this.vy * dt;
        if (this.y >= this.ground) {
          this.y = this.ground;
          this.vy = 0;
          this.wall = null;
          this.groundedIdle(1, 3);
          return 'land';
        }
        break;
    }

    this.x = Math.min(Math.max(this.x, this.left), this.right);
    this.y = Math.min(Math.max(this.y, this.ceiling), this.ground);
    return null;
  }
}
