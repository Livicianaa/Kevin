// Kevin'in konustugu diller: Turkce + en cok konusulan 10 dil (yazisi bu
// bilgisayardaki fontlarla gorunenler; Cince/Japonca/Bengalce icin font yok).
// Her dilin Piper sesi ilk secildiginde Hugging Face'ten indirilir (~60 MB).

const fs = require('fs');
const path = require('path');

const VOICE_BASE = 'https://huggingface.co/rhasspy/piper-voices/resolve/main/';

const LANGS = {
  tr: {
    prompt: 'Turkce', voice: 'tr_TR-fahrettin-medium', voiceUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/tr/tr_TR/fahrettin/medium/tr_TR-fahrettin-medium.onnx',
    wake: ['Efendim?', 'Buyur', 'Ne oldu?', 'Dinliyorum'],
    slow: 'Bu biraz uzun sürdü, tekrar sorar mısın?', error: 'Bir sorun çıktı, tekrar söyler misin?',
    unclear: 'Hmm, tam anlayamadım, bir daha söyler misin?', noKey: 'Konuşabilmem için menüden kendi API anahtarını girmen lazım. Bana sağ tıkla, Yapay Zeka kısmına bak.',
  },
  en: {
    prompt: 'English', voice: 'en_US-lessac-medium', voicePath: 'en/en_US/lessac/medium/',
    wake: ['Yes?', 'I\'m here', 'What\'s up?', 'Listening'],
    slow: 'That took a while, can you ask again?', error: 'Something went wrong, can you say that again?',
    unclear: 'Hmm, I didn\'t quite get that, say it again?', noKey: 'I need your own API key to talk. Right-click me and open the AI section.',
  },
  es: {
    prompt: 'Espanol', voice: 'es_ES-davefx-medium', voicePath: 'es/es_ES/davefx/medium/',
    wake: ['¿Sí?', 'Dime', '¿Qué pasa?', 'Te escucho'],
    slow: 'Eso tardó un poco, ¿me lo preguntas otra vez?', error: 'Algo salió mal, ¿lo repites?',
    unclear: 'Mmm, no te entendí bien, ¿lo repites?', noKey: 'Necesito tu propia clave de API para hablar. Haz clic derecho sobre mí y abre la sección de IA.',
  },
  fr: {
    prompt: 'Francais', voice: 'fr_FR-siwis-medium', voicePath: 'fr/fr_FR/siwis/medium/',
    wake: ['Oui ?', 'Je t\'écoute', 'Quoi de neuf ?', 'Vas-y'],
    slow: 'Ça a pris du temps, tu peux redemander ?', error: 'Un problème est survenu, tu peux répéter ?',
    unclear: 'Hmm, je n\'ai pas bien compris, tu répètes ?', noKey: 'Il me faut ta propre clé API pour parler. Fais un clic droit sur moi et ouvre la section IA.',
  },
  de: {
    prompt: 'Deutsch', voice: 'de_DE-thorsten-medium', voicePath: 'de/de_DE/thorsten/medium/',
    wake: ['Ja?', 'Ich höre', 'Was gibt\'s?', 'Bin da'],
    slow: 'Das hat gedauert, fragst du nochmal?', error: 'Etwas ist schiefgelaufen, sag es bitte nochmal.',
    unclear: 'Hmm, das hab ich nicht ganz verstanden, nochmal?', noKey: 'Ich brauche deinen eigenen API-Schlüssel zum Reden. Rechtsklick auf mich, dann KI öffnen.',
  },
  pt: {
    prompt: 'Portugues', voice: 'pt_BR-faber-medium', voicePath: 'pt/pt_BR/faber/medium/',
    wake: ['Sim?', 'Pode falar', 'O que foi?', 'Estou ouvindo'],
    slow: 'Isso demorou, pode perguntar de novo?', error: 'Deu algum problema, pode repetir?',
    unclear: 'Hmm, não entendi direito, repete?', noKey: 'Preciso da sua própria chave de API para falar. Clique com o botão direito em mim e abra a seção de IA.',
  },
  ru: {
    prompt: 'Russkiy (Russian)', voice: 'ru_RU-irina-medium', voicePath: 'ru/ru_RU/irina/medium/',
    wake: ['Да?', 'Слушаю', 'Что такое?', 'Я тут'],
    slow: 'Это заняло время, спросишь ещё раз?', error: 'Что-то пошло не так, повтори, пожалуйста.',
    unclear: 'Хм, я не совсем понял, повтори?', noKey: 'Чтобы говорить, мне нужен твой API-ключ. Нажми на меня правой кнопкой и открой раздел ИИ.',
  },
  ar: {
    prompt: 'Arabic', voice: 'ar_JO-kareem-medium', voicePath: 'ar/ar_JO/kareem/medium/',
    wake: ['نعم؟', 'تفضل', 'ماذا هناك؟', 'أنا أسمعك'],
    slow: 'استغرق ذلك وقتا، هل تسأل مرة أخرى؟', error: 'حدثت مشكلة، هل تعيد؟',
    unclear: 'لم أفهم جيدا، هل تعيد؟', noKey: 'أحتاج مفتاح API الخاص بك لأتكلم. انقر بالزر الأيمن علي وافتح قسم الذكاء الاصطناعي.',
  },
  hi: {
    prompt: 'Hindi', voice: 'hi_IN-pratham-medium', voicePath: 'hi/hi_IN/pratham/medium/',
    wake: ['हाँ?', 'बोलो', 'क्या हुआ?', 'सुन रहा हूँ'],
    slow: 'इसमें समय लगा, फिर से पूछोगे?', error: 'कुछ गड़बड़ हो गई, फिर से बोलोगे?',
    unclear: 'हम्म, ठीक से समझ नहीं आया, फिर से बोलो?', noKey: 'बात करने के लिए मुझे तुम्हारी अपनी API कुंजी चाहिए। मुझ पर राइट-क्लिक करो और AI वाला हिस्सा खोलो।',
  },
  ur: {
    prompt: 'Urdu', voice: 'ur_PK-fasih-medium', voicePath: 'ur/ur_PK/fasih/medium/',
    wake: ['جی؟', 'بولو', 'کیا ہوا؟', 'سن رہا ہوں'],
    slow: 'اس میں وقت لگا، دوبارہ پوچھو گے؟', error: 'کچھ مسئلہ ہو گیا، دوبارہ کہو گے؟',
    unclear: 'ہمم، ٹھیک سے سمجھ نہیں آیا، دوبارہ کہو؟', noKey: 'بات کرنے کے لیے مجھے تمہاری اپنی API کلید چاہیے۔ مجھ پر رائٹ کلک کرو اور AI والا حصہ کھولو۔',
  },
  id: {
    prompt: 'Bahasa Indonesia', voice: 'id_ID-news_tts-medium', voicePath: 'id/id_ID/news_tts/medium/',
    wake: ['Ya?', 'Aku dengar', 'Ada apa?', 'Silakan'],
    slow: 'Itu agak lama, bisa tanya lagi?', error: 'Ada masalah, bisa ulangi?',
    unclear: 'Hmm, aku kurang paham, bisa ulangi?', noKey: 'Aku butuh kunci API milikmu untuk bicara. Klik kanan aku lalu buka bagian AI.',
  },
};

// Eski ayar "Turkce" gibi isim tutuyordu; artik iki harfli kod
function langCode(cfg) {
  const raw = String((cfg && cfg.language) || 'tr').toLowerCase();
  if (LANGS[raw]) return raw;
  if (raw.startsWith('tur')) return 'tr';
  const two = raw.slice(0, 2);
  return LANGS[two] ? two : 'tr';
}

function lang(cfg) {
  return LANGS[langCode(cfg)];
}

const downloads = new Map();

async function downloadFile(url, target) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
  const tmp = `${target}.part`;
  fs.writeFileSync(tmp, Buffer.from(await res.arrayBuffer()));
  fs.renameSync(tmp, target);
}

// Dilin Piper sesi: varsa yolu, yoksa indirmeyi baslatip null (o arada sessiz)
function voiceFor(cfg, voicesDir) {
  const L = lang(cfg);
  const dir = path.join(voicesDir, L.voice);
  const onnx = path.join(dir, `${L.voice}.onnx`);
  if (fs.existsSync(onnx) && fs.existsSync(`${onnx}.json`)) return onnx;
  if (!downloads.has(L.voice)) {
    const url = L.voiceUrl || `${VOICE_BASE}${L.voicePath}${L.voice}.onnx`;
    console.log(`[kevin] ses indiriliyor: ${L.voice}`);
    const job = (async () => {
      fs.mkdirSync(dir, { recursive: true });
      await downloadFile(`${url}.json`, `${onnx}.json`);
      await downloadFile(url, onnx);
      console.log(`[kevin] ses hazir: ${L.voice}`);
    })().catch((err) => console.error('[kevin] ses indirilemedi:', err.message))
      .finally(() => downloads.delete(L.voice));
    downloads.set(L.voice, job);
  }
  return null;
}

module.exports = { LANGS, langCode, lang, voiceFor };
