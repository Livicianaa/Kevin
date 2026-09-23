// OptiFine CEM (Custom Entity Models) animasyon ifadelerini calistiran kucuk yorumlayici.
// Fresh Moves gibi .jem paketleri animasyonlarini matematiksel ifadelerle yaziyor;
// burada onlari okuyup Kevin'in uzuvlarina uyguluyoruz. Paket dosyasi repoda DEGIL,
// kullanici kendi paketini koyuyor (bkz. bin/cem/).

const FUNCTIONS = {
  sin: Math.sin,
  cos: Math.cos,
  tan: Math.tan,
  asin: Math.asin,
  acos: Math.acos,
  atan: Math.atan,
  atan2: Math.atan2,
  abs: Math.abs,
  floor: Math.floor,
  ceil: Math.ceil,
  exp: Math.exp,
  log: Math.log,
  pow: Math.pow,
  sqrt: Math.sqrt,
  min: (...a) => Math.min(...a),
  max: (...a) => Math.max(...a),
  frac: (x) => x - Math.floor(x),
  signum: Math.sign,
  torad: (deg) => (deg * Math.PI) / 180,
  todeg: (rad) => (rad * 180) / Math.PI,
  clamp: (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x),
  between: (x, lo, hi) => (x >= lo && x <= hi ? 1 : 0),
  equals: (a, b, eps = 0.0001) => (Math.abs(a - b) <= eps ? 1 : 0),
  lerp: (t, a, b) => a + (b - a) * t,
  random: (seed) => {
    if (seed === undefined) return Math.random();
    const x = Math.sin(seed * 12.9898) * 43758.5453;
    return x - Math.floor(x);
  },
  fmod: (a, b) => a % b,
  wraprad: (r) => {
    let v = (r + Math.PI) % (2 * Math.PI);
    if (v < 0) v += 2 * Math.PI;
    return v - Math.PI;
  },
  wrapdeg: (d) => {
    let v = (d + 180) % 360;
    if (v < 0) v += 360;
    return v - 180;
  },
  print: (x) => x,
};

function tokenize(source) {
  const tokens = [];
  const re = /\s*(\d*\.?\d+|[A-Za-z_][A-Za-z_0-9.]*|&&|\|\||[<>!=]=|[-+*/%(),<>!])/g;
  let match;
  let index = 0;
  while ((match = re.exec(source)) !== null) {
    if (match.index !== index && source.slice(index, match.index).trim()) {
      throw new Error(`cozumlenemeyen parca: ${source.slice(index, match.index)}`);
    }
    tokens.push(match[1]);
    index = re.lastIndex;
  }
  if (source.slice(index).trim()) throw new Error(`cozumlenemeyen son: ${source.slice(index)}`);
  return tokens;
}

// Ifadeyi bir JS fonksiyonuna derliyoruz: her karede yeniden ayristirmak pahali olurdu.
function parse(source) {
  const tokens = tokenize(String(source));
  let pos = 0;

  const peek = () => tokens[pos];
  const next = () => tokens[pos++];
  const expect = (tok) => {
    if (next() !== tok) throw new Error(`${tok} bekleniyordu`);
  };

  function parseExpression() {
    return parseOr();
  }

  function parseOr() {
    let left = parseAnd();
    while (peek() === '||') {
      next();
      const right = parseAnd();
      const l = left;
      left = (ctx) => (truthy(l(ctx)) || truthy(right(ctx)) ? 1 : 0);
    }
    return left;
  }

  function parseAnd() {
    let left = parseComparison();
    while (peek() === '&&') {
      next();
      const right = parseComparison();
      const l = left;
      left = (ctx) => (truthy(l(ctx)) && truthy(right(ctx)) ? 1 : 0);
    }
    return left;
  }

  function parseComparison() {
    const left = parseAdditive();
    const op = peek();
    if (['<', '>', '<=', '>=', '==', '!='].includes(op)) {
      next();
      const right = parseAdditive();
      switch (op) {
        case '<': return (ctx) => (left(ctx) < right(ctx) ? 1 : 0);
        case '>': return (ctx) => (left(ctx) > right(ctx) ? 1 : 0);
        case '<=': return (ctx) => (left(ctx) <= right(ctx) ? 1 : 0);
        case '>=': return (ctx) => (left(ctx) >= right(ctx) ? 1 : 0);
        case '==': return (ctx) => (left(ctx) === right(ctx) ? 1 : 0);
        default: return (ctx) => (left(ctx) !== right(ctx) ? 1 : 0);
      }
    }
    return left;
  }

  function parseAdditive() {
    let left = parseMultiplicative();
    while (peek() === '+' || peek() === '-') {
      const op = next();
      const right = parseMultiplicative();
      const l = left;
      left = op === '+' ? (ctx) => l(ctx) + right(ctx) : (ctx) => l(ctx) - right(ctx);
    }
    return left;
  }

  function parseMultiplicative() {
    let left = parseUnary();
    while (peek() === '*' || peek() === '/' || peek() === '%') {
      const op = next();
      const right = parseUnary();
      const l = left;
      if (op === '*') left = (ctx) => l(ctx) * right(ctx);
      else if (op === '/') left = (ctx) => l(ctx) / right(ctx);
      else left = (ctx) => l(ctx) % right(ctx);
    }
    return left;
  }

  function parseUnary() {
    if (peek() === '-') {
      next();
      const operand = parseUnary();
      return (ctx) => -operand(ctx);
    }
    if (peek() === '!') {
      next();
      const operand = parseUnary();
      return (ctx) => (truthy(operand(ctx)) ? 0 : 1);
    }
    if (peek() === '+') {
      next();
      return parseUnary();
    }
    return parsePrimary();
  }

  function parsePrimary() {
    const token = next();
    if (token === undefined) throw new Error('ifade beklenmedik sekilde bitti');

    if (token === '(') {
      const inner = parseExpression();
      expect(')');
      return inner;
    }

    if (/^\d*\.?\d+$/.test(token)) {
      const value = parseFloat(token);
      return () => value;
    }

    if (peek() === '(') {
      next();
      const args = [];
      if (peek() !== ')') {
        args.push(parseExpression());
        while (peek() === ',') {
          next();
          args.push(parseExpression());
        }
      }
      expect(')');

      // if(kosul, deger, [kosul2, deger2, ...] varsayilan) - else-if zinciri
      if (token === 'if') {
        return (ctx) => {
          for (let i = 0; i + 1 < args.length; i += 2) {
            if (truthy(args[i](ctx))) return args[i + 1](ctx);
          }
          return args.length % 2 === 1 ? args[args.length - 1](ctx) : 0;
        };
      }

      const fn = FUNCTIONS[token];
      if (!fn) throw new Error(`bilinmeyen fonksiyon: ${token}`);
      return (ctx) => fn(...args.map((a) => a(ctx)));
    }

    return (ctx) => lookup(ctx, token);
  }

  const compiled = parseExpression();
  if (pos !== tokens.length) throw new Error(`fazladan belirtec: ${tokens[pos]}`);
  return compiled;
}

function truthy(value) {
  return value !== 0 && value !== false;
}

function lookup(ctx, name) {
  if (name === 'pi') return Math.PI;
  if (name === 'true') return 1;
  if (name === 'false') return 0;

  if (name in ctx.vars) return ctx.vars[name];

  const dot = name.indexOf('.');
  if (dot > 0) {
    const part = name.slice(0, dot);
    const field = name.slice(dot + 1);
    const target = ctx.parts[part];
    if (target && field in target) return target[field];
    return 0;
  }

  const value = ctx.context[name];
  if (value === undefined) return 0;
  return typeof value === 'boolean' ? (value ? 1 : 0) : value;
}

const PART_FIELDS = ['tx', 'ty', 'tz', 'rx', 'ry', 'rz'];
const CEM_PARTS = ['head', 'body', 'left_arm', 'right_arm', 'left_leg', 'right_leg'];

export class CemAnimator {
  constructor(jem) {
    this.assignments = [];
    this.warnings = [];
    this.collect(jem);
  }

  collect(node) {
    if (Array.isArray(node)) {
      node.forEach((n) => this.collect(n));
      return;
    }
    if (!node || typeof node !== 'object') return;

    for (const [key, value] of Object.entries(node)) {
      if (key === 'animations' && Array.isArray(value)) {
        for (const frame of value) {
          for (const [target, expression] of Object.entries(frame)) {
            try {
              this.assignments.push({ target, evaluate: parse(expression) });
            } catch (err) {
              this.warnings.push(`${target}: ${err.message}`);
            }
          }
        }
      } else {
        this.collect(value);
      }
    }
  }

  // pose: bizim vanilla pozumuz (CEM ifadeleri bunun uzerine yaziyor)
  apply(pose, context) {
    const parts = {};
    for (const name of CEM_PARTS) {
      const source = pose[name] || {};
      parts[name] = {
        tx: source.tx || 0,
        ty: source.ty || 0,
        tz: source.tz || 0,
        rx: source.rx || 0,
        ry: source.ry || 0,
        rz: source.rz || 0,
      };
    }

    const ctx = { vars: {}, parts, context };

    for (const { target, evaluate } of this.assignments) {
      let value;
      try {
        value = evaluate(ctx);
      } catch {
        continue;
      }
      if (!Number.isFinite(value)) continue;

      if (target.startsWith('var.') || target.startsWith('varb.')) {
        ctx.vars[target] = value;
        continue;
      }

      const dot = target.indexOf('.');
      if (dot < 0) continue;
      const part = target.slice(0, dot);
      const field = target.slice(dot + 1);
      if (parts[part] && PART_FIELDS.includes(field)) {
        parts[part][field] = value;
      }
    }

    return parts;
  }
}

export function loadCem(jemText) {
  const jem = JSON.parse(jemText.replace(/\/\/[^\n"]*$/gm, ''));
  return new CemAnimator(jem);
}

export { parse as parseCemExpression, CEM_PARTS };
