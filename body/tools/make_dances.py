#!/usr/bin/env python3
"""Kevin'in kendi dans emote'larini (Emotecraft .json) uretir.

Her dans vurusa gore yazildi: 1 vurus = BEAT tick (20 tick/sn'de 120 BPM).
Govde sarkinin temposunu olcup oynatma hizini ayarliyor, yani buradaki
anahtar kareler vurusun ustune dusuyor. Cikti: body/emotes/kevin_*.json (CC0).

Eksen yonleri (mevcut emote'lardan): sag kol roll +1.57 = yana acik (T-poz),
sol kol tersi; kol pitch -2.8 = yukarida; bacak pitch - = one; kafa pitch + =
asagi; govde ("torso") y + = yukari, blok cinsinden.

Kullanim: python3 body/tools/make_dances.py
"""
import json
import math
from pathlib import Path

BEAT = 10
OUT = Path(__file__).resolve().parent.parent / "emotes"

# Dinlenme pozu (konumlar Minecraft oyuncu modelinden, emote'larla ayni)
REST = {
    "torso": {"x": 0.0, "y": 0.0, "z": 0.0, "pitch": 0.0, "yaw": 0.0, "roll": 0.0},
    "head": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
    "rightArm": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
    "leftArm": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
    "rightLeg": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
    "leftLeg": {"pitch": 0.0, "yaw": 0.0, "roll": 0.0},
}


def pose(**parts):
    """pose(rightArm=dict(roll=1.2), torso=dict(y=-0.1)) -> tam poz"""
    p = {k: dict(v) for k, v in REST.items()}
    for part, axes in parts.items():
        p[part].update(axes)
    return p


def mirror(p):
    """Sag/sol ayna: kol ve bacaklar yer degistirir, yan eksenler ters"""
    swap = {"rightArm": "leftArm", "leftArm": "rightArm", "rightLeg": "leftLeg", "leftLeg": "rightLeg"}
    out = {}
    for part, axes in p.items():
        q = dict(axes)
        for a in ("yaw", "roll", "x"):
            if a in q:
                q[a] = -q[a]
        out[swap.get(part, part)] = q
    return out


def write(name, title, keys, easing="EASEINOUTSINE"):
    """keys: [(vurus, poz)]; son poz ilk pozla ayni olmali (dongu)"""
    length = int(round(keys[-1][0] * BEAT))
    moves = []
    for beat, p in keys:
        tick = int(round(beat * BEAT))
        for part, axes in p.items():
            moves.append({"tick": tick, "easing": easing, "turn": 0, part: {a: round(v, 4) for a, v in axes.items()}})
    data = {
        "name": title,
        "author": "Kevin (Liviciana)",
        "description": f"{BEAT} tick = 1 vurus; govde tempoya gore hizlandirir",
        "emote": {
            "isLoop": "true",
            "beginTick": 0,
            "endTick": length,
            "stopTick": length + 1,
            "returnTick": 1,
            "degrees": False,
            "moves": moves,
        },
    }
    (OUT / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
    print(f"{name}: {length} tick, {len(moves)} hareket")


def bounce():
    # Sakin: her vurusta dizler kirilir gibi asagi, kafa vurusa sallanir
    down = pose(torso=dict(y=-0.07, roll=0.03), head=dict(pitch=0.22),
                rightArm=dict(pitch=-0.35, roll=0.12), leftArm=dict(pitch=0.25, roll=-0.12))
    up = pose(torso=dict(y=0.0), head=dict(pitch=-0.05), rightArm=dict(roll=0.08), leftArm=dict(roll=-0.08))
    keys = []
    for b in range(8):
        d = down if b % 2 == 0 else mirror(down)
        keys += [(b, d), (b + 0.5, up)]
    keys.append((8, down))
    write("kevin_bounce", "Tempoya kafa sallama", keys)


def sway():
    # Sakin: iki vurus saga, iki vurus sola; kollar havada yavas yavas
    right = pose(torso=dict(x=0.14, roll=-0.09), head=dict(roll=-0.12, pitch=0.05),
                 rightArm=dict(roll=2.55, pitch=-0.2), leftArm=dict(roll=-2.85, pitch=-0.2),
                 rightLeg=dict(roll=0.08), leftLeg=dict(roll=0.08))
    left = mirror(right)
    keys = [(0, right), (2, left), (4, right), (6, left), (8, right)]
    write("kevin_sway", "Saga sola sallanma", keys)


def disco():
    # Orta: Saturday Night Fever - sag kol yana-yukari capraz, sonra asagi
    # karsi kalcaya; sol el belde, kalca vurusa gore. (Kollar yana acma
    # ekseniyle kalkiyor: one kaldirip yana cevirince kol yuzun onune dusuyordu.)
    up = pose(torso=dict(x=0.06, roll=-0.07), head=dict(yaw=-0.3, roll=-0.1),
              rightArm=dict(roll=2.45, pitch=-0.25),
              leftArm=dict(pitch=-0.2, roll=-0.55, yaw=0.6),
              rightLeg=dict(roll=0.1), leftLeg=dict(pitch=-0.15, roll=-0.05))
    down = pose(torso=dict(x=-0.06, roll=0.07), head=dict(yaw=0.2, pitch=0.2),
                rightArm=dict(roll=-0.45, pitch=-0.35),
                leftArm=dict(pitch=-0.2, roll=-0.55, yaw=0.6),
                rightLeg=dict(pitch=-0.15), leftLeg=dict(roll=-0.1))
    keys = []
    for b in range(0, 8, 2):
        a, c = (up, down) if b < 4 else (mirror(up), mirror(down))
        keys += [(b, a), (b + 1, c)]
    keys.append((8, up))
    write("kevin_disco", "Disko", keys)


def robot():
    # Orta: kollar dirsek yok ama sert, kare kare; her vurusta ani gecis
    frames = [
        pose(rightArm=dict(pitch=-1.57), leftArm=dict(pitch=0.0), head=dict(yaw=0.0)),
        pose(rightArm=dict(pitch=-1.57, yaw=0.6), leftArm=dict(pitch=-1.57), head=dict(yaw=0.5)),
        pose(rightArm=dict(pitch=0.0), leftArm=dict(pitch=-1.57, yaw=-0.6), head=dict(yaw=0.5), torso=dict(yaw=0.3)),
        pose(rightArm=dict(pitch=-3.0), leftArm=dict(pitch=-1.57), head=dict(yaw=0.0, pitch=-0.2), torso=dict(yaw=0.0)),
        pose(rightArm=dict(pitch=-1.57), leftArm=dict(pitch=-3.0), head=dict(yaw=-0.5), torso=dict(yaw=-0.3)),
        pose(rightArm=dict(roll=1.57), leftArm=dict(roll=-1.57), head=dict(yaw=-0.5)),
        pose(rightArm=dict(roll=1.57, pitch=-0.8), leftArm=dict(roll=-1.57, pitch=0.8), head=dict(roll=0.25)),
        pose(rightArm=dict(roll=1.57, pitch=0.8), leftArm=dict(roll=-1.57, pitch=-0.8), head=dict(roll=-0.25)),
    ]
    keys = []
    for b, f in enumerate(frames):
        # Vurusun basinda hizla yerine oturur, sonra donar
        keys += [(b, f), (b + 0.7, f)]
    keys.append((8, frames[0]))
    write("kevin_robot", "Robot", keys, easing="EASEOUTQUAD")


def clap():
    # Hareketli: eller basin ustunde vurusta birlesir, arada V acilir; ufak sicrama
    hit = pose(torso=dict(y=0.12), head=dict(pitch=-0.25),
               rightArm=dict(roll=3.0), leftArm=dict(roll=-3.0))
    open_ = pose(torso=dict(y=0.0), head=dict(pitch=-0.1),
                 rightArm=dict(roll=2.35), leftArm=dict(roll=-2.35))
    keys = []
    for b in range(8):
        keys += [(b, hit), (b + 0.5, open_)]
    keys.append((8, hit))
    write("kevin_clap", "Alkis", keys, easing="EASEOUTQUAD")


def running_man():
    # Hareketli: bacaklar sirayla one-arkaya, kollar tersine
    a = pose(torso=dict(y=-0.05, pitch=0.08), head=dict(pitch=0.12),
             rightLeg=dict(pitch=-0.7), leftLeg=dict(pitch=0.35),
             rightArm=dict(pitch=0.6, roll=0.1), leftArm=dict(pitch=-0.9, roll=-0.1))
    mid = pose(torso=dict(y=0.05), head=dict(pitch=0.0))
    b = mirror(a)
    # Onden bakinca bacaklarin one-arkaya gidisi gorunmuyordu: govde capraz
    for p in (a, b, mid):
        p["torso"]["yaw"] = 0.55
        p["head"]["yaw"] = -0.3
    keys = []
    for i in range(8):
        keys += [(i, a if i % 2 == 0 else b), (i + 0.5, mid)]
    keys.append((8, a))
    write("kevin_runningman", "Running man", keys)


def headbang():
    # Hareketli (rock): kafa vurusa asagi, govde one; sag el "boynuz" havada
    down = pose(head=dict(pitch=0.6), torso=dict(pitch=0.18, y=-0.05),
                rightArm=dict(roll=2.75), leftArm=dict(pitch=-0.5, roll=-0.2),
                rightLeg=dict(roll=0.18), leftLeg=dict(roll=-0.18))
    up = pose(head=dict(pitch=-0.25), torso=dict(pitch=0.02),
              rightArm=dict(roll=2.55), leftArm=dict(pitch=-0.3, roll=-0.2),
              rightLeg=dict(roll=0.18), leftLeg=dict(roll=-0.18))
    keys = []
    for b in range(8):
        d, u = (down, up) if b < 4 else (mirror(down), mirror(up))
        keys += [(b, d), (b + 0.5, u)]
    keys.append((8, down))
    write("kevin_headbang", "Headbang", keys, easing="EASEOUTQUAD")


def wave_arms():
    # Konserdeki gibi iki kol havada, bir vurus saga bir vurus sola
    left = pose(torso=dict(roll=0.06, x=-0.05), head=dict(roll=0.1, pitch=-0.15),
                rightArm=dict(pitch=-0.3, roll=2.35), leftArm=dict(pitch=-0.3, roll=-2.95))
    right = mirror(left)
    keys = [(b, left if b % 2 == 0 else right) for b in range(8)] + [(8, left)]
    write("kevin_wave_arms", "Kollar havada", keys)


if __name__ == "__main__":
    for make in (bounce, sway, disco, robot, clap, running_man, headbang, wave_arms):
        make()
