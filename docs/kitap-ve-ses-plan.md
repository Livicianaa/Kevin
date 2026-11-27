# Kitap okuma + özel ses modeli (plan)

## Kullanıcı deneyimi

- Dosya Kevin'in üstüne sürüklenir (Godot penceresi `files_dropped`).
- Okunacak dosya ise (.pdf .md .markdown .txt .epub .cbz .zip, resimler .png .jpg .jpeg .webp, resim klasörü):
  Kevin arkasından kitap çıkarır, açar, sesli okumaya başlar.
  - Metin: sayfa sayfa, cümle gruplarıyla sesli okur.
  - Manga/çizgi roman (cbz, zip, resim, metni olmayan PDF): her sayfayı görüntü modeline gösterir,
    balonları okuyup kısa yorum yapar, sonra sayfayı çevirir.
  - Kaldığı yer kitap başına kaydedilir; aynı dosya tekrar bırakılınca oradan devam eder.
  - Kevin'e tıklamak ya da adını söylemek okumayı duraklatır. "devam et", "okumaya devam" sürdürür.
    "kitabı kapat", "okumayı bırak" kapatır. Sağ tık menüsünde de "Okumaya devam" / "Kitabı kapat" var.
- Ses modeli dosyası ise (.pth, .index, .onnx + .onnx.json): Kevin sesi kurar ve yeni sesiyle "Yeni sesim nasıl?" der.

## Beyin ↔ gövde mesajları (TCP JSON satırı, body/brain.gd ↔ main.js)

Gövde → beyin (renderer'a `body-command` olarak gelir):
- `{"type":"drop","files":["/mutlak/yol", ...]}`
- `{"type":"book_cmd","cmd":"pause"|"resume"|"close"}`
- `{"type":"voices_get"}`
- `{"type":"voice_set","id":"<id veya 'default'>"}`
- `{"type":"voice_pitch","id":"<id>","pitch":<-12..12 tam sayı, null=otomatik>}`
- `{"type":"voice_test"}`
- `{"type":"voice_remove","id":"<id>"}`
- `{"type":"rvc_install"}`

Beyin → gövde (`bodySend`):
- `{"type":"book","state":"open","kind":"text"|"images","title":"...","page":0,"total":N}`
- `{"type":"book","state":"page","page":i,"total":N}`
- `{"type":"book","state":"pause"}` / `{"state":"resume"}` / `{"state":"close"}`
- `{"type":"book","state":"error","text":"..."}`
- `{"type":"voices","list":[{"id","name","type":"piper"|"rvc","pitch"}],"active":"<id|default>","rvc":{"ready":bool,"installing":bool,"progress":0..1,"text":"..."}}`

## Ses modeli

- Kullanıcı sesleri: `userData/voices/<id>/` + `meta.json` `{id,name,type,model,index,config,pitch}`.
- Piper: `.onnx` + `.onnx.json` doğrudan Piper'a verilir.
- RVC: Kevin dilin varsayılan Piper sesiyle konuşur, wav kalıcı Python sürecinde (`rvc/kevin_rvc.py`,
  Applio `VoiceConverter`) modele çevrilir. `pitch` null ise Applio `proposed_pitch` otomatik perde kullanılır.
- RVC çalışma ortamı sırası: `cfg.rvcApplio` → `KEVIN_RVC_APPLIO` → `userData/rvc/Applio` (eklenti).
  Eklenti yoksa ayarlardan "RVC eklentisini kur" (uv + Python 3.12 + Applio + torch) indirir.
- RVC hata verirse Kevin sessiz kalmaz, düz Piper sesiyle konuşur.
