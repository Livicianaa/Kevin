#!/usr/bin/env python3
"""Cekim emote'lari: Quaternius UAL kliplerinden (body/anim/ual) yumruk sahnesi.
_r: sag kol yumruk (imlec sagda), _l: ayna.

Kullanim: python3 body/tools/make_ual_emotes.py
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ual_to_emote as u  # noqa: E402

CLIPS = HERE.parent / "anim" / "ual"
OUT = HERE.parent / "emotes"
## cekim.gd UCUS_TIME (bacak emote'u bu surede)
UCUS_ARKA = 0.7
## Punch_Cross: 0-5. kare gard
GUARD_T = 4 / 30.0


def no_twist(ticks):
    """Govde donmesi yok: Kevin havada yandan kalsin (klipteki kalca donusu
    onu kameraya ceviriyordu, yumruk yana itme gibi gorunuyordu)"""
    for f in ticks:
        f["torso"]["yaw"] = 0.0
    return ticks


def both(name, title, ticks, loop_from=None):
    u.write(OUT / f"{name}_r.json", title, ticks, loop_from)
    u.write(OUT / f"{name}_l.json", title + " (ayna)", [u.mirror_parts(p) for p in ticks], loop_from)


def main():
    rest = u.load(CLIPS / "Idle_Loop.json")["frames"][0]["pelvis"]
    start = u.load(CLIPS / "NinjaJump_Start.json")
    punch = u.load(CLIPS / "Punch_Cross.json")
    jab = u.load(CLIPS / "Punch_Jab.json")
    land = u.load(CLIPS / "NinjaJump_Land.json")

    # Gerilme: ninja ziplamasinin comelmis ilk karesi, govde titrer
    crouch = no_twist(u.convert(start, 0.0, 0.05, rest_pelvis=rest))[0]
    ticks = []
    for i in range(12):
        f = {k: dict(v) for k, v in crouch.items()}
        f["torso"]["roll"] = f["torso"].get("roll", 0.0) + (0.025 if i % 2 else -0.025)
        ticks.append(f)
    both("u_geril", "Gerilme (UAL NinjaJump_Start)", ticks, loop_from=0)

    # Ucus bacaklari (kollari cekim.gd veriyor): siciyip bacaklari onde-arkada
    # acar, vurusta arka bacak geriye uzanir, govde vurusa dogru egilir.
    # Torso pitch + geriye yaslanma, bacak pitch - one.
    def poz(on, arka, govde):
        return {"torso": {"pitch": govde, "yaw": 0.0, "roll": 0.0, "y": 0.0},
                "leftLeg": {"pitch": on, "roll": 0.0}, "rightLeg": {"pitch": arka, "roll": 0.0}}
    ucus_ticks = round(UCUS_ARKA * u.TICKS)
    keys = [(0, poz(-0.2, 0.2, 0.0)), (3, poz(-0.95, 0.55, -0.1)), (ucus_ticks - 3, poz(-0.95, 0.55, -0.1)),
            (ucus_ticks, poz(-0.35, 1.05, -0.3))]
    ticks = []
    for i in range(ucus_ticks + 1):
        for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
            if t0 <= i <= t1:
                k = (i - t0) / max(1, t1 - t0)
                k = k * k * (3 - 2 * k)
                ticks.append({part: {ax: p0[part][ax] + (p1[part][ax] - p0[part][ax]) * k for ax in p0[part]} for part in p0})
                break
    both("u_ucus", "Ucus bacaklari (yumruk)", ticks, loop_from=len(ticks) - 1)

    # Ofke: imlece dogru havaya sol-sag-sol-sag yumruk (golge boks), sonra
    # gardda titreyerek bekler
    combo = u.convert(jab, 0.0, None, speed=1.5, rest_pelvis=rest)
    combo += u.convert(punch, 0.0, None, speed=1.5, rest_pelvis=rest)[1:]
    combo += u.convert(jab, 0.0, None, speed=1.6, rest_pelvis=rest)[1:]
    combo += u.convert(punch, 0.0, None, speed=1.6, rest_pelvis=rest)[1:]
    gard = u.convert(punch, GUARD_T, GUARD_T + 0.02, rest_pelvis=rest)[0]
    loop_from = len(combo)
    for i in range(8):
        f = {k: dict(v) for k, v in gard.items()}
        f["torso"]["roll"] = f["torso"].get("roll", 0.0) + (0.02 if i % 2 else -0.02)
        combo.append(f)
    both("u_ofke", "Ofke (UAL Punch_Jab + Punch_Cross)", combo, loop_from=loop_from)

    # Inis: comelip eli yere, kayar, sonra dogrulur
    both("u_inis", "Inis (UAL NinjaJump_Land)", u.convert(land, 0.0, None, rest_pelvis=rest))

if __name__ == "__main__":
    main()
