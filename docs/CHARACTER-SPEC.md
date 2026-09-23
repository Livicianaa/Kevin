# Kevin - Karakter Animasyon Spec

Karakter **3D Minecraft rig'i** (skinview3d + Three.js). 5 Agustos 2026'da alinan bu karar
onceki "2D sprite / pixel art" planini gecersiz kilar - PNG frame, sprite sheet ya da
govde+yuz katman ayrimi YOK. Yuz ifadesi skin dokusuna gomulu oldugu icin duygu, govde
duruslariyla ve (ileride) HUD rozetiyle anlatilir.

## Nasil calisiyor

- `renderer/animations.js` - her animasyon `(t, pose, duration)` alip bir **poz** dolduruyor:
  6 uzvun (`head`, `body`, `leftArm`, `rightArm`, `leftLeg`, `rightLeg`) rotasyonu + `rootY`.
- `KevinAnimator` (ayni dosya) poz uretir, durum degisiminde iki pozu **0.25 sn boyunca
  harmanlar** (sert gecis yok), tek seferlik animasyonlari sureleri bitince onceki duruma dondurur.
- `renderer/skin-viewer-src.js` animatoru viewer'a baglar ve `window.KevinSkin` uzerinden
  `setState` / `play` / `setSitting` / `currentState` sunar. Kaynak degisince `npm run build:skin`.
- `renderer/character.js` hangi durumun ne zaman gectigine karar verir (asagidaki tablo).

Aci isaretleri: `+x` uzvu geriye, `-x` one dondurur; kollarda `+z` sol kolu, `-z` sag kolu
govdeden uzaklastirir. `rootY` Minecraft birimi (karakter boyu 32 birim).

## Durumlar

### Surekli (loop)

| Durum | Ne zaman | Nasil gorunuyor |
| - | - | - |
| idle | Varsayilan | Hafif nefes + kol salinimi; 9-22 sn'de bir rastgele idle varyasyonu oynar |
| walk | Henuz tetiklenmiyor (ekranda gezinme yok) | Klasik yurume dongusu, kafa sallanmasi |
| talk | TTS sesi calarken | Kafa/govde ritmi + kucuk kol jestleri |
| listen | VAD konusma algiladiginda | Kafa yana egik, dikkat kesilmis, sakin nefes |
| think | LLM cevabi beklenirken | Kafa one-yana egik, sag kol yuze dogru |
| sleep | 3 dk etkilesimsizlik | Kafa one dusmus, yavas nefes |
| night-sleepy | 00:00-06:00 arasi, bosta | Uykulu idle, periyodik kafa dusmesi |
| dance | Sistemde muzik calarken (MPRIS/playerctl) | Ritmik zipla + kol/kalca hareketi |
| held | Bagli degil (pencere suruklemesi yok) | Yercekimiyle kollar yukari, bacaklar sarkik |
| held-wheee | Bagli degil | held'in enerjik hali |

### Tek seferlik (oneShot, bitince onceki duruma doner)

| Durum | Sure | Ne zaman |
| - | - | - |
| wake | 1.6 sn | Uykudayken etkilesim olunca |
| jump | 0.75 sn | Karaktere cift tiklayinca |
| tickle | 1.8 sn | Karaktere 600 ms basili tutunca (panel acilmaz) |
| wave | 2.4 sn | Sohbet paneli acildiginda selam |
| nod-yes | 1.2 sn | Cevap "evet / tabii / olur / tamam..." ile basliyorsa |
| nod-no | 1.2 sn | Cevap "hayir / olmaz / maalesef..." ile basliyorsa |
| idle-bakinma / idle-gerinme / idle-esneme / idle-kasima | 2.4-3.5 sn | idle'dayken rastgele |

### Oturma

Ayri bir animasyon degil, **bacaklara uygulanan katman**: `setSitting(true)` bacaklari one
uzatir ve govdeyi 4 birim indirir, ustune hangi durum oynuyorsa o devam eder. Sohbet paneli
acikken acik, kapaninca 0.4 sn'de kalkar.

## Test modu

```bash
npm start -- --anim=dance        # tek bir durumu sabitler
npm start -- --anim=idle:sit     # ":sit" oturmus halde gosterir
```
Tek seferlik animasyonlar test modunda 2 sn'de bir tekrar oynar. Bu modda durum makinesi
devre disi - karakter baska hicbir sebeple durum degistirmez.

## Kamera

`skin-viewer-src.js`: `fov 30`, `zoom 0.68`, `playerWrapper.position.y = 1`. zoom buyurse
zipla (rootY +7) ust kenardan, oturma alt kenardan tasar.

## Muzik algilama

`main.js` -> `music-status` IPC, `playerctl metadata` ile `{{playerName}}|{{status}}|
{{xesam:artist}}|{{xesam:title}}`. Calan sey **bilinen bir muzik oynaticidan** geliyorsa ya da
**artist alani doluysa** sarki sayilir (Firefox'ta video izlerken dans etmesin diye).
Renderer 6 saniyede bir soruyor. **Sadece Linux** - Windows'ta ayri bir yol gerekecek.

## Yapilmayanlar

- `walk` kodlandi ama tetikleyicisi yok: karakter ekranda gezinmiyor (pencere kose-ankorlu).
- `held` / `held-wheee` kodlandi ama pencere suruklemesi olmadigi icin bagli degil.
- Isaret etme / gosterme, alkislama, OS bildirimine tepki - v2.
- "Kizgin" gibi duygu durumlari: 3D rig'de yuz degismedigi icin HUD rozet katmani gerekiyor.
