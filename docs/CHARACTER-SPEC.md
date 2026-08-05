# Kevin - Karakter Animasyon Spec

Bu dosya sanat/animasyon uretimi icin referans. Stil henuz karara baglanmadi (pixel art / chibi-anime / vektor-flat) - ilk asamada stil secilip birkaç ornek uretildikten sonra bu dosya guncellenecek.

Tasarim komple bitirilip sonra kodlamaya gecilecek - fazlama yok, asagidaki liste tam kapsam.

## Teknik gereksinimler

- **Format:** PNG, seffaf arka plan (alpha kanali sart)

- **Boyut:** referans 128x128px karakter alani (v1 iskeletinde placeholder 64x64 kullanildi, gercek boyut buyutulebilir)

- **Katman ayrimi:** govde (aktivite) ve yuz ifadesi (duygu) AYRI dosyalar/katmanlar olmali, birlesik degil. Render sirasinda yuz, govde uzerine bindirilecek. Bu sayede N aktivite x M duygu icin N+M asset yeterli olur, N\*M degil.

- **Sprite sheet ya da ayri dosyalar:** her aktivite icin kisa bir dongu (2-6 frame) yeterli.

## Govde / Aktivite durumlari (komple liste)

| Durum | Aciklama | Tahmini frame |
| - | - | - |
| idle | Bosta durma, hafif nefes/durus hareketi | 2-4 |
| idle-esneme | Esneme (idle varyasyonu) | 3-5 |
| idle-bakinma | Etrafa bakinma/merak (idle varyasyonu) | 3-4 |
| idle-oturma | Ekran kenarina oturup sallanma (idle varyasyonu) | 2-4 |
| idle-gerinme | Gerinme (idle varyasyonu) | 3-4 |
| idle-kasima | Kafa kasima (idle varyasyonu) | 2-3 |
| walk | Yurume dongusu (tek yon, kod tarafinda aynalanir) | 4-6 |
| talk | Konusurken govde/agiz hareketi | 2-4 |
| listen | Mikrofon acikken dikkat kesilmis poz | 1-2 |
| think | LLM cevap uretirken bekleme/dusunme poz | 2-3 |
| sleep | Gozler kapali, "Z" efekti ayri eklenebilir | 1-2 |
| wake | Uyanma/cagrilma gecis animasyonu (dongu degil, tek seferlik) | 2-3 |
| held | Mouse ile tutulup suruklenirken sarkma pozu | 1-2 |
| held-wheee | Suruklenirken keyifli tepki (held'in enerjik versiyonu) | 2-3 |
| jump | Cift tiklaninca zipla/heyecan tepkisi | 2-3 |
| tickle | Uzun basili tutunca saskin/gidiklanmis tepki | 2-3 |
| nod-yes | Onaylama - bas sallama | 2-3 |
| nod-no | Reddetme - bas sallama | 2-3 |
| dance | Rastgele dusuk ihtimalle tetiklenen kisa dans (easter egg) | 4-6 |
| night-sleepy | Gece gec saatte uykulu duruş, saat bazli (easter egg) | 2-3 |


## Yuz ifadesi / Duygu durumlari (komple liste)

| Durum | Ne zaman kullanilir |
| - | - |
| notr | Varsayilan |
| mutlu | Iyi haber, basarili yanit, kullanici olumlu tepki verince |
| uzgun | Hata, kotu haber, basarisiz istek |
| saskin | Beklenmedik girdi/olay |
| meraklı | Vision ("bak" komutu) kullanilirken |
| kizgin | Tetikleme mantigi kod tarafinda ayrica netlesecek (ne zaman kullanilacagi acik, art onceden hazirlanabilir) |


## v2 sonrasi / henuz eklenmeyen fikirler

- Isaret etme / gosterme (bir seye dikkat cekerken)

- Alkislama

- OS bildirimine tepki verme (ozel entegrasyon gerektirir)

## Notlar

- Renk paleti ve genel stil henuz secilmedi.

- Idle durumunda karakter ekranda rastgele geziniyor (bkz. `renderer/character.js`) - walk animasyonu bu hareketle senkron oynatilacak.

- Gel sohbet edelim tarzı birşey deyicne eleman otursun sohbet edelim onunla


