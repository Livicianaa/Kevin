#!/usr/bin/env python3
"""Quaternius UAL klibini (sample_clip.gd ciktisi, eklem konumlari) Kevin'in
6 parcali Emotecraft emote'una cevirir.

Kollar omuzdan ele, bacaklar kalcadan ayaga duz cizgi (Minecraft'ta dirsek ve
diz yok). Butun vucut ("torso") pelvis->boyun ekseni ve omuz cizgisinden.
Kafa yazilmaz: cekimde kafa imlece bakiyor.

Eksenler (Godot karakter uzayi: y yukari, yuz +z, sag -x), body/emote.gd ve
character.gd'deki donusumlerden:
  kol/bacak yonu d = (-cos p sin r, -cos p cos r, -sin p)
  butun vucut B = Rz(-roll) * Ry(yaw) * Rx(-pitch)  (pitch + = geriye yaslanma)

Kullanim (modul olarak): convert(clip_json, start, end, ...) -> tick listesi
"""
import json
import math

HIP_HEIGHT = 0.75  # Kevin'in kalcasi (12 px), blok
TICKS = 20.0

LIMBS = {
    "rightArm": ("upperarm_r", "hand_r"),
    "leftArm": ("upperarm_l", "hand_l"),
    "rightLeg": ("thigh_r", "foot_r"),
    "leftLeg": ("thigh_l", "foot_l"),
}


def sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def norm(a):
    n = math.sqrt(sum(x * x for x in a)) or 1.0
    return [x / n for x in a]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def wrap(a):
    while a > math.pi:
        a -= 2 * math.pi
    while a < -math.pi:
        a += 2 * math.pi
    return a


def body_basis(f):
    """Sutunlar X, Y, Z: omuz cizgisi (sola), pelvis->boyun, one"""
    y = norm(sub(f["neck_01"], f["pelvis"]))
    sx = sub(f["upperarm_l"], f["upperarm_r"])
    x = norm(sub(sx, [c * dot(sx, y) for c in y]))
    z = cross(x, y)
    return x, y, z


def euler_from_basis(x, y, z):
    """B = Rz(a) Ry(b) Rx(c); dondurur (pitch, yaw, roll) = (-c, b, -a)"""
    # Satir-sutun: B[i][j], sutunlar x, y, z
    b20 = x[2]
    b = math.asin(max(-1.0, min(1.0, -b20)))
    a = math.atan2(x[1], x[0])
    c = math.atan2(y[2], z[2])
    return -c, b, -a


def to_local(basis, v):
    x, y, z = basis
    return [dot(v, x), dot(v, y), dot(v, z)]


def limb_angles(d, prev):
    """Yon -> (pitch, roll); iki cozumden oncekine yakin olani"""
    dx, dy, dz = d
    h = math.sqrt(dx * dx + dy * dy)
    r1 = math.atan2(-dx, -dy)
    p1 = math.atan2(-dz, h)
    s1 = (p1, r1)
    s2 = (wrap(math.pi - p1), wrap(r1 + math.pi))
    if prev is None:
        return s1 if abs(s1[1]) <= abs(s2[1]) else s2

    def cost(s):
        return abs(wrap(s[0] - prev[0])) + abs(wrap(s[1] - prev[1]))
    best = s1 if cost(s1) <= cost(s2) else s2
    # Aci sicramasin (prev + en kisa fark)
    return (prev[0] + wrap(best[0] - prev[0]), prev[1] + wrap(best[1] - prev[1]))


def load(path):
    return json.load(open(path))


def sample(frames, fps, t):
    i = t * fps
    a = int(math.floor(i))
    if a >= len(frames) - 1:
        return frames[-1]
    k = i - a
    fa, fb = frames[a], frames[a + 1]
    return {b: [fa[b][j] + (fb[b][j] - fa[b][j]) * k for j in range(3)] for b in fa}


def convert(clip, t0=0.0, t1=None, speed=1.0, rest_pelvis=None, move=False, mirror=False):
    """clip saniyeleri [t0, t1] -> emote tick'leri (0'dan). speed > 1 hizli."""
    frames, fps = clip["frames"], clip["fps"]
    if t1 is None:
        t1 = (len(frames) - 1) / fps
    p0 = rest_pelvis or frames[0]["pelvis"]
    scale = HIP_HEIGHT / p0[1]
    out = []
    prev = {k: None for k in LIMBS}
    n = int(round((t1 - t0) / speed * TICKS))
    for i in range(n + 1):
        f = sample(frames, fps, t0 + i / TICKS * speed)
        basis = body_basis(f)
        pitch, yaw, roll = euler_from_basis(*basis)
        pel = f["pelvis"]
        torso = {"pitch": pitch, "yaw": yaw, "roll": roll, "y": (pel[1] - p0[1]) * scale}
        if move:
            torso["x"] = -(pel[0] - p0[0]) * scale
            torso["z"] = -(pel[2] - p0[2]) * scale
        parts = {"torso": torso}
        for name, (a, b) in LIMBS.items():
            d = norm(to_local(basis, sub(f[b], f[a])))
            pr = limb_angles(d, prev[name])
            prev[name] = pr
            parts[name] = {"pitch": pr[0], "roll": pr[1]}
        if mirror:
            parts = mirror_parts(parts)
        out.append(parts)
    return out


def mirror_parts(parts):
    swap = {"rightArm": "leftArm", "leftArm": "rightArm", "rightLeg": "leftLeg", "leftLeg": "rightLeg"}
    res = {}
    for k, axes in parts.items():
        q = dict(axes)
        for a in ("yaw", "roll", "x"):
            if a in q:
                q[a] = -q[a]
        res[swap.get(k, k)] = q
    return res


def write(path, title, ticks, loop_from=None, keep=()):
    """ticks: her tick icin parca sozlugu. keep: elle verilen ek hareketler"""
    moves = []
    for tick, parts in enumerate(ticks):
        for part, axes in parts.items():
            moves.append({"tick": tick, "easing": "LINEAR", "turn": 0, part: {a: round(v, 4) for a, v in axes.items()}})
    moves += list(keep)
    length = len(ticks) - 1
    em = {"isLoop": "true" if loop_from is not None else "false", "beginTick": 0,
          "endTick": length, "stopTick": length + 1, "degrees": False, "moves": moves}
    if loop_from is not None:
        em["returnTick"] = loop_from
    data = {"name": title, "author": "Quaternius (CC0), Kevin'e aktarildi",
            "description": "Universal Animation Library, CC0", "emote": em}
    open(path, "w").write(json.dumps(data, ensure_ascii=False))
    print(f"{path}: {length} tick")
