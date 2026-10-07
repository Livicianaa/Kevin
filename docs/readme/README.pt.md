# Kevin

[Türkçe](../../README.md) · [English](README.en.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Português** · [Русский](README.ru.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md) · [اردو](README.ur.md) · [Bahasa Indonesia](README.id.md)

Um amigo com IA que vive na sua área de trabalho, conversa, conhece você e consegue usar seu computador.
Um personagem 3D no estilo Minecraft: anda pela tela, senta encostado na borda e você pode pegá-lo e
jogá-lo. Diga o nome dele e ele se vira para você e fala em voz alta.

<p align="center"><img src="../gorseller/menu.png" width="520" alt="Kevin"></p>

## Baixar

Na [versão mais recente](https://github.com/Livicianaa/Kevin/releases/latest):

| Sistema | Arquivo | Como abrir |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Rode o instalador. Um atalho do Kevin aparece na área de trabalho. |
| Windows (sem instalar) | `Kevin-Windows.zip` | Extraia numa pasta e dê dois cliques em `Kevin\Kevin.exe`. |
| Linux | `Kevin-x86_64.AppImage` | Botão direito > Propriedades > marcar como executável, depois dois cliques. Terminal: `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

Se o Windows disser "O Windows protegeu o computador", escolha "Mais informações" > "Executar assim mesmo".
Na primeira vez o Kevin se prepara por alguns segundos (tela de abertura) e depois cai na sua área de trabalho.

## Primeira configuração: chave de IA

O Kevin precisa de um serviço de IA para falar. Cada um usa a própria chave; ela fica só no seu computador.

1. Na primeira vez o Kevin abre as configurações sozinho (depois: **botão direito** no personagem > **IA**).
2. Escolha um provedor e clique em **Pegar chave**. Chave grátis no Groq: [console.groq.com/keys](https://console.groq.com/keys)
3. Cole a chave. A lista de modelos carrega sozinha; se a chave estiver certa aparece "Conectado".
4. **Salvar**.

Para usar sem internet escolha **Local (Ollama)**: instale o [Ollama](https://ollama.com/download) e baixe um
modelo (`ollama pull qwen3:8b`).

## O que testar

- Diga **"Kevin"** (ou clique com o botão do meio nele) e fale: "como está o tempo?", "toca lo-fi no YouTube",
  "olha minha tela, o que é isso?"
- **Fale de você:** "meu nome é Ali, tomo café sem açúcar". Ele lembra; corrija e ele aprende. Na página Conversa do
  menu você vê e apaga o que ele sabe.
- **Peça código:** "escreve um dado em Python". Ele não lê em voz alta; digita letra por letra na janela dele.
- **Câmera** (se ligada nas configurações): "olha pra mim", "sou eu, lembra de mim", "o que estou segurando?"
- **Música:** toque uma música e ele dança (com vídeo não). Falando, ele se mexe conforme o humor.
- **Física:** pegue, arraste, jogue; puxe um braço devagar e ele tropeça. Depois da queda ele levanta.
- **Menu (botão direito):** adicionar skins (skin Minecraft 64x64, `+`), tamanho, idioma, comportamento. Esc fecha.
- **11 idiomas:** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. A voz de cada idioma é baixada na primeira vez (~60 MB).

## Requisitos

- Linux 64 bits ou Windows 10/11, microfone, alto-falantes
- 8 GB de RAM recomendados. O Kevin mede seu computador a cada início; em máquinas mais fracas ele se mexe menos
  e roda com menos quadros por segundo.
- Internet para a IA (ou Ollama local)

## Limites conhecidos

- **Windows:** dançar com música, controlar a tela e a câmera por enquanto só funcionam no Linux. Conversa, voz,
  menu, skins e física funcionam no Windows também.
- **Linux:** testado principalmente no Hyprland. Em outros ambientes a transparência e "sempre no topo" podem variar.
- Fresh Animations não vem incluído (a licença não permite redistribuir); o Kevin anda com animações próprias.
  Se você tem, coloque `player.jem` na pasta `bin/cem/` do aplicativo.

## Onde ficam configurações e dados?

| | Linux | Windows |
|---|---|---|
| Configurações, chave, memória, histórico, skins | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Apague essa pasta para zerar o Kevin.

## A partir do código (desenvolvedores)

O Kevin tem duas partes: o **corpo** (`body/`, Godot 4.7 + física Jolt) e o **cérebro** (Electron: voz, conversa,
ferramentas). O corpo inicia o cérebro sozinho.

```bash
npm install
npm run build:skin
body/run.sh
```

`bin/` (voz Piper, reconhecimento whisper.cpp e modelos) não está no git por causa do tamanho; a lista está no
[README em turco](../../README.md). Pacotes: `scripts/paketle.sh [linux|windows|hepsi]`.

## Agradecimentos

Emotecraft emotes (CC0), Quaternius Universal Animation Library 2 (CC0), Piper (MIT), whisper.cpp (MIT),
Godot (MIT), Electron (MIT), Anton (OFL), Noto.

---

Created by Liviciana · Codemisk
