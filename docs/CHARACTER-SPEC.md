# Kevin - Karakter Animasyon Spec

Bu dosya sanat/animasyon uretimi icin referans. Stil henuz karara baglanmadi (pixel art / chibi-anime / vektor-flat) - ilk asamada stil secilip birkaç ornek uretildikten sonra bu dosya guncellenecek.

## Teknik gereksinimler

- **Format:** PNG, seffaf arka plan (alpha kanali sart)
- **Boyut:** referans 128x128px karakter alani (v1 iskeletinde placeholder 64x64 kullanildi, gercek boyut buyutulebilir)
- **Katman ayrimi:** govde (aktivite) ve yuz ifadesi (duygu) AYRI dosyalar/katmanlar olmali, birlesik degil. Render sirasinda yuz, govde uzerine bindirilecek.
- **Sprite sheet ya da ayri dosyalar:** her aktivite icin kisa bir dongu (2-6 frame) yeterli, tam bir yuruyus animasyonu gibi dusunulmesine gerek yok - hafif/loop'lanabilir hareket yeterli.

## Govde / Aktivite durumlari (v1)

| Durum | Aciklama | Tahmini frame |
|---|---|---|
| idle | Bosta durma, hafif nefes/durus hareketi | 2-4 |
| walk | Yurume dongusu (tek yon, kod tarafinda aynalanir) | 4-6 |
| talk | Konusurken govde/agiz hareketi | 2-4 |
| listen | Mikrofon acikken dikkat kesilmis poz | 1-2 |
| sleep | Gozler kapali, "Z" efekti ayri eklenebilir | 1-2 |
| wake | Uyanma/cagrilma gecis animasyonu (kisa, dongu degil) | 2-3 |
| held | Mouse ile tutulup surukleniyor (sarkma pozu) | 1-2 |

## Yuz ifadesi / Duygu durumlari (v1)

| Durum | Ne zaman kullanilir |
|---|---|
| notr | Varsayilan |
| mutlu | Iyi haber, basarili yanit, kullanici olumlu tepki verince |
| uzgun | Hata, kotu haber, basarisiz istek |
| saskin | Beklenmedik girdi/olay |
| meraklı | Vision ("bak" komutu) kullanilirken |

> Kizgin, utanmis vb. ek duygular v2'ye birakildi - once temel 5 duygu + LLM tetikleme mantigi oturmali.

## v2 (sonraya birakilan) mikro-etkilesimler

- El sallama (selam/veda)
- Isaret etme / gosterme
- Uzun yalnizlik sonrasi mouse'u sallama
- Alkislama

## Notlar

- Renk paleti ve genel stil henuz secilmedi.
- Idle durumunda karakter ekranda rastgele geziniyor (bkz. `renderer/character.js`) - walk animasyonu bu hareketle senkron oynatilacak.
