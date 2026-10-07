// Calan sarkinin temposu (BPM), vurus zamani ve enerjisi. Sistem sesini
// (varsayilan cikisin monitoru) 8 kHz mono dinler; sadece muzik calarken acik.
// Govde bununla dansi vurusa oturtuyor ve sarkiya uygun dans seciyor.
const { spawn } = require('node:child_process');

const RATE = 8000;
const HOP = 80; // 10 ms
const HOPS_PER_SEC = RATE / HOP;
const WINDOW_HOPS = 8 * HOPS_PER_SEC;
const REPORT_MS = 2000;
const MIN_BPM = 70;
const MAX_BPM = 180;

class BeatTracker {
  constructor(onReport) {
    this.onReport = onReport;
    this.proc = null;
    this.energies = [];
    this.onsets = [];
    this.hopTimes = [];
    this.pending = Buffer.alloc(0);
    this.prevLog = 0;
    this.timer = null;
  }

  running() {
    return Boolean(this.proc);
  }

  start() {
    if (this.proc || process.platform !== 'linux') return;
    try {
      this.proc = spawn('parec', ['-d', '@DEFAULT_MONITOR@', '--format=s16le', `--rate=${RATE}`, '--channels=1', '--raw', '--latency-msec=50']);
    } catch {
      this.proc = null;
      return;
    }
    this.proc.on('error', () => this.stop());
    this.proc.on('exit', () => {
      this.proc = null;
    });
    this.proc.stdout.on('data', (chunk) => this.feed(chunk));
    this.timer = setInterval(() => this.report(), REPORT_MS);
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
    if (this.proc) {
      this.proc.kill();
      this.proc = null;
      this.onReport({ bpm: 0, energy: 0.5, age: 0 });
    }
    this.energies = [];
    this.onsets = [];
    this.hopTimes = [];
    this.pending = Buffer.alloc(0);
  }

  feed(chunk) {
    let buf = this.pending.length ? Buffer.concat([this.pending, chunk]) : chunk;
    const hopBytes = HOP * 2;
    const now = performance.now();
    const hops = Math.floor(buf.length / hopBytes);
    for (let h = 0; h < hops; h++) {
      let sum = 0;
      for (let i = 0; i < HOP; i++) {
        const s = buf.readInt16LE(h * hopBytes + i * 2) / 32768;
        sum += s * s;
      }
      const e = sum / HOP;
      // Vurus gucu: enerjinin logaritmik artisi (sadece yukselisler)
      const log = Math.log10(1e-9 + e);
      const onset = Math.max(0, log - this.prevLog);
      this.prevLog = log;
      this.energies.push(e);
      this.onsets.push(onset);
      // Bu parcadaki son hop "simdi"; oncekiler 10 ms araliklarla geride
      this.hopTimes.push(now - (hops - 1 - h) * (1000 / HOPS_PER_SEC));
    }
    buf = buf.subarray(hops * hopBytes);
    this.pending = Buffer.from(buf);
    const extra = this.onsets.length - WINDOW_HOPS;
    if (extra > 0) {
      this.energies.splice(0, extra);
      this.onsets.splice(0, extra);
      this.hopTimes.splice(0, extra);
    }
  }

  report() {
    const r = analyze(this.onsets, this.energies);
    if (!r) return;
    const lastHopTime = this.hopTimes[this.hopTimes.length - 1];
    const age = (performance.now() - lastHopTime + r.lastBeatHopsAgo * (1000 / HOPS_PER_SEC)) / 1000;
    this.onReport({ bpm: r.bpm, energy: r.energy, age });
  }
}

// Ses yeterince yoksa (sessiz kisim, duraklatilmis) null
function analyze(onsets, energies) {
  const n = onsets.length;
  if (n < 4 * HOPS_PER_SEC) return null;
  const meanE = energies.reduce((a, b) => a + b, 0) / n;
  if (meanE < 1e-6) return null;

  const mean = onsets.reduce((a, b) => a + b, 0) / n;
  const x = onsets.map((v) => v - mean);

  // Otokorelasyon; 120 BPM civarina hafif oncelik (yari/iki kat tempo karismasin)
  const minLag = Math.floor((60 / MAX_BPM) * HOPS_PER_SEC);
  const maxLag = Math.ceil((60 / MIN_BPM) * HOPS_PER_SEC);
  const scores = [];
  for (let lag = minLag; lag <= maxLag; lag++) {
    let s = 0;
    for (let i = lag; i < n; i++) s += x[i] * x[i - lag];
    const bpm = (60 * HOPS_PER_SEC) / lag;
    const pref = Math.exp(-0.5 * (Math.log2(bpm / 120) / 0.9) ** 2);
    scores.push(s * pref);
  }
  let best = 0;
  for (let i = 1; i < scores.length; i++) if (scores[i] > scores[best]) best = i;
  if (scores[best] <= 0) return null;
  // Tepe noktasini komsularla incelt
  let lag = best + minLag;
  if (best > 0 && best < scores.length - 1) {
    const a = scores[best - 1];
    const b = scores[best];
    const c = scores[best + 1];
    const d = a - 2 * b + c;
    if (d < 0) lag += (0.5 * (a - c)) / d;
  }
  const bpm = (60 * HOPS_PER_SEC) / lag;

  // Faz: vurus izgarasinin son 4 sn'de en cok vurusa denk geldigi kaymasi
  const period = lag;
  const span = Math.min(n, 4 * HOPS_PER_SEC);
  let bestOff = 0;
  let bestSum = -1;
  const steps = Math.max(1, Math.round(period));
  for (let off = 0; off < steps; off++) {
    let s = 0;
    for (let t = n - 1 - off; t >= n - span; t -= period) s += onsets[Math.round(t)] || 0;
    if (s > bestSum) {
      bestSum = s;
      bestOff = off;
    }
  }

  // Enerji: tempo + sarkinin ne kadar "vurmali" oldugu (ses seviyesinden bagimsiz)
  let varE = 0;
  for (const e of energies) varE += (e - meanE) ** 2;
  const cv = Math.sqrt(varE / n) / meanE;
  const punch = Math.min(1, cv / 1.6);
  const tempo = Math.min(1, Math.max(0, (bpm - 80) / 70));
  const energy = 0.55 * tempo + 0.45 * punch;

  return { bpm: Math.round(bpm * 10) / 10, energy: Math.round(energy * 100) / 100, lastBeatHopsAgo: bestOff };
}

module.exports = { BeatTracker, analyze, HOPS_PER_SEC };
