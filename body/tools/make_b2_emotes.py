#!/usr/bin/env python3
"""Bolum 2 emote'lari: telasli kosu ve dizlerini kendine cekip oturma.
Eksen notu: torso pitch + = geriye; kol/bacak pitch - = one/yukari.

Kullanim: python3 body/tools/make_b2_emotes.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ual_to_emote as u  # noqa: E402

OUT = HERE.parent / "emotes"
CLIPS = HERE.parent / "anim" / "ual"


def yaz(ad, baslik, aciklama, moves, son, dongu_bas=0):
    d = {"name": baslik, "author": "Kevin (Liviciana)", "description": aciklama,
         "emote": {"isLoop": "true", "beginTick": 0, "endTick": son, "stopTick": son + 1,
                   "returnTick": dongu_bas, "degrees": False, "moves": moves}}
    (OUT / f"{ad}.json").write_text(json.dumps(d, indent=1) + "\n")


def kare(tick, parca, **deg):
    return {"tick": tick, "easing": "EASEINOUTSINE", "turn": 0, parca: deg}


def kosu():
    """Insan gibi telasli kosu: Quaternius UAL Sprint_Loop (CC0) hareket kaydi
    (elle yazilan kosu oyundaki gibi duruyordu). Kayittaki kol dirsekten
    bukuldugu icin Minecraft kolunda salinim kucuk kaliyordu: kol salinimi
    buyutulur, yana acilma azaltilir; kafa govdeye karsi doner, one bakar."""
    clip = u.load(CLIPS / "Sprint_Loop.json")
    rest = u.load(CLIPS / "Idle_Loop.json")["frames"][0]["pelvis"]
    ticks = u.convert(clip, rest_pelvis=rest)[:-1]
    for kol in ("rightArm", "leftArm"):
        ort = sum(t[kol]["pitch"] for t in ticks) / len(ticks)
        for t in ticks:
            t[kol]["pitch"] = ort * 0.6 + (t[kol]["pitch"] - ort) * 2.4
            t[kol]["roll"] *= 0.3
    # Dizler bukulu kayit: duz Minecraft bacaginda bacak geriye gitmiyor, yana
    # aciliyordu (put gibi). Salinim buyutulur, yana acilma kisilir, ziplama artar.
    for bacak in ("rightLeg", "leftLeg"):
        ort = sum(t[bacak]["pitch"] for t in ticks) / len(ticks)
        for t in ticks:
            # Arkaya fazla gidince topuk kalcaya degiyordu: sinirli
            t[bacak]["pitch"] = min(0.75, ort * 0.3 + (t[bacak]["pitch"] - ort) * 1.6)
            t[bacak]["roll"] *= 0.2
    for t in ticks:
        t["torso"]["y"] *= 2.5
        t["torso"]["roll"] = t["torso"].get("roll", 0.0) * 0.5
    for t in ticks:
        g = t["torso"]
        # Kafa one baksin: govde one egildikce kafa yukari (pitch + asagi bakar)
        t["head"] = {"pitch": g["pitch"] * 0.85, "yaw": -g["yaw"] * 0.6, "roll": -g.get("roll", 0.0) * 0.5}
    u.write(OUT / "b2_kos.json", "Telasli kos (UAL Sprint_Loop)", ticks, loop_from=0)


def kilic_at():
    """Kilici firlatma: UAL Sword_Attack (CC0) hamlesi; butun vucut gerilip
    savurur. Birakma ani: sag kolun en hizli one gittigi tick (cekim_b2.gd)"""
    clip = u.load(CLIPS / "Sword_Attack.json")
    rest = u.load(CLIPS / "Idle_Loop.json")["frames"][0]["pelvis"]
    ticks = u.convert(clip, rest_pelvis=rest, speed=1.15)
    for t in ticks:
        g = t["torso"]
        t["head"] = {"pitch": -g["pitch"] * 0.4, "yaw": -g["yaw"] * 0.5}
    hiz = [abs(ticks[i + 1]["rightArm"]["pitch"] - ticks[i]["rightArm"]["pitch"]) + abs(ticks[i + 1]["rightArm"]["roll"] - ticks[i]["rightArm"]["roll"]) for i in range(len(ticks) - 1)]
    birak = max(range(len(hiz)), key=lambda i: hiz[i])
    u.write(OUT / "b2_kilic_at.json", "Kilic firlat (UAL Sword_Attack)", ticks)
    (OUT / "b2_kilic_at.birak").write_text(str(birak + 1) + "\n")
    print("birakma tick", birak + 1, "/", len(ticks) - 1)


def kilic_cek():
    """Kalcadaki kilici cekme: gövde kalcaya doner, kafa egilip bakar, sag kol
    kalcadan yukari one kalkar (kilicin kendisine bakar), sonra alcakta tutar"""
    def poz(t, govde_yaw, govde_pitch, kafa_p, kafa_y, kol_p, kol_r, sol_p):
        return [kare(t, "torso", yaw=govde_yaw, pitch=govde_pitch),
                kare(t, "head", pitch=kafa_p, yaw=kafa_y),
                kare(t, "rightArm", pitch=kol_p, roll=kol_r),
                kare(t, "leftArm", pitch=sol_p, roll=-0.1)]
    m = []
    m += poz(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    m += poz(6, 0.35, -0.18, 0.45, 0.3, 0.3, 0.35, -0.2)     # kabzaya
    m += poz(9, 0.38, -0.2, 0.45, 0.3, 0.35, 0.38, -0.25)    # kavrar
    m += poz(15, -0.15, 0.05, -0.2, -0.1, -2.5, 0.25, 0.15)  # cekip kaldirir
    m += poz(18, -0.1, 0.0, -0.25, -0.1, -2.6, 0.2, 0.1)     # kilica bakar
    m += poz(24, 0.0, 0.0, 0.0, 0.0, -0.45, 0.2, 0.0)        # alcakta tutar
    m += poz(40, 0.0, 0.0, 0.0, 0.0, -0.45, 0.2, 0.0)
    yaz("b2_kilic_cek", "Kilic cek", "Kalcadaki kilici ceker (Bolum 2)", m, 40, dongu_bas=24)


def diz_otur():
    """Yere oturup dizlerini kendine ceker, kollari dizlerine sarili"""
    # Bacak x/y/z mutlak eklem noktasi (piksel, kalca y=12); sit.json gibi
    poz = [kare(10, "torso", y=-0.62, pitch=0.1),
           kare(10, "head", pitch=0.15),
           kare(10, "rightLeg", pitch=-2.25, x=-1.9, y=12.0, z=-0.6, roll=-0.06),
           kare(10, "leftLeg", pitch=-2.25, x=1.9, y=12.0, z=-0.6, roll=0.06),
           kare(10, "rightArm", pitch=-1.35, yaw=-0.5, roll=0.05, x=-5.0, y=2.0),
           kare(10, "leftArm", pitch=-1.35, yaw=0.5, roll=-0.05, x=5.0, y=2.0)]
    tut = [dict(k, tick=40) for k in poz]
    yaz("b2_diz_otur", "Dizlerini cekip otur", "Yere oturur, dizlerini kendine ceker (Bolum 2)",
        poz + tut, 40, dongu_bas=10)


def bitap():
    """Imlecten dusunce: domalmis, eller ve ayaklar yerde, govde yatay, kafa
    asagi-one, nefes nefese sirti inip kalkar (dizlerin ustune cokunce yere
    gomulmus gibi duruyordu)"""
    m = []
    for t, nefes in ((0, 0.0), (8, 0.0), (18, 1.0), (28, 0.0)):
        m += [kare(t, "torso", y=-0.05 - 0.04 * nefes, pitch=-1.4 - 0.07 * nefes),
              kare(t, "head", pitch=-0.35 + 0.1 * nefes),
              kare(t, "rightArm", pitch=-1.4 + 0.06 * nefes, roll=0.05),
              kare(t, "leftArm", pitch=-1.4 + 0.06 * nefes, roll=-0.05),
              # Govde egimi bacaklari da donduruyor: ters donup dik yere
              kare(t, "rightLeg", pitch=-1.4 - 0.07 * nefes + 0.1),
              kare(t, "leftLeg", pitch=-1.4 - 0.07 * nefes - 0.05)]
    yaz("b2_bitap", "Bitap", "Domalmis, nefes nefese (Bolum 2)", m, 28, dongu_bas=8)


def kalk():
    """Bitap halden dogrulma: elleriyle yerden itip yavasca dogrulur (birden
    kalkinca isinlaniyor gibiydi). Son kare duz durus: emote sorunsuz biter."""
    m = []
    for t, (gy, gp, kp, sag_b, sol_b, kol) in ((0, (-0.05, -1.4, -0.35, -1.3, -1.45, -1.4)),
                                             (9, (-0.05, -0.8, -0.1, -0.75, -0.85, -0.8)),
                                             (17, (0.0, -0.25, 0.1, -0.25, -0.25, -0.25)),
                                             (24, (0.0, 0.0, 0.0, 0.0, 0.0, 0.0))):
        m += [kare(t, "torso", y=gy, pitch=gp),
              kare(t, "head", pitch=kp),
              kare(t, "rightArm", pitch=kol, roll=0.1),
              kare(t, "leftArm", pitch=kol, roll=-0.1),
              kare(t, "rightLeg", pitch=sag_b),
              kare(t, "leftLeg", pitch=sol_b)]
    d = {"name": "Dogrul", "author": "Kevin (Liviciana)", "description": "Bitap halden ayaga kalkar (Bolum 2)",
         "emote": {"isLoop": "false", "beginTick": 0, "endTick": 24, "stopTick": 25, "degrees": False, "moves": m}}
    (OUT / "b2_kalk.json").write_text(json.dumps(d, indent=1) + "\n")


if __name__ == "__main__":
    kosu()
    diz_otur()
    kilic_at()
    kilic_cek()
    bitap()
    kalk()
    print("yazildi: b2_kos, b2_diz_otur, b2_kilic_at, b2_kilic_cek")
