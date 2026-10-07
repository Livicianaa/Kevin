# Kevin

[Türkçe](../../README.md) · **English** · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md) · [اردو](README.ur.md) · [Bahasa Indonesia](README.id.md)

An AI friend who lives on your desktop, talks, gets to know you and can use your computer.
A 3D Minecraft-style character: he walks around your screen, sits leaning on the edge, and you can
grab and throw him. Say his name and he turns to you and talks out loud.

<p align="center"><img src="../gorseller/menu.png" width="520" alt="Kevin"></p>

## Download

From the [latest release](https://github.com/Livicianaa/Kevin/releases/latest):

| System | File | How to open |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Run the installer. A Kevin shortcut appears on the desktop. |
| Windows (no install) | `Kevin-Windows.zip` | Extract to a folder, double-click `Kevin\Kevin.exe`. |
| Linux | `Kevin-x86_64.AppImage` | Right-click > Properties > mark as executable, then double-click. Terminal: `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

If Windows says "Windows protected your PC", choose "More info" > "Run anyway".
On first start Kevin gets ready for a few seconds (intro screen), then drops onto your desktop.

## First setup: AI key

Kevin needs an AI service to talk. Everyone uses their own key; it is stored only on your computer.

1. On first start Kevin opens his settings by himself (later: **right-click** the character > **AI**).
2. Pick a provider and click **Get key**. Free key on Groq: [console.groq.com/keys](https://console.groq.com/keys)
3. Paste the key. The model list loads by itself; if the key is right it says "Connected".
4. **Save**.

To use him without internet choose **Local (Ollama)**: install [Ollama](https://ollama.com/download) and pull a
model (`ollama pull qwen3:8b`).

## Things to try

- Say **"Kevin"** (or middle-click him), then talk: "what's the weather?", "play lo-fi on YouTube",
  "look at my screen, what is this?"
- **Tell him about yourself:** "my name is Ali, I drink coffee without sugar". He remembers; correct him and he
  learns. See and delete what he knows on the Chat page of the menu.
- **Ask for code:** "write a Python dice roller". He does not read it aloud; he types it letter by letter in his own window.
- **Camera** (if enabled in settings): "look at me", "this is me, remember me", "what am I holding?"
- **Music:** play a song and he dances (not while you watch videos). While talking he moves with his mood.
- **Physics:** grab, drag, throw; pull an arm slowly and he stumbles. He gets up after a fall.
- **Menu (right-click):** add skins (64x64 Minecraft skin, `+`), size, language, behaviour. Esc closes it.
- **11 languages:** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. The voice for a language is downloaded the first time (~60 MB).

## Requirements

- 64-bit Linux or Windows 10/11, microphone, speakers
- 8 GB RAM recommended. Kevin measures your computer at every start; on weaker machines he moves less
  and runs at a lower frame rate.
- Internet for the AI (or Ollama locally)

## Known limits

- **Windows:** dancing to music, screen control and the camera only work on Linux for now. Chat, voice,
  menu, skins and physics work on Windows too.
- **Linux:** mostly tested on Hyprland. On other desktops window transparency and "always on top" may vary.
- Fresh Animations is not included (its license does not allow redistribution); Kevin walks with built-in
  animations. If you own it, put `player.jem` into the app's `bin/cem/` folder.

## Where are settings and data?

| | Linux | Windows |
|---|---|---|
| Settings, key, memory, chat history, skins | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Delete this folder to reset Kevin.

## Running from source (developers)

Kevin has two parts: the **body** (`body/`, Godot 4.7 + Jolt physics) and the **brain** (Electron: voice,
chat, tools). The body starts the brain by itself.

```bash
npm install
npm run build:skin
body/run.sh
```

`bin/` (Piper voice, whisper.cpp speech recognition and their models) is not in git because of its size; see the
[Turkish README](../../README.md) for the file list. Build packages with `scripts/paketle.sh [linux|windows|hepsi]`.

## Thanks

Emotecraft emotes (CC0), Quaternius Universal Animation Library 2 (CC0), Piper (MIT), whisper.cpp (MIT),
Godot (MIT), Electron (MIT), Anton (OFL), Noto.

---

Created by Liviciana · Codemisk
