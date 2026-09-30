extends RefCounted
## Emotecraft / PlayerAnimator (.json) emote oynatici.
##
## Emote'lar Minecraft oyuncu modelinin 6 parcasi icin yazilmis anahtar kareler:
## kafa, gövde, kollar, bacaklar + butun vucut ("torso", eski surumlerde).
## Parca konumlari ve acilari Fresh Animations (CEM) ile AYNI model uzayinda,
## karakter ikisini ayni donusumle yerlestiriyor.
##
## Anahtar karesi olmayan eksen dokunulmadan kalir: emote o eksene hic
## karismaz, altta calisan Fresh Animations / fareye bakis gorunur.

const TICKS := 20.0

## Emotecraft parca adi -> bizim poz anahtarimiz
const PART_NAMES := {
	"head": "head", "rightArm": "right_arm", "leftArm": "left_arm",
	"rightLeg": "right_leg", "leftLeg": "left_leg",
}
const AXES := {
	"x": "tx", "y": "ty", "z": "tz", "pitch": "rx", "yaw": "ry", "roll": "rz",
}
const ANGLE_AXES := ["pitch", "yaw", "roll"]

var name := ""
var looped := false
var begin_tick := 0
var end_tick := 1
var stop_tick := 1
var return_tick := 0

## "right_arm_rx" -> [[tick, deger, easing], ...] (tick sirali)
## Butun vucut icin "whole_tx" ... "whole_rz"
var tracks := {}


static func load_file(path: String) -> RefCounted:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or not data.has("emote"):
		return null
	var e := new()
	if not e._read(data):
		return null
	e.name = path.get_file().get_basename()
	return e


func _read(data: Dictionary) -> bool:
	var em: Dictionary = data.emote
	var version := int(data.get("version", 1))
	begin_tick = int(em.get("beginTick", 0))
	end_tick = int(em.get("endTick", 0))
	if end_tick <= 0:
		return false
	stop_tick = int(em.get("stopTick", end_tick))
	looped = str(em.get("isLoop", false)).to_lower() == "true" and em.has("returnTick")
	return_tick = int(em.get("returnTick", 0))
	var degrees := str(em.get("degrees", true)).to_lower() == "true"

	for move in em.get("moves", []):
		var tick := int(move.get("tick", 0))
		var ease := _ease_name(str(move.get("easing", "linear")))
		var turn := int(move.get("turn", 0))
		for key in move:
			if not (move[key] is Dictionary):
				continue
			var part := ""
			if key == "body" or (key == "torso" and version < 3):
				part = "whole"
			elif PART_NAMES.has(key):
				part = PART_NAMES[key]
			else:
				continue
			for axis in AXES:
				if not move[key].has(axis):
					continue
				var v := float(move[key][axis])
				if axis in ANGLE_AXES:
					if degrees:
						v = deg_to_rad(v)
					v += TAU * turn
				var track_name: String = part + "_" + AXES[axis]
				if not tracks.has(track_name):
					tracks[track_name] = []
				tracks[track_name].append([tick, v, ease])

	for k in tracks:
		tracks[k].sort_custom(func(a, b): return a[0] < b[0])
	return not tracks.is_empty()


func length_seconds() -> float:
	return stop_tick / TICKS


func finished(t: float) -> bool:
	return not looped and t * TICKS >= stop_tick


## Emote'u t saniyesinde pozun ustune yazar. weight 0-1 (dongulu emote'tan
## cikarken yumusak birakmak icin). Butun vucut dönüşümünü dondurur.
func apply(pose: Dictionary, t: float, weight: float) -> Dictionary:
	var tick := t * TICKS
	var loop_started := false
	if looped and tick > end_tick:
		loop_started = true
		tick = return_tick + fmod(tick - return_tick, end_tick - return_tick + 1)

	var whole := {}
	for track_name in tracks:
		var is_whole: bool = track_name.begins_with("whole_")
		var base: float = 0.0 if is_whole else float(pose.get(track_name, 0.0))
		var v := _sample(tracks[track_name], tick, base, loop_started)
		v = lerpf(base, v, weight)
		if is_whole:
			whole[track_name.substr(6)] = v
		else:
			pose[track_name] = v
	return whole


func _sample(keys: Array, tick: float, base: float, loop_started: bool) -> float:
	var period := float(end_tick - return_tick + 1)
	var bi := -1
	for i in keys.size():
		if keys[i][0] <= tick:
			bi = i
		else:
			break

	var before: Array
	var after: Array
	if bi < 0:
		before = [0, base, "inoutsine"]
	else:
		before = keys[bi]
	if loop_started and before[0] < return_tick:
		# Dongunun basina donduk: onceki kare son kare, bir periyot geride
		var last: Array = keys[keys.size() - 1]
		before = [last[0] - period, last[1], last[2]]

	if bi + 1 < keys.size():
		after = keys[bi + 1]
	elif looped:
		after = []
		for k in keys:
			if k[0] >= return_tick:
				after = [k[0] + period, k[1], k[2]]
				break
		if after.is_empty():
			return before[1]
	elif tick < end_tick:
		return before[1]
	else:
		# Emote bitti: son kareden normal duruşa geri don
		before = [end_tick, keys[keys.size() - 1][1], "inoutquad"]
		after = [stop_tick, base, "linear"]

	var span := float(after[0] - before[0])
	if span <= 0.0:
		return before[1]
	var f := clampf((tick - before[0]) / span, 0.0, 1.0)
	return lerpf(before[1], after[1], _ease(before[2], f))


static func _ease_name(s: String) -> String:
	s = s.to_lower()
	if s.begins_with("ease"):
		s = s.substr(4)
	return s


static func _ease(e: String, f: float) -> float:
	if e == "constant":
		return 0.0
	if e == "linear":
		return f
	var fn := func(x: float) -> float: return x * x
	if e.ends_with("sine"):
		fn = func(x: float) -> float: return 1.0 - cos(x * PI / 2.0)
	elif e.ends_with("cubic"):
		fn = func(x: float) -> float: return x * x * x
	elif e.ends_with("quart"):
		fn = func(x: float) -> float: return x * x * x * x
	elif e.ends_with("quint"):
		fn = func(x: float) -> float: return x * x * x * x * x
	elif e.ends_with("expo"):
		fn = func(x: float) -> float: return 0.0 if x == 0.0 else pow(2.0, 10.0 * x - 10.0)
	elif e.ends_with("circ"):
		fn = func(x: float) -> float: return 1.0 - sqrt(1.0 - x * x)
	elif not e.ends_with("quad"):
		return f
	if e.begins_with("inout"):
		return fn.call(f * 2.0) / 2.0 if f < 0.5 else 1.0 - fn.call((1.0 - f) * 2.0) / 2.0
	if e.begins_with("out"):
		return 1.0 - fn.call(1.0 - f)
	return fn.call(f)
