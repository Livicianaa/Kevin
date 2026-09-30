extends Node3D
## Minecraft karakteri.
##
## Uc hali var:
##  ANIMATED   - ayakta; yuruyor, bakiniyor, fareye bakiyor. bin/cem/player.jem
##               (Fresh Animations) varsa animasyonu o paket uretiyor.
##  RAGDOLL    - bir uzvundan tutuldu ya da dusuyor; Godot'nun fizik motoru suruyor
##  GETTING_UP - ragdoll bitti; dustugu pozdan ayakta duruşa gecis
##
## Butun pozlar EKLEM noktalarindan hesaplaniyor: govde bir yerde durur, her uzuv
## kendi ekleminde doner. Onceden kalkis sirasinda parcalar bagimsiz kaydiriliyordu;
## eklemler hesaba katilmadigi icin uzuvlar govdeden ayrilip ic ice giriyordu.

const PX := 1.0 / 16.0
const SKIN_SIZE := 64.0

## Parcalar (piksel): boyut, ayakta merkez, skin UV koku (ic/dis katman), kutle
const PARTS := {
	"head":      { "size": Vector3(8, 8, 8),  "center": Vector3(0, 28, 0),  "uv": Vector2(0, 0),   "overlay": Vector2(32, 0),  "mass": 4.0 },
	"body":      { "size": Vector3(8, 12, 4), "center": Vector3(0, 18, 0),  "uv": Vector2(16, 16), "overlay": Vector2(16, 32), "mass": 10.0 },
	"right_arm": { "size": Vector3(4, 12, 4), "center": Vector3(-6, 18, 0), "uv": Vector2(40, 16), "overlay": Vector2(40, 32), "mass": 2.5 },
	"left_arm":  { "size": Vector3(4, 12, 4), "center": Vector3(6, 18, 0),  "uv": Vector2(32, 48), "overlay": Vector2(48, 48), "mass": 2.5 },
	"right_leg": { "size": Vector3(4, 12, 4), "center": Vector3(-2, 6, 0),  "uv": Vector2(0, 16),  "overlay": Vector2(0, 32),  "mass": 4.0 },
	"left_leg":  { "size": Vector3(4, 12, 4), "center": Vector3(2, 6, 0),   "uv": Vector2(16, 48), "overlay": Vector2(0, 48),  "mass": 4.0 },
}

## Uzuvlar: govdeye baglandigi eklem (piksel, ayakta) ve fizikteki koni acisi (derece)
const LIMBS := {
	"head":      { "joint": Vector3(0, 24, 0),  "swing": 32.0 },
	"right_arm": { "joint": Vector3(-5, 23, 0), "swing": 105.0 },
	"left_arm":  { "joint": Vector3(5, 23, 0),  "swing": 105.0 },
	"right_leg": { "joint": Vector3(-2, 12, 0), "swing": 50.0 },
	"left_leg":  { "joint": Vector3(2, 12, 0),  "swing": 50.0 },
}

const BODY_REST_PX := Vector3(0, 18, 0)
const WALK_SPEED := 1.4
const TURN_SPEED := 6.0
## Yururken yonune bakis. Yari donuk (0.95 rad) yurudugunde karakter kameraya
## dogru yuruyormus gibi gorunuyordu; neredeyse tam profil.
const FACE_SIDE := PI / 2.0
const GETUP_DELAY := 1.0
const GETUP_TIME := 0.9
const SETTLE_ENERGY := 0.12
const MAX_LYING_TIME := 4.0

enum Mode { ANIMATED, RAGDOLL, GETTING_UP }

const Cem := preload("res://cem.gd")
## Yururken Minecraft'in limb_speed degeri ve limb_swing'in saniyede artisi.
## Adim boyu yurume hizina uysun diye secildi (ayaklar kaymasin).
const CEM_WALK_LIMB_SPEED := 0.45
const CEM_SWING_RATE := 16.0
## Minecraft oyuncu modelinde parcalarin donme noktalari (piksel, y asagi)
const CEM_PIVOT := {
	"head": Vector3(0, 0, 0),
	"body": Vector3(0, 0, 0),
	"right_arm": Vector3(-5, 2, 0),
	"left_arm": Vector3(5, 2, 0),
	"right_leg": Vector3(-1.9, 12, 0),
	"left_leg": Vector3(1.9, 12, 0),
}
const CEM_BLEND_TIME := 0.3

const Emote := preload("res://emote.gd")
## Hangi emote ne zaman. Listede olmayan (kullanicinin bin/emotes'a attigi)
## emote'lar "fun" havuzuna giriyor.
const EMOTE_POOLS := {
	"idle": ["lookaround", "Inspect", "item", "hunchback", "shake", "nervous", "heart", "bow2"],
	"rest": ["sit_lean_wall", "cool_sit", "campfire_sit1", "lejat", "lay_down5", "meditation_fly"],
	"fun": ["dab", "the_dab", "floss_dance3", "orange justice", "club_penguin_dance", "take the l",
		"jump", "jumping jacks", "selfie", "headspin", "tpose"],
	"social": ["meeting", "hug", "hearthands", "bow1", "F", "make_gestures", "grace"],
}
## Dongulu emote'larin suresi (saniye) havuza gore
const LOOP_TIME := {"idle": Vector2(2.5, 4.0), "rest": Vector2(10.0, 22.0), "fun": Vector2(4.0, 7.0), "social": Vector2(3.0, 5.0)}
const EMOTE_FADE := 0.5
## Rastgele secimde agirlik (varsayilan 1). lookaround sik geliyordu.
const EMOTE_WEIGHT := {"lookaround": 0.25}

var emotes := {}
var emote_pool := {}
var emote: RefCounted = null
var emote_t := 0.0
var emote_until := 0.0
var emote_weight := 1.0
## Emote boyunca tutulacak yon (NAN = kameraya don). Kenara yaslaninca yana.
var emote_facing := NAN
## Yurume bitince ne yapilacak ("wall_sit" = kenara yaslanip otur)
var after_walk := ""
var wall_sit_facing := 0.0

var cem: RefCounted = null
var cem_age := 0.0
var limb_swing := 0.0
var limb_speed := 0.0
var cem_blend := 1.0
var cem_blend_from := {}

var mode := Mode.ANIMATED
var bodies := {}
var joint_probes := []
var skin_texture: Texture2D

# Ayakta durum
var root_x := 0.0
var facing := 0.0
var facing_now := 0.0
var anim_state := "idle"
var anim_t := 0.0
var state_timer := 2.0
var walk_target := 0.0
var bounds := Vector2(-4.0, 4.0)
## Karakterin bulundugu ekranin zemini (dunya y). Ekranlar farkli yukseklikte
## olabiliyor (laptop 1.5 olcekli: alti 720'de, yandaki ekranin 1080'de).
var ground_y := 0.0

# Fareye bakma (main her karede fare konumunu dunya birimi olarak veriyor)
var look_point := Vector3(0, 3, 0)
var look_yaw := 0.0
var look_pitch := 0.0
var last_look_point := Vector3.ZERO
var mouse_activity := 0.0
var attention_left := 0.0
var attention_cooldown := 3.0

# Ragdoll / kalkis
var settle_timer := 0.0
var released_for := 0.0
var getup_t := 0.0
var getup_from_body := Transform3D()
var getup_from_local := {}
var getup_to_origin := Vector3.ZERO


func _ready() -> void:
	skin_texture = load("res://skins/totem.png")
	for part_name in PARTS.keys():
		_build_part(part_name)
	for limb in LIMBS.keys():
		_build_joint("body", limb, LIMBS[limb].joint * PX, deg_to_rad(LIMBS[limb].swing))

	# Govdenin kendi parcalari birbirine carpmasin: bacaklar yan yana temas
	# halinde basliyor, carpisma acikken itisip titremeye yol aciyorlardi.
	var names := bodies.keys()
	for i in names.size():
		for k in range(i + 1, names.size()):
			bodies[names[i]].add_collision_exception_with(bodies[names[k]])

	_set_frozen(true)
	_apply_pose(_animated_pose(0.0), _body_transform(0.0, 0.0))
	_load_cem()
	_load_emotes()


func _load_emotes() -> void:
	var dirs := [
		ProjectSettings.globalize_path("res://emotes"),
		ProjectSettings.globalize_path("res://").path_join("../bin/emotes").simplify_path(),
	]
	if OS.get_environment("KEVIN_EMOTES") != "":
		dirs.append(OS.get_environment("KEVIN_EMOTES"))
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".json"):
				continue
			var e = Emote.load_file(dir.path_join(f))
			if e == null:
				push_warning("[kevin] emote okunamadi: " + f)
				continue
			emotes[e.name] = e
	for name in emotes:
		emote_pool[name] = "fun"
		for pool in EMOTE_POOLS:
			if name in EMOTE_POOLS[pool]:
				emote_pool[name] = pool
	print("[kevin] %d emote yuklendi" % emotes.size())


## Emote oynat (beyin de bunu cagiracak). Dongulu emote'lar sure bitince
## yumusakca birakiliyor, digerleri kendi sonunda.
func play_emote(emote_name: String, seconds := -1.0) -> bool:
	if mode != Mode.ANIMATED or not emotes.has(emote_name):
		return false
	emote = emotes[emote_name]
	emote_t = 0.0
	emote_weight = 1.0
	emote_facing = NAN
	var pool: String = emote_pool.get(emote_name, "fun")
	var range: Vector2 = LOOP_TIME[pool]
	emote_until = seconds if seconds > 0.0 else randf_range(range.x, range.y)
	if not emote.looped:
		emote_until = emote.length_seconds()
	_set_state("emote", 0.0)
	return true


func _random_emote(pool: String) -> String:
	var names := []
	var weights := []
	for n in emote_pool:
		if emote_pool[n] == pool:
			names.append(n)
			weights.append(EMOTE_WEIGHT.get(n, 1.0))
	if names.is_empty():
		return ""
	return names[RandomNumberGenerator.new().rand_weighted(PackedFloat32Array(weights))]


func _load_cem() -> void:
	var path := OS.get_environment("KEVIN_CEM")
	if path == "":
		path = ProjectSettings.globalize_path("res://").path_join("../bin/cem/player.jem").simplify_path()
	cem = Cem.load_pack(path)
	if cem == null:
		print("[kevin] CEM paketi yok (%s), yerlesik animasyonlar" % path)
		return
	for w in cem.warnings:
		push_warning("[kevin] CEM: " + w)
	print("[kevin] CEM paketi yuklendi: ", path)


# =====================================================================
# Kurulum
# =====================================================================

func _build_part(part_name: String) -> void:
	var spec: Dictionary = PARTS[part_name]

	var body := RigidBody3D.new()
	body.name = part_name
	body.mass = spec.mass
	body.position = spec.center * PX
	# Havada asili cok parcali sarkac: sonum dusukken sallanma surup gidiyordu.
	body.linear_damp = 1.0
	body.angular_damp = 6.0
	body.continuous_cd = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = spec.size * PX
	shape.shape = box
	body.add_child(shape)

	body.add_child(_make_box_mesh(spec.size, spec.uv, 0.0))
	body.add_child(_make_box_mesh(spec.size, spec.overlay, 0.5))

	add_child(body)
	bodies[part_name] = body


func _build_joint(a_name: String, b_name: String, world_point: Vector3, swing: float) -> void:
	var a: RigidBody3D = bodies[a_name]
	var b: RigidBody3D = bodies[b_name]

	var joint := ConeTwistJoint3D.new()
	joint.position = world_point
	joint.rotation = Vector3(0, 0, PI / 2)
	add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25))
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)

	joint_probes.append([a, a.transform.affine_inverse() * world_point,
		b, b.transform.affine_inverse() * world_point, "%s-%s" % [a_name, b_name]])


## Minecraft skin UV duzenine gore kutu. grow: dis katman icin piksel sisirme.
func _make_box_mesh(px_size: Vector3, uv_origin: Vector2, grow: float) -> MeshInstance3D:
	var w := px_size.x
	var h := px_size.y
	var d := px_size.z
	var hx := (w / 2.0 + grow) * PX
	var hy := (h / 2.0 + grow) * PX
	var hz := (d / 2.0 + grow) * PX
	var u := uv_origin.x
	var v := uv_origin.y

	var faces := [
		[Vector3(0, 0, 1),  [Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)],   Rect2(u + d, v + d, w, h)],
		[Vector3(0, 0, -1), [Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz)], Rect2(u + d + w + d, v + d, w, h)],
		[Vector3(-1, 0, 0), [Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz)], Rect2(u, v + d, d, h)],
		[Vector3(1, 0, 0),  [Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)],     Rect2(u + d + w, v + d, d, h)],
		[Vector3(0, 1, 0),  [Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)],     Rect2(u + d, v, w, d)],
		[Vector3(0, -1, 0), [Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz)], Rect2(u + d + w, v, w, d)],
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var normal: Vector3 = face[0]
		var c: Array = face[1]
		var r: Rect2 = face[2]
		var uv_tl := Vector2(r.position.x, r.position.y) / SKIN_SIZE
		var uv_tr := Vector2(r.position.x + r.size.x, r.position.y) / SKIN_SIZE
		var uv_br := Vector2(r.position.x + r.size.x, r.position.y + r.size.y) / SKIN_SIZE
		var uv_bl := Vector2(r.position.x, r.position.y + r.size.y) / SKIN_SIZE
		for pair in [[c[0], uv_tl], [c[1], uv_tr], [c[2], uv_br], [c[0], uv_tl], [c[2], uv_br], [c[3], uv_bl]]:
			st.set_normal(normal)
			st.set_uv(pair[1])
			st.add_vertex(pair[0])

	var material := StandardMaterial3D.new()
	material.albedo_texture = skin_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.roughness = 1.0

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	return mi


# =====================================================================
# Eklem tabanli poz
# =====================================================================

## Govdenin dunya transformu: konum (x, zemin + ziplama) ve yon (y ekseni).
func _body_transform(lift: float, lean: float) -> Transform3D:
	var basis := Basis(Vector3.UP, facing_now) * Basis(Vector3.RIGHT, lean)
	var origin := Vector3(root_x, ground_y + BODY_REST_PX.y * PX + lift, 0)
	return Transform3D(basis, origin)


## Uzuvlarin govdeye gore yerel donusleri (Euler, radyan) ile poz uygular.
## Her uzuv kendi eklem noktasinda doner - uzuvlar govdeden ASLA ayrilmaz.
func _apply_pose(local_rot: Dictionary, body_xf: Transform3D) -> void:
	bodies["body"].global_transform = body_xf
	for limb in LIMBS.keys():
		var basis: Basis = body_xf.basis * _local_basis(local_rot[limb])
		_place_limb(limb, body_xf, basis)


func _local_basis(value) -> Basis:
	if value is Quaternion:
		return Basis(value)
	return Basis.from_euler(value)


func _place_limb(limb: String, body_xf: Transform3D, limb_basis: Basis) -> void:
	var spec: Dictionary = LIMBS[limb]
	var joint_local: Vector3 = (spec.joint - BODY_REST_PX) * PX
	var center_from_joint: Vector3 = (PARTS[limb].center - spec.joint) * PX
	var joint_world: Vector3 = body_xf * joint_local
	bodies[limb].global_transform = Transform3D(limb_basis, joint_world + limb_basis * center_from_joint)


# =====================================================================
# Ayakta durus (kalkisin hedefi). Ayaktayken pozu Fresh Animations + emote'lar
# uretiyor (_cem_step); bu sadece eklem tabanli kalkis icin.
# =====================================================================

const ARM_REST := PI * 0.02

func _animated_pose(_t: float) -> Dictionary:
	return {
		"head": Vector3.ZERO,
		"right_arm": Vector3(0, 0, -ARM_REST),
		"left_arm": Vector3(0, 0, ARM_REST),
		"right_leg": Vector3.ZERO,
		"left_leg": Vector3.ZERO,
	}


## Kafa: bakinma animasyonu ya da fareye bakis (govdeye gore). x = egim, y = donus
func _head_angles(t: float) -> Vector2:
	if anim_state == "walk":
		return Vector2.ZERO
	return Vector2(look_pitch, look_yaw)


# =====================================================================
# CEM (Fresh Animations): Minecraft'in vanilla pozu hesaplanip pakete veriliyor,
# paket onun ustune kendi animasyonunu yaziyor - oyundaki gibi.
# =====================================================================

func _cem_step(delta: float) -> void:
	cem_age += delta * 20.0
	# Adim sadece tam yana donmusken: yuzu kameraya donukken adim atinca
	# "ekrana dogru yuruyor" gibi gorunuyordu
	var turned := absf(facing_now - facing) < 0.05 and absf(facing) > 0.1
	var target_speed := CEM_WALK_LIMB_SPEED if anim_state == "walk" and turned else 0.0
	limb_speed = move_toward(limb_speed, target_speed, delta * 2.0)
	limb_swing += limb_speed * CEM_SWING_RATE * delta

	var ls := limb_swing * 0.6662
	var bob_z := cos(cem_age * 0.09) * 0.05 + 0.05
	var bob_x := sin(cem_age * 0.067) * 0.05
	var head := _head_angles(anim_t)

	# Minecraft HumanoidModel.setupAnim (model uzayi: y asagi)
	var pose := {
		"head_rx": head.x, "head_ry": -head.y,
		"right_arm_rx": cos(ls + PI) * limb_speed + bob_x, "right_arm_rz": bob_z,
		"left_arm_rx": cos(ls) * limb_speed - bob_x, "left_arm_rz": -bob_z,
		"right_leg_rx": cos(ls) * 1.4 * limb_speed,
		"left_leg_rx": cos(ls + PI) * 1.4 * limb_speed,
	}
	for part in CEM_PIVOT:
		var pv: Vector3 = CEM_PIVOT[part]
		pose[part + "_tx"] = pv.x
		pose[part + "_ty"] = pv.y
		pose[part + "_tz"] = pv.z

	if cem:
		cem.apply(pose, {
		"age": cem_age, "time": cem_age / 20.0, "frame_time": delta,
		"limb_swing": limb_swing, "limb_speed": limb_speed,
		"move_forward": 1.0 if anim_state == "walk" else 0.0,
		"is_on_ground": 1.0, "id": 7.0, "health": 20.0, "max_health": 20.0,
	})

	var root := Transform3D(Basis(Vector3.UP, facing_now), Vector3(root_x, ground_y, 0))
	if emote:
		root = root * _whole_body(emote.apply(pose, emote_t, emote_weight))
	if cem_blend < 1.0:
		cem_blend = minf(1.0, cem_blend + delta / CEM_BLEND_TIME)
	var k := ease(cem_blend, -2.0)
	for part in CEM_PIVOT:
		var xf := root * _cem_part_transform(part, pose)
		if k < 1.0 and cem_blend_from.has(part):
			xf = (cem_blend_from[part] as Transform3D).interpolate_with(xf, k)
		bodies[part].global_transform = xf


## Emote'un butun vucut hareketi (yatma, egilme, ziplama). Minecraft bunu
## varligin kendi uzayinda (y yukari, yuz -z, birim blok) ayaklarin 0.7 blok
## ustundeki noktanin etrafinda uyguluyor; bizim uzaya Y'de 180 derece.
func _whole_body(w: Dictionary) -> Transform3D:
	if w.is_empty():
		return Transform3D.IDENTITY
	var pos := Vector3(-float(w.get("tx", 0.0)), float(w.get("ty", 0.0)), -float(w.get("tz", 0.0)))
	var basis := Basis(Vector3.BACK, -float(w.get("rz", 0.0))) \
		* Basis(Vector3.UP, float(w.get("ry", 0.0))) \
		* Basis(Vector3.RIGHT, -float(w.get("rx", 0.0)))
	var pivot := Vector3(0, 0.7, 0)
	return Transform3D(Basis.IDENTITY, pos + pivot) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


## Model uzayi (y asagi, yuz -z) -> karakter uzayi (y yukari, yuz +z): X ekseni
## etrafinda 180 derece. Bu yuzden rx ayni kalir, ry ve rz ters doner.
## Minecraft donus sirasi Z*Y*X.
func _cem_part_transform(part: String, pose: Dictionary) -> Transform3D:
	var t := Vector3(pose[part + "_tx"], pose[part + "_ty"], pose[part + "_tz"])
	var basis := Basis(Vector3.BACK, -float(pose.get(part + "_rz", 0.0))) \
		* Basis(Vector3.UP, -float(pose.get(part + "_ry", 0.0))) \
		* Basis(Vector3.RIGHT, float(pose.get(part + "_rx", 0.0)))
	var rest: Vector3 = CEM_PIVOT[part]
	var rest_world := Vector3(rest.x, 24.0 - rest.y, -rest.z)
	var offset: Vector3 = (PARTS[part].center - rest_world) * PX
	var pivot := Vector3(t.x, 24.0 - t.y, -t.z) * PX
	return Transform3D(basis, pivot + basis * offset)


# =====================================================================
# Davranis (ayaktayken)
# =====================================================================

func _update_behaviour(delta: float) -> void:
	anim_t += delta
	state_timer -= delta

	match anim_state:
		"idle":
			if state_timer <= 0.0:
				_choose_next()
		"emote":
			emote_t += delta
			if emote == null or emote.finished(emote_t):
				_end_emote()
			elif emote.looped and emote_t >= emote_until:
				emote_weight -= delta / EMOTE_FADE
				if emote_weight <= 0.0:
					_end_emote()
		"walk":
			var dir := signf(walk_target - root_x)
			facing = dir * FACE_SIDE
			# Once yana don, sonra yuru
			if absf(facing_now - facing) < 0.05:
				root_x += dir * WALK_SPEED * delta * (limb_speed / CEM_WALK_LIMB_SPEED)
			if dir == 0.0 or (dir > 0 and root_x >= walk_target) or (dir < 0 and root_x <= walk_target):
				root_x = walk_target
				if after_walk == "wall_sit" and play_emote("sit_lean_wall", randf_range(15.0, 30.0)):
					emote_facing = wall_sit_facing
				else:
					_set_state("idle", randf_range(0.8, 2.5))
				after_walk = ""

	# Yurumuyorken izleyiciye (kameraya) don - ama adimlar bittikten sonra
	if anim_state == "emote" and not is_nan(emote_facing):
		facing = emote_facing
	elif anim_state != "walk" and limb_speed < 0.02:
		facing = 0.0
	facing_now = move_toward(facing_now, facing, TURN_SPEED * delta)
	root_x = clampf(root_x, bounds.x, bounds.y)

	_update_look(delta)


func _end_emote() -> void:
	emote = null
	emote_facing = NAN
	_set_state("idle", randf_range(0.8, 2.5))


## Siradaki davranis. Kisa bir durusla yuruyus arasina emote'lar giriyor;
## uzun dinlenmeler (oturma, uzanma) seyrek.
func _choose_next() -> void:
	var roll := randf()
	var pool := ""
	if roll < 0.08:
		pool = "idle"
	elif roll < 0.13:
		pool = "fun"
	elif roll < 0.15:
		pool = "rest"
	elif roll < 0.18:
		_go_wall_sit()
		return
	if pool != "":
		var name := _random_emote(pool)
		if name != "sit_lean_wall" and name != "" and play_emote(name):
			return
	if randf() < 0.8:
		var span := bounds.y - bounds.x
		walk_target = clampf(root_x + randf_range(-0.45, 0.45) * span, bounds.x + 0.4, bounds.y - 0.4)
		if absf(walk_target - root_x) < 0.5:
			walk_target = clampf(root_x + 1.5 * (1 if randf() < 0.5 else -1), bounds.x + 0.4, bounds.y - 0.4)
		_set_state("walk", 0.0)
	else:
		_set_state("idle", randf_range(1.0, 3.0))


## En yakin kenara yuru, sirtini yaslayip otur (livi: "yasli dayilar gibi")
func _go_wall_sit() -> void:
	var left := root_x - bounds.x < bounds.y - root_x
	if randf() < 0.25:
		left = not left
	walk_target = bounds.x if left else bounds.y
	after_walk = "wall_sit"
	# Sirti kenara: yuzu ekranin icine
	wall_sit_facing = FACE_SIDE if left else -FACE_SIDE
	_set_state("walk", 0.0)


func _set_state(state: String, duration: float) -> void:
	anim_state = state
	state_timer = duration


## Fareye bakis artik OLAY: fare hareket edince ara sira "bu ne yapiyor" diye
## kisa bakip birakiyor. Onceden kafa surekli farenin durdugu yere kilitliydi,
## fare kimildamayinca bos bir noktaya bakiyormus gibi duruyordu.
## (Baska pencerede klavyeyi goremiyoruz; tetik sadece fare.)
func _update_look(delta: float) -> void:
	var head_pos := Vector3(root_x, ground_y + (LIMBS.head.joint.y + 4) * PX, 0)
	var moved := look_point.distance_to(last_look_point)
	last_look_point = look_point
	mouse_activity = maxf(0.0, mouse_activity - delta * 2.0) + moved

	attention_cooldown -= delta
	attention_left -= delta
	if attention_left <= 0.0 and attention_cooldown <= 0.0 and mouse_activity > 1.2:
		var near := look_point.distance_to(head_pos) < 3.0
		if randf() < (0.6 if near else 0.25):
			attention_left = randf_range(1.2, 2.6)
			attention_cooldown = randf_range(10.0, 25.0)
		else:
			attention_cooldown = randf_range(2.0, 4.0)

	var target := Vector2.ZERO
	if attention_left > 0.0 and anim_state != "walk":
		var to := look_point - head_pos
		target = Vector2(
			clampf(-atan2(to.y, 3.0), -0.5, 0.45),
			clampf(atan2(to.x, 3.0) - facing_now, -0.9, 0.9),
		)
	else:
		# Kendi halinde: onune bakiyor, cok yavas hafif bir kayma
		target = Vector2(sin(anim_t * 0.23) * 0.04, sin(anim_t * 0.17 + 1.3) * 0.1)
	var k := minf(1.0, delta * (6.0 if attention_left > 0.0 else 2.0))
	look_pitch = lerpf(look_pitch, target.x, k)
	look_yaw = lerpf(look_yaw, target.y, k)


# =====================================================================
# Ragdoll ve kalkis
# =====================================================================

func _set_frozen(frozen: bool) -> void:
	for body in bodies.values():
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = frozen
		if not frozen:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO


func start_ragdoll() -> void:
	emote = null
	emote_facing = NAN
	after_walk = ""
	mode = Mode.RAGDOLL
	settle_timer = 0.0
	released_for = 0.0
	_set_frozen(false)


func release_ragdoll() -> void:
	settle_timer = 0.0


func is_ragdoll() -> bool:
	return mode == Mode.RAGDOLL


func _physics_process(delta: float) -> void:
	match mode:
		Mode.ANIMATED:
			_update_behaviour(delta)
			_cem_step(delta)
		Mode.RAGDOLL:
			_update_ragdoll(delta)
		Mode.GETTING_UP:
			_advance_getup(delta)


func _update_ragdoll(delta: float) -> void:
	if get_parent().has_method("is_holding") and get_parent().is_holding():
		settle_timer = 0.0
		released_for = 0.0
		return

	released_for += delta
	var energy := 0.0
	for body in bodies.values():
		energy += body.linear_velocity.length_squared()

	# Yerde yatarken fizik motoru ara sira minik bir temas sarsintisi uretiyor.
	# Onceden tek bir sarsinti sayaci sifirliyordu ve karakter hic kalkmiyordu;
	# artik sayac sadece yavasca geri sariyor.
	if energy < SETTLE_ENERGY:
		settle_timer += delta
	else:
		settle_timer = maxf(0.0, settle_timer - delta * 0.5)

	# Guvenlik: birakildiktan sonra ne olursa olsun bir sure icinde kalk
	if settle_timer > GETUP_DELAY or released_for > MAX_LYING_TIME:
		_begin_getup()


func _begin_getup() -> void:
	# Dustugu pozu eklem tabanli olarak kaydet: govde transformu + her uzvun
	# govdeye gore donusu. Gecis bu ikisini ayri ayri yumusatiyor.
	var body_xf: Transform3D = bodies["body"].global_transform
	getup_from_body = body_xf
	getup_from_local.clear()
	for limb in LIMBS.keys():
		var local: Basis = body_xf.basis.inverse() * bodies[limb].global_transform.basis
		getup_from_local[limb] = local.orthonormalized().get_rotation_quaternion()

	# Nereye dustuyse orada kalksin (bounds, main tarafindan dustugu ekrana gore
	# guncelleniyor)
	root_x = clampf(body_xf.origin.x, bounds.x, bounds.y)
	facing = 0.0
	facing_now = 0.0
	anim_state = "idle"
	getup_t = 0.0
	mode = Mode.GETTING_UP
	_set_frozen(true)


func _advance_getup(delta: float) -> void:
	getup_t = minf(1.0, getup_t + delta / GETUP_TIME)
	var k := ease(getup_t, -2.2)

	var target_body := _body_transform(0.0, 0.0)
	var from_q := getup_from_body.basis.orthonormalized().get_rotation_quaternion()
	var to_q := target_body.basis.get_rotation_quaternion()
	var body_xf := Transform3D(
		Basis(from_q.slerp(to_q, k)),
		getup_from_body.origin.lerp(target_body.origin, k),
	)

	var target_pose := _animated_pose(0.0)
	var local := {}
	for limb in LIMBS.keys():
		var to_limb := Basis.from_euler(target_pose[limb]).get_rotation_quaternion()
		local[limb] = (getup_from_local[limb] as Quaternion).slerp(to_limb, k)

	_apply_pose(local, body_xf)

	if getup_t >= 1.0:
		# Kalkis eklem tabanli ayakta pozda bitiyor; paketin pozu ondan birkac
		# piksel farkli, sicramasin diye kisa bir gecisle devraliyor.
		cem_blend = 0.0
		limb_speed = 0.0
		for part in bodies:
			cem_blend_from[part] = bodies[part].global_transform
		mode = Mode.ANIMATED
		anim_t = 0.0
		_set_state("idle", randf_range(1.5, 3.0))


# =====================================================================
# Teshis
# =====================================================================

## Her eklemde iki govdenin eklem noktalari arasindaki aciklik (piksel).
func joint_gaps() -> Dictionary:
	var out := {}
	for p in joint_probes:
		var pa: Vector3 = p[0].transform * p[1]
		var pb: Vector3 = p[2].transform * p[3]
		out[p[4]] = snappedf(pa.distance_to(pb) / PX, 0.01)
	return out
