// Akil: Kevin'in seni tanimasi ve hatirlamasi.
//  - Hafiza: konusmalardan ogrendigi kalici bilgiler (memory.json). Model
//    cevabina [hatirla: ...] / [unut: ...] etiketi koyuyor; ayri bir model
//    cagrisi yok, token harcamiyor.
//  - Duygu: cevabin basinda [mutlu] gibi etiket; govde o duyguya uyan hareketi
//    oynatiyor.
//  - Kamera: sen isteyince (ya da ayarda aciksa seslenince) tek kare cekip
//    goruntu modeline soruyor. Tanittigin yuzler faces/ altinda; kamerada
//    biri varsa bu fotograflarla karsilastiriliyor. Kare saklanmiyor.

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const MOODS = ['mutlu', 'heyecanli', 'havali', 'uzgun', 'utangac', 'saskin', 'dusunceli', 'sevgi', 'selam', 'kutlama', 'alay', 'saygi', 'notr'];
const MAX_FACTS = 120;

function asciiFold(s) {
  return s.toLocaleLowerCase('tr')
    .replace(/ı/g, 'i').replace(/ğ/g, 'g').replace(/ü/g, 'u')
    .replace(/ş/g, 's').replace(/ö/g, 'o').replace(/ç/g, 'c');
}

function createAkil({ userData, runCommand }) {
  const memoryPath = path.join(userData, 'memory.json');
  const facesDir = path.join(userData, 'faces');

  function load() {
    try {
      const data = JSON.parse(fs.readFileSync(memoryPath, 'utf-8'));
      return { facts: Array.isArray(data.facts) ? data.facts : [] };
    } catch {
      return { facts: [] };
    }
  }

  function save(mem) {
    fs.writeFileSync(memoryPath, JSON.stringify(mem, null, 2));
  }

  function remember(text) {
    const t = text.trim().replace(/\s+/g, ' ');
    if (t.length < 3) return;
    const mem = load();
    const key = asciiFold(t);
    if (mem.facts.some((f) => asciiFold(f.text) === key)) return;
    mem.facts.push({ text: t, at: new Date().toISOString() });
    if (mem.facts.length > MAX_FACTS) mem.facts.splice(0, mem.facts.length - MAX_FACTS);
    save(mem);
    console.log('[kevin] hatirladi:', t);
  }

  // Eslesme gevsek: "kahveyi sekersiz icer" -> icinde gecen bilgi silinir
  function forget(text) {
    const key = asciiFold(text.trim());
    if (key.length < 3) return;
    const mem = load();
    const before = mem.facts.length;
    mem.facts = mem.facts.filter((f) => {
      const fk = asciiFold(f.text);
      return !(fk.includes(key) || key.includes(fk));
    });
    if (mem.facts.length !== before) {
      save(mem);
      console.log('[kevin] unuttu:', text);
    }
  }

  function faces() {
    try {
      return fs.readdirSync(facesDir)
        .filter((f) => f.endsWith('.jpg'))
        .map((f) => ({ name: f.slice(0, -4), file: path.join(facesDir, f) }));
    } catch {
      return [];
    }
  }

  // Modelin her cevapta uydugu kurallar + bildikleri. Kullanicinin kendi
  // kisilik metni olsa da eklenir (etiketler govde ve hafiza icin sart).
  function personaBlock() {
    const mem = load();
    const lines = [
      'CEVAP BICIMI: Her cevabin EN BASINA tek bir duygu etiketi koy, su listeden:',
      MOODS.map((m) => `[${m}]`).join(' ') + '.',
      'Etiket sesli okunmaz, govden o duyguyu hareketle gosterir. Duygu gercekten belirgin degilse [notr] koy.',
      'HAFIZA: Kullanici kendisi hakkinda KALICI bir sey soylerse (adi, yasi, isi, sevdikleri, sevmedikleri,',
      'aliskanliklari, tanidiklari, projeleri) ya da seni duzeltirse ("oyle degil, boyle"), cevabin SONUNA',
      '[hatirla: kullanici hakkinda kisa ve net bilgi] ekle. Ornek: [hatirla: Kullanicinin adi Ali]',
      '[hatirla: Kahveyi sekersiz icer]. Kullanici "aklinda tut", "unutma", "hatirla" derse MUTLAKA ekle.',
      'Eski bir bilgiyi duzeltiyorsa ayrica [unut: eski bilgi] ekle.',
      'Su anki istegi, yaptigin isi, ekranda gordugunu, havayi ASLA hatirlama; sadece kisinin kendisi.',
      '"Hatirladim" deyip etiketi koymamak YALAN olur.',
    ];
    if (mem.facts.length) {
      lines.push('KULLANICI HAKKINDA BILDIKLERIN (onceki konusmalardan; dogal kullan, sayip dokme):');
      for (const f of mem.facts.slice(-60)) lines.push(`- ${f.text}`);
    }
    const known = faces().map((f) => f.name);
    if (known.length) lines.push(`Kameradan tanidigin yuzler: ${known.join(', ')}.`);
    return lines.join('\n');
  }

  // Cevaptan etiketleri ayikla, hafizayi guncelle
  function parseReply(raw) {
    let text = raw;
    let mood = '';
    const head = text.match(/^\s*\[([^\]\n]{2,20})\]\s*/);
    if (head) {
      const m = asciiFold(head[1]).replace(/[^a-z]/g, '');
      if (MOODS.includes(m)) mood = m;
      text = text.slice(head[0].length);
    }
    text = text.replace(/\[(hatirla|hatırla|remember)\s*:\s*([^\]]+)\]/gi, (_all, _k, fact) => {
      remember(fact);
      return '';
    });
    text = text.replace(/\[(unut|forget)\s*:\s*([^\]]+)\]/gi, (_all, _k, fact) => {
      forget(fact);
      return '';
    });
    // Yanlis yere konmus duygu etiketleri de okunmasin
    text = text.replace(/\[([a-zçğıöşü]{3,12})\]/gi, (all, word) => (MOODS.includes(asciiFold(word)) ? '' : all));
    return { text: text.replace(/\s{2,}/g, ' ').trim(), mood };
  }

  async function captureCamera(device) {
    const out = path.join(os.tmpdir(), `kevin-cam-${crypto.randomUUID()}.jpg`);
    // Ilk kareler karanlik (pozlama oturmadan): 1 sn sonrasini al
    await runCommand('ffmpeg', [
      '-y', '-loglevel', 'error', '-f', 'v4l2', '-i', device || '/dev/video0',
      '-ss', '1', '-frames:v', '1', '-vf', 'scale=960:-2', out,
    ]);
    try {
      return fs.readFileSync(out).toString('base64');
    } finally {
      fs.rmSync(out, { force: true });
    }
  }

  async function rememberFace(name, device) {
    const clean = String(name || '').trim().replace(/[\\/:*?"<>|]/g, '').slice(0, 40);
    if (!clean) return 'isim gerekli';
    const image = await captureCamera(device);
    fs.mkdirSync(facesDir, { recursive: true });
    fs.writeFileSync(path.join(facesDir, `${clean}.jpg`), Buffer.from(image, 'base64'));
    return `${clean} yuzu kaydedildi, artik kameradan taniyabilirsin`;
  }

  // Kameraya bak; tanittigin yuzler varsa onlarla karsilastir
  async function lookAtCamera(question, device, describeImages) {
    const frame = await captureCamera(device);
    const known = faces().slice(0, 3);
    const refs = known.map((f) => fs.readFileSync(f.file).toString('base64'));
    let prompt = 'Ilk goruntu su an kameradan. ';
    if (known.length) {
      prompt += `Sonraki goruntuler tanidigin kisiler, sirasiyla: ${known.map((f) => f.name).join(', ')}. `
        + 'Ilk goruntude bu kisilerden biri varsa adini soyle (emin degilsen "benziyor" de). ';
    }
    prompt += question && question.trim()
      ? `Soru: ${question.trim()}`
      : 'Kim var, ne yapiyor, elinde ya da onunde ne var? Kisa anlat.';
    return describeImages([frame, ...refs], prompt);
  }

  return { load, save, remember, forget, faces, personaBlock, parseReply, rememberFace, lookAtCamera };
}

module.exports = { createAkil, MOODS };
