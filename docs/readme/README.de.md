# Kevin

[Türkçe](../../README.md) · [English](README.en.md) · [Español](README.es.md) · [Français](README.fr.md) · **Deutsch** · [Português](README.pt.md) · [Русский](README.ru.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md) · [اردو](README.ur.md) · [Bahasa Indonesia](README.id.md)

Ein KI-Freund, der auf deinem Desktop lebt, spricht, dich kennenlernt und deinen Computer bedienen kann.
Eine 3D-Figur im Minecraft-Stil: Er läuft über den Bildschirm, setzt sich an den Rand gelehnt hin, und du
kannst ihn packen und werfen. Sag seinen Namen, dann dreht er sich zu dir und spricht laut.

<p align="center"><img src="../gorseller/menu.png" width="520" alt="Kevin"></p>

## Herunterladen

Aus der [neuesten Version](https://github.com/Livicianaa/Kevin/releases/latest):

| System | Datei | So öffnest du sie |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Installer starten. Auf dem Desktop erscheint eine Kevin-Verknüpfung. |
| Windows (ohne Installation) | `Kevin-Windows.zip` | In einen Ordner entpacken, `Kevin\Kevin.exe` doppelklicken. |
| Linux | `Kevin-x86_64.AppImage` | Rechtsklick > Eigenschaften > als ausführbar markieren, dann doppelklicken. Terminal: `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

Wenn Windows „Der Computer wurde durch Windows geschützt“ meldet: „Weitere Informationen“ > „Trotzdem ausführen“.
Beim ersten Start bereitet sich Kevin ein paar Sekunden vor (Startbild) und fällt dann auf deinen Desktop.

## Erste Einrichtung: KI-Schlüssel

Kevin braucht einen KI-Dienst, um zu sprechen. Jeder nutzt seinen eigenen Schlüssel; er bleibt nur auf deinem Rechner.

1. Beim ersten Start öffnet Kevin seine Einstellungen selbst (später: **Rechtsklick** auf die Figur > **KI**).
2. Anbieter wählen und **Schlüssel holen** klicken. Kostenloser Schlüssel bei Groq: [console.groq.com/keys](https://console.groq.com/keys)
3. Schlüssel einfügen. Die Modellliste lädt automatisch; stimmt der Schlüssel, steht dort „Verbunden“.
4. **Speichern**.

Ohne Internet: **Lokal (Ollama)** wählen, [Ollama](https://ollama.com/download) installieren und ein Modell laden
(`ollama pull qwen3:8b`).

## Zum Ausprobieren

- Sag **„Kevin“** (oder Mittelklick auf ihn) und sprich: „Wie ist das Wetter?“, „Spiel Lo-Fi auf YouTube“,
  „Schau auf meinen Bildschirm, was ist das?“
- **Erzähl von dir:** „Ich heiße Ali, ich trinke Kaffee ohne Zucker“. Er merkt es sich; korrigiere ihn, er lernt.
  Auf der Chat-Seite im Menü siehst und löschst du, was er weiß.
- **Code schreiben lassen:** „Schreib einen Würfel in Python“. Er liest ihn nicht vor, sondern tippt ihn Buchstabe für
  Buchstabe in seinem Fenster.
- **Kamera** (wenn eingeschaltet): „Schau mich an“, „Das bin ich, merk dir mich“, „Was halte ich?“
- **Musik:** Spiel ein Lied, dann tanzt er (nicht bei Videos). Beim Reden bewegt er sich nach seiner Stimmung.
- **Physik:** packen, ziehen, werfen; zieh langsam am Arm, er stolpert. Nach einem Sturz steht er auf.
- **Menü (Rechtsklick):** Skins hinzufügen (64x64-Minecraft-Skin, `+`), Größe, Sprache, Verhalten. Esc schließt.
- **11 Sprachen:** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. Die Stimme einer Sprache wird beim ersten Mal geladen (~60 MB).

## Voraussetzungen

- 64-Bit-Linux oder Windows 10/11, Mikrofon, Lautsprecher
- 8 GB RAM empfohlen. Kevin misst deinen Rechner bei jedem Start; auf schwächeren Rechnern bewegt er sich
  weniger und läuft mit weniger Bildern pro Sekunde.
- Internet für die KI (oder Ollama lokal)

## Bekannte Grenzen

- **Windows:** Tanzen zur Musik, Bildschirmsteuerung und Kamera gibt es vorerst nur unter Linux. Chat, Stimme,
  Menü, Skins und Physik funktionieren auch unter Windows.
- **Linux:** vor allem unter Hyprland getestet. Auf anderen Desktops können Transparenz und „immer im Vordergrund“ abweichen.
- Fresh Animations ist nicht enthalten (die Lizenz erlaubt keine Weitergabe); Kevin läuft mit eingebauten
  Animationen. Wenn du es besitzt, lege `player.jem` in den Ordner `bin/cem/` der App.

## Wo liegen Einstellungen und Daten?

| | Linux | Windows |
|---|---|---|
| Einstellungen, Schlüssel, Gedächtnis, Verlauf, Skins | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Lösche diesen Ordner, um Kevin zurückzusetzen.

## Aus dem Quellcode (Entwickler)

Kevin besteht aus zwei Teilen: dem **Körper** (`body/`, Godot 4.7 + Jolt-Physik) und dem **Gehirn** (Electron:
Stimme, Chat, Werkzeuge). Der Körper startet das Gehirn selbst.

```bash
npm install
npm run build:skin
body/run.sh
```

`bin/` (Piper-Stimme, whisper.cpp-Spracherkennung und Modelle) ist wegen der Größe nicht in git; die Liste steht
im [türkischen README](../../README.md). Pakete: `scripts/paketle.sh [linux|windows|hepsi]`.

## Danke

Emotecraft emotes (CC0), Quaternius Universal Animation Library 2 (CC0), Piper (MIT), whisper.cpp (MIT),
Godot (MIT), Electron (MIT), Anton (OFL), Noto.

---

Created by Liviciana · Codemisk
