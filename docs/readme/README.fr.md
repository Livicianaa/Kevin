# Kevin

[Türkçe](../../README.md) · [English](README.en.md) · [Español](README.es.md) · **Français** · [Deutsch](README.de.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md) · [اردو](README.ur.md) · [Bahasa Indonesia](README.id.md)

Un ami IA qui vit sur ton bureau, parle, apprend à te connaître et sait utiliser ton ordinateur.
Un personnage 3D façon Minecraft : il se promène sur l'écran, s'assoit adossé au bord, et tu peux
l'attraper et le lancer. Dis son nom : il se tourne vers toi et parle à voix haute.

<p align="center"><img src="../gorseller/menu.png" width="520" alt="Kevin"></p>

## Télécharger

Depuis la [dernière version](https://github.com/Livicianaa/Kevin/releases/latest) :

| Système | Fichier | Comment l'ouvrir |
|---|---|---|
| Windows 10/11 | `Kevin-Kurulum.exe` | Lance l'installateur. Un raccourci Kevin apparaît sur le bureau. |
| Windows (sans installation) | `Kevin-Windows.zip` | Extrais dans un dossier, double-clique sur `Kevin\Kevin.exe`. |
| Linux | `Kevin-x86_64.AppImage` | Clic droit > Propriétés > rendre exécutable, puis double-clic. Terminal : `chmod +x Kevin-x86_64.AppImage && ./Kevin-x86_64.AppImage` |

Si Windows affiche « Windows a protégé votre ordinateur », choisis « Informations complémentaires » > « Exécuter quand même ».
Au premier lancement Kevin se prépare quelques secondes (écran d'accueil), puis tombe sur ton bureau.

## Première configuration : clé IA

Kevin a besoin d'un service d'IA pour parler. Chacun utilise sa propre clé ; elle reste sur ton ordinateur.

1. Au premier lancement Kevin ouvre ses réglages tout seul (ensuite : **clic droit** sur le personnage > **IA**).
2. Choisis un fournisseur et clique **Obtenir une clé**. Clé gratuite chez Groq : [console.groq.com/keys](https://console.groq.com/keys)
3. Colle la clé. La liste des modèles se charge seule ; si la clé est bonne, « Connecté » s'affiche.
4. **Enregistrer**.

Pour l'utiliser sans internet, choisis **Local (Ollama)** : installe [Ollama](https://ollama.com/download) et
télécharge un modèle (`ollama pull qwen3:8b`).

## À essayer

- Dis **« Kevin »** (ou clic molette sur lui), puis parle : « quel temps fait-il ? », « mets du lo-fi sur YouTube »,
  « regarde mon écran, c'est quoi ? »
- **Parle-lui de toi :** « je m'appelle Ali, je bois mon café sans sucre ». Il s'en souvient ; corrige-le, il apprend.
  Tu vois et effaces ce qu'il sait dans la page Discussion du menu.
- **Demande du code :** « écris un lanceur de dés en Python ». Il ne le lit pas à voix haute ; il le tape lettre par
  lettre dans sa fenêtre.
- **Caméra** (si activée) : « regarde-moi », « c'est moi, souviens-toi », « qu'est-ce que je tiens ? »
- **Musique :** lance une chanson, il danse (pas pendant les vidéos). En parlant, il bouge selon son humeur.
- **Physique :** attrape, glisse, lance ; tire doucement un bras, il trébuche. Il se relève seul.
- **Menu (clic droit) :** ajouter des skins (skin Minecraft 64x64, `+`), taille, langue, comportement. Échap ferme.
- **11 langues :** Türkçe, English, Español, Français, Deutsch, Português, Русский, العربية, हिन्दी, اردو,
  Bahasa Indonesia. La voix d'une langue est téléchargée la première fois (~60 Mo).

## Configuration requise

- Linux 64 bits ou Windows 10/11, micro, haut-parleurs
- 8 Go de RAM conseillés. Kevin mesure ton ordinateur à chaque démarrage ; sur une machine modeste il bouge
  moins et tourne à moins d'images par seconde.
- Internet pour l'IA (ou Ollama en local)

## Limites connues

- **Windows :** danser sur la musique, contrôler l'écran et la caméra ne marchent pour l'instant que sous Linux.
  Discussion, voix, menu, skins et physique marchent aussi sous Windows.
- **Linux :** surtout testé sous Hyprland. Sur d'autres bureaux, la transparence et « toujours au-dessus » peuvent varier.
- Fresh Animations n'est pas inclus (sa licence interdit la redistribution) ; Kevin marche avec des animations
  intégrées. Si tu l'as, mets `player.jem` dans le dossier `bin/cem/` de l'application.

## Où sont les réglages et les données ?

| | Linux | Windows |
|---|---|---|
| Réglages, clé, mémoire, historique, skins | `~/.config/kevin-pc-version/` | `%APPDATA%\kevin-pc-version\` |

Supprime ce dossier pour réinitialiser Kevin.

## Depuis les sources (développeurs)

Kevin a deux parties : le **corps** (`body/`, Godot 4.7 + physique Jolt) et le **cerveau** (Electron : voix,
discussion, outils). Le corps lance le cerveau tout seul.

```bash
npm install
npm run build:skin
body/run.sh
```

`bin/` (voix Piper, reconnaissance whisper.cpp et leurs modèles) n'est pas dans git à cause de sa taille ;
la liste est dans le [README turc](../../README.md). Paquets : `scripts/paketle.sh [linux|windows|hepsi]`.

## Merci

Emotecraft emotes (CC0), Quaternius Universal Animation Library 2 (CC0), Piper (MIT), whisper.cpp (MIT),
Godot (MIT), Electron (MIT), Anton (OFL), Noto.

---

Created by Liviciana · Codemisk
