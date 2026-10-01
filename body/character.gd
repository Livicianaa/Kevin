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

## Parcalar (piksel): boyut, ayakta merkez, skin UV koku (ic/dis katman), kutle.
## Ince (Alex) modelde kollar 3 px: _ready'de PARTS buna gore kuruluyor.
const PARTS_CLASSIC := {
	"head":      { "size": Vector3(8, 8, 8),  "center": Vector3(0, 28, 0),  "uv": Vector2(0, 0),   "overlay": Vector2(32, 0),  "mass": 4.0 },
	"body":      { "size": Vector3(8, 12, 4), "center": Vector3(0, 18, 0),  "uv": Vector2(16, 16), "overlay": Vector2(16, 32), "mass": 10.0 },
	"right_arm": { "size": Vector3(4, 12, 4), "center": Vector3(-6, 18, 0), "uv": Vector2(40, 16), "overlay": Vector2(40, 32), "mass": 2.5 },
	"left_arm":  { "size": Vector3(4, 12, 4), "center": Vector3(6, 18, 0),  "uv": Vector2(32, 48), "overlay": Vector2(48, 48), "mass": 2.5 },
	"right_leg": { "size": Vector3(4, 12, 4), "center": Vector3(-2, 6, 0),  "uv": Vector2(0, 16),  "overlay": Vector2(0, 32),  "mass": 4.0 },
	"left_leg":  { "size": Vector3(4, 12, 4), "center": Vector3(2, 6, 0),   "uv": Vector2(16, 48), "overlay": Vector2(0, 48),  "mass": 4.0 },
}

var PARTS := PARTS_CLASSIC.duplicate(true)

const Settings := preload("res://settings.gd")
## Menuden gelen ayarlar (add_child'dan ONCE atanir)
var slim := false
var skin_path := "res://skins/totem.png"
var walk_factor := 1.0
var emote_factor := 1.0
var look_enabled := true
var wall_sit_enabled := true
var fun_enabled := true

## Uzuvlar: govdeye baglandigi eklem (piksel, ayakta) ve fizikteki koni acisi (derece)
const LIMBS := {
	"head":      { "joint": Vector3(0, 24, 0),  "swing": 32.0 },
	"right_arm": { "joint": Vector3(-5, 23, 0), "swing": 160.0 },
	"left_arm":  { "joint": Vector3(5, 23, 0),  "swing": 160.0 },
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

enum Mode { ANIMATED, RAGDOLL, GETTING_UP, LED, MENU }

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
var walk_stall := 0.0
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
## Kalkis zaman cizelgesi: [[saniye, govde transformu, {uzuv: Quaternion}], ...]
var getup_keys := []
var getup_time := 0.0
var hard_fall := false
var getup_lift := 0.0

## Tutan el (main her karede gunceller). held_part "" = tutulmuyor.
var held_part := ""
var hold_point := Vector3.ZERO
var muscle_t := 0.0

## Sendeleme (LED): ayaktayken yavasca cekilince ragdoll yerine dengesi
## bozulmus gibi cekilen yone yuruyor. Hizli ya da yukari cekilince ragdoll.
## livi: "kendini ne kadar az birakirsa o kadar iyi; kuvvet uygulamadikca
## salmasina gerek yok". Esikler yuksek: ancak gercekten kaldirinca/savurunca.
const LED_LIFT := 1.1
const LED_MAX_PULL := 2.6
const LED_MAX_MOUSE_SPEED := 14.0
## Yukari cekince once parmak uclarinda yukseliyor (en fazla, birim)
const LED_TIPTOE := 0.22
var led_part := ""
var led_local := Vector3.ZERO
var led_target := Vector3.ZERO
var led_lean := 0.0
var led_speed := 0.0
var led_rise := 0.0

## Menu: karakter ekranin ortasina ucuyor, kullanici surukleyerek donduruyor
var menu_yaw := 0.0
var menu_lift := 0.0


func _ready() -> void:
	if slim:
		for arm in ["right_arm", "left_arm"]:
			PARTS[arm].size = Vector3(3, 12, 4)
			PARTS[arm].center.x = -5.5 if arm == "right_arm" else 5.5
	skin_texture = Settings.load_skin(skin_path)
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
	_load_getup_clip()


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
	if (mode != Mode.ANIMATED and mode != Mode.MENU) or not emotes.has(emote_name):
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
	# Dis katman sadece deride o bolge doluysa: bos katman kutusu hicbir sey
	# gostermeden kenar cizgisi uretiyordu
	if _overlay_used(spec.size, spec.overlay):
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


## Skin'i canli degistir (model ve boyut degisikligi yeniden kurulum ister)
func set_skin(path: String) -> void:
	skin_path = path
	skin_texture = Settings.load_skin(path)
	for b in bodies.values():
		for child in b.get_children():
			if child is MeshInstance3D and child.material_override:
				child.material_override.albedo_texture = skin_texture


func _overlay_used(px_size: Vector3, uv: Vector2) -> bool:
	var img := skin_texture.get_image()
	var w := int(2 * (px_size.x + px_size.z))
	var h := int(px_size.y + px_size.z)
	for y in range(int(uv.y), mini(int(uv.y) + h, img.get_height())):
		for x in range(int(uv.x), mini(int(uv.x) + w, img.get_width())):
			if img.get_pixel(x, y).a > 0.5:
				return true
	return false


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
		# Kenar pikselleri komsu doku bolgesini okumasin (donen kutunun kenarinda
		# ince renk cizgileri cikiyordu): yuzun UV'si icten biraz kirpiliyor
		var r: Rect2 = (face[2] as Rect2).grow(-0.03)
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
	if mode == Mode.LED:
		target_speed = led_speed
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

	# Emote oynarken Fresh Animations'in idle hareketi (govde salinimi, bacak ve
	# kol noktalarinin kaymasi) emote'un ustune biniyordu: oturunca titreme ve
	# kopukluk. Emote suresince vanilla poza geri cekiliyor.
	var vanilla := pose.duplicate()
	if cem:
		cem.apply(pose, {
		"age": cem_age, "time": cem_age / 20.0, "frame_time": delta,
		"limb_swing": limb_swing, "limb_speed": limb_speed,
		"move_forward": 1.0 if anim_state == "walk" else 0.0,
		"is_on_ground": 1.0, "id": 7.0, "health": 20.0, "max_health": 20.0,
	})

	var root := Transform3D(Basis(Vector3.UP, facing_now), Vector3(root_x, ground_y + menu_lift, 0))
	if mode == Mode.LED:
		root = root * Transform3D(Basis(Vector3.RIGHT, led_lean), Vector3(0, led_rise, 0))
	if emote:
		for k in pose:
			pose[k] = lerpf(pose[k], vanilla.get(k, 0.0), emote_weight)
		root = root * _whole_body(emote.apply(pose, emote_t, emote_weight))
	if cem_blend < 1.0:
		cem_blend = minf(1.0, cem_blend + delta / CEM_BLEND_TIME)
	var k := ease(cem_blend, -2.0)
	for part in CEM_PIVOT:
		var xf := root * _cem_part_transform(part, pose)
		if k < 1.0 and cem_blend_from.has(part):
			xf = (cem_blend_from[part] as Transform3D).interpolate_with(xf, k)
		bodies[part].global_transform = xf
	if mode == Mode.LED and led_part.ends_with("arm"):
		_reach_arm(led_part, led_target)


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
			# Hedef her karede sinirin icinde: sinir sonradan birazcik degisince
			# hedef disarida kaliyor, Kevin kenarda sonsuza kadar yerinde
			# yuruyordu.
			walk_target = clampf(walk_target, bounds.x, bounds.y)
			var dir := signf(walk_target - root_x)
			facing = dir * FACE_SIDE
			var before := root_x
			# Once yana don, sonra yuru
			if absf(facing_now - facing) < 0.05:
				root_x = clampf(root_x + dir * WALK_SPEED * delta * (limb_speed / CEM_WALK_LIMB_SPEED), bounds.x, bounds.y)
			# Emniyet: ilerleyemiyorsa (bir seye takildi) vazgec
			walk_stall = walk_stall + delta if absf(root_x - before) < 0.0001 and limb_speed > 0.3 else 0.0
			if walk_stall > 0.6 or absf(walk_target - root_x) < 0.01 or dir == 0.0 or (dir > 0 and root_x >= walk_target) or (dir < 0 and root_x <= walk_target):
				if walk_stall <= 0.6:
					root_x = walk_target
				walk_stall = 0.0
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
	var e := emote_factor
	var pool := ""
	if roll < 0.08 * e:
		pool = "idle"
	elif roll < 0.13 * e:
		pool = "fun" if fun_enabled else ""
	elif roll < 0.15 * e:
		pool = "rest"
	elif roll < 0.18 * e and wall_sit_enabled:
		_go_wall_sit()
		return
	if pool != "":
		var name := _random_emote(pool)
		if name != "sit_lean_wall" and name != "" and play_emote(name):
			return
	if randf() < clampf(0.8 * walk_factor, 0.0, 0.97):
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
	if look_enabled and attention_left <= 0.0 and attention_cooldown <= 0.0 and mouse_activity > 1.2:
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


func enter_menu() -> void:
	emote = null
	emote_facing = NAN
	after_walk = ""
	menu_yaw = facing_now
	anim_state = "idle"
	mode = Mode.MENU


func exit_menu() -> void:
	menu_lift = 0.0
	if mode == Mode.MENU:
		mode = Mode.ANIMATED
		_set_state("idle", randf_range(0.8, 1.6))


## Sendeleme basladi: part'in bu yerel noktasindan tutuldu
func start_led(part: String, local_point: Vector3) -> void:
	emote = null
	emote_facing = NAN
	after_walk = ""
	led_part = part
	led_local = local_point
	led_lean = 0.0
	led_speed = 0.0
	led_rise = 0.0
	mode = Mode.LED


func end_led() -> void:
	if mode == Mode.LED:
		mode = Mode.ANIMATED
		_set_state("idle", randf_range(0.8, 1.6))
	led_part = ""


func led_grab_point() -> Vector3:
	return bodies[led_part].global_transform * led_local


## Tutan el hedefi (dunya) ve farenin hizi. true: artik ragdoll'a gec.
func led_update(target: Vector3, mouse_speed: float) -> bool:
	led_target = target
	var pull := target - led_grab_point()
	return pull.y > LED_LIFT or pull.length() > LED_MAX_PULL or mouse_speed > LED_MAX_MOUSE_SPEED


func _led_step(delta: float) -> void:
	anim_t += delta
	var pull := led_target - led_grab_point()
	var vx := clampf(pull.x * 4.0, -2.2, 2.2)
	root_x = clampf(root_x + vx * delta, bounds.x, bounds.y)
	if absf(vx) > 0.25:
		facing = signf(vx) * FACE_SIDE
	facing_now = move_toward(facing_now, facing, TURN_SPEED * delta)
	# Adimlar cekme hizina gore; govde cekilen yone egiliyor
	led_speed = clampf(absf(vx) / 2.2, 0.0, 1.0) * 0.7
	var lean_target := clampf(absf(pull.x) * 0.5, 0.0, 0.4) if absf(facing_now) > 0.5 else 0.0
	led_lean = lerpf(led_lean, lean_target, minf(1.0, delta * 6.0))
	led_rise = lerpf(led_rise, clampf(pull.y * 0.35, 0.0, LED_TIPTOE), minf(1.0, delta * 8.0))
	attention_left = 0.5
	_update_look(delta)


## Kolu dunyadaki bir noktaya uzat (omuzdan)
func _reach_arm(arm: String, world_point: Vector3) -> void:
	var body_xf: Transform3D = bodies["body"].global_transform
	var joint: Vector3 = body_xf * ((LIMBS[arm].joint - BODY_REST_PX) * PX)
	var d := world_point - joint
	if d.length() < 0.05:
		return
	var basis := Basis(Quaternion(Vector3.DOWN, d.normalized()))
	var center_from_joint: Vector3 = (PARTS[arm].center - LIMBS[arm].joint) * PX
	bodies[arm].global_transform = Transform3D(basis, joint + basis * center_from_joint)


func start_ragdoll() -> void:
	led_part = ""
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
		Mode.LED:
			_led_step(delta)
			_cem_step(delta)
		Mode.MENU:
			anim_t += delta
			if emote:
				emote_t += delta
				if emote.finished(emote_t) or (emote.looped and emote_t >= emote_until):
					emote = null
			facing = menu_yaw
			facing_now = menu_yaw
			_update_look(delta)
			_cem_step(delta)


func _update_ragdoll(delta: float) -> void:
	muscle_t += delta
	_apply_muscles()
	if held_part != "":
		settle_timer = 0.0
		released_for = 0.0
		return

	released_for += delta
	# Ayaklarinin ustune dustu: yikilmasin, comelip darbeyi alsin ve ayakta kalsin
	var body: RigidBody3D = bodies["body"]
	var bb := body.global_transform.basis.orthonormalized()
	if released_for > 0.1 and bb.y.y > 0.85 and body.linear_velocity.y > -1.0 and body.linear_velocity.length() < 3.0:
		var feet := minf(_part_bottom("right_leg"), _part_bottom("left_leg"))
		if feet - ground_y < 0.12:
			_begin_getup()
			return
	var energy := 0.0
	for part_body in bodies.values():
		energy += part_body.linear_velocity.length_squared()

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


# =====================================================================
# Kaslar: ragdoll ip gibi sarkmasin. Her uzuv govdeye gore bir hedef donuse
# yaylı motorla (PD tork) cekiliyor; hedef ve guc duruma gore degisiyor.
# livi: "tutunca kendini tam salmasin, carpinca pat diye carpmasin, kafasini
# korusun, tutunca itmeye calissin".
# =====================================================================

const MUSCLE_K := {"head": 160.0, "right_arm": 150.0, "left_arm": 150.0, "right_leg": 240.0, "left_leg": 240.0}
const MUSCLE_D := {"head": 12.0, "right_arm": 15.0, "left_arm": 15.0, "right_leg": 24.0, "left_leg": 24.0}
const MUSCLE_MAX := {"head": 30.0, "right_arm": 45.0, "left_arm": 45.0, "right_leg": 70.0, "left_leg": 70.0}
const SHOULDER_OFFSET := {"right_arm": -1.0, "left_arm": 1.0}


func _apply_muscles() -> void:
	var body: RigidBody3D = bodies["body"]
	var bb := body.global_transform.basis.orthonormalized()
	var targets := {}
	var strength := {}

	if held_part != "":
		# Tutulan uzvun eklemi de kasli: gevsek birakinca govde oradan ip gibi
		# sallaniyordu ("kendini saliyor").
		match held_part:
			"head":
				targets["head"] = Quaternion.IDENTITY
				strength["head"] = 0.9
			"body":
				pass
			_:
				targets[held_part] = _point_limb_at(held_part, hold_point, bb)
				strength[held_part] = 0.7
		for arm in ["right_arm", "left_arm"]:
			if arm == held_part:
				continue
			if held_part.ends_with("leg"):
				# Bas asagi: kollar kafanin iki yaninda, kafayi koruyor
				var side := -1.0 if arm == "right_arm" else 1.0
				targets[arm] = _dir_quat(Vector3(side * 0.3, 0.9, 0.3))
				strength[arm] = 0.6
			else:
				var reach := _reach_toward(arm, hold_point, bb)
				if reach == Quaternion.IDENTITY:
					# El uzanilamayacak yerde: bosluga uzanmasin, gevsek
					targets[arm] = _rest_quats()[arm]
					strength[arm] = 0.15
				else:
					targets[arm] = reach
					strength[arm] = 0.95
		for leg in ["right_leg", "left_leg"]:
			if leg == held_part:
				continue
			var phase := 0.0 if leg == "right_leg" else PI
			targets[leg] = Quaternion.from_euler(Vector3(-0.2 + sin(muscle_t * 7.0 + phase) * 0.5, 0, 0))
			strength[leg] = 0.9
		if held_part != "head":
			targets["head"] = _look_quat(hold_point, bb)
			strength["head"] = 0.6
	else:
		var v := body.linear_velocity
		var airborne := v.length() > 1.5 or body.global_position.y - ground_y > 1.1
		if airborne and bb.y.y > 0.9:
			# Dik dusuyor: ayak ustune inmeye hazirlan, kollar denge icin acik.
			# Govdeyi dik tutan hafif bir "havada denge" torku da var.
			for limb in LIMBS:
				strength[limb] = 0.8
			targets["right_arm"] = _dir_quat(Vector3(-0.8, -0.45, 0.2))
			targets["left_arm"] = _dir_quat(Vector3(0.8, -0.45, 0.2))
			targets["right_leg"] = Quaternion.from_euler(Vector3(-0.05, 0, -0.06))
			targets["left_leg"] = Quaternion.from_euler(Vector3(0.05, 0, 0.06))
			targets["head"] = Quaternion.IDENTITY
			body.apply_torque(bb.y.cross(Vector3.UP) * 70.0 - body.angular_velocity * 8.0)
		elif airborne:
			var impact := _impact_soon(body, v)
			for limb in LIMBS:
				strength[limb] = 1.0 if impact else 0.6
			# Kollar yuzun onunde yukarida (kendi tarafinda, capraz degil),
			# bacaklar toplu, cene gogse
			targets["right_arm"] = _dir_quat(Vector3(-0.15, 0.8, 0.6))
			targets["left_arm"] = _dir_quat(Vector3(0.15, 0.8, 0.6))
			targets["right_leg"] = Quaternion.from_euler(Vector3(-0.6, 0, -0.05))
			targets["left_leg"] = Quaternion.from_euler(Vector3(-0.45, 0, 0.05))
			targets["head"] = Quaternion.from_euler(Vector3(0.35, 0, 0))
		else:
			# Yerde: tamamen gevsek degil, hafif tonus
			for limb in LIMBS:
				strength[limb] = 0.12
			targets = _rest_quats()

	for limb in LIMBS:
		var st: float = strength.get(limb, 0.0)
		if st <= 0.0 or not targets.has(limb):
			continue
		var lb: RigidBody3D = bodies[limb]
		var cur := (bb.inverse() * lb.global_transform.basis.orthonormalized()).get_rotation_quaternion()
		var err: Quaternion = (targets[limb] as Quaternion) * cur.inverse()
		if err.w < 0.0:
			err = -err
		var angle := err.get_angle()
		var axis := err.get_axis() if angle > 0.0001 else Vector3.ZERO
		var torque: Vector3 = bb * axis * angle * MUSCLE_K[limb] * st
		torque -= (lb.angular_velocity - body.angular_velocity) * MUSCLE_D[limb] * st
		torque = torque.limit_length(MUSCLE_MAX[limb] * st)
		lb.apply_torque(torque)
		body.apply_torque(-torque)


func _rest_quats() -> Dictionary:
	var out := {}
	var rest := _animated_pose(0.0)
	for limb in LIMBS:
		out[limb] = Quaternion.from_euler(rest[limb])
	return out


## Uzvun (asagi bakan) ekseni govde uzayinda bu yone dönsün
func _dir_quat(local_dir: Vector3) -> Quaternion:
	return Quaternion(Vector3.DOWN, local_dir.normalized())


## Kolu noktaya uzat; kol kendi tarafinda/onde kalinca hedeften cok sapiyorsa
## (ulasilamaz) IDENTITY. Onceden bu durumda kol bosluga uzaniyordu.
func _reach_toward(arm: String, world_point: Vector3, bb: Basis) -> Quaternion:
	var joint: Vector3 = (bodies["body"] as RigidBody3D).global_transform * ((LIMBS[arm].joint - BODY_REST_PX) * PX)
	var d := world_point - joint
	if d.length() < 0.05:
		return Quaternion.IDENTITY
	var want: Vector3 = (bb.inverse() * d).normalized()
	var got := _point_limb_at(arm, world_point, bb) * Vector3.DOWN
	if want.angle_to(got) > deg_to_rad(35.0):
		return Quaternion.IDENTITY
	return _point_limb_at(arm, world_point, bb)


func _point_limb_at(limb: String, world_point: Vector3, bb: Basis) -> Quaternion:
	var joint: Vector3 = (bodies["body"] as RigidBody3D).global_transform * ((LIMBS[limb].joint - BODY_REST_PX) * PX)
	var d := world_point - joint
	if d.length() < 0.01:
		return _dir_quat(Vector3.DOWN)
	var ld: Vector3 = (bb.inverse() * d).normalized()
	# Kol kendi tarafinda ve govdenin onunde kalsin: capraz uzaninca kollar
	# ic ice giriyor, kafadan tutunca kendini bogazliyormus gibi duruyordu.
	if limb == "right_arm":
		ld.x = minf(ld.x, 0.1)
	elif limb == "left_arm":
		ld.x = maxf(ld.x, -0.1)
	if limb.ends_with("arm"):
		ld.z = maxf(ld.z, 0.15)
	return _dir_quat(ld)


func _look_quat(world_point: Vector3, bb: Basis) -> Quaternion:
	var local: Vector3 = bb.inverse() * (world_point - bodies["head"].global_position)
	var yaw := clampf(atan2(local.x, local.z), -0.9, 0.9)
	var pitch := clampf(-atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.5)
	return Quaternion.from_euler(Vector3(pitch, yaw, 0))


## Hizla bir seye (zemin/duvar) carpmak uzere mi?
func _impact_soon(body: RigidBody3D, v: Vector3) -> bool:
	if v.length() < 2.0:
		return false
	var from := body.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + v * 0.3)
	q.exclude = bodies.values().map(func(b): return b.get_rid())
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Kalkis pozlari arasinda uzuvlar zemine gomuluyordu: gomulen varsa butun
## vucut o kadar yukari. Eller/dizler zemine degiyor ama batmiyor.
## Kaldirma aninda ama inis yavas: her karede farkli miktarda kaldirmak
## karakteri "zipliyormus" gibi gosteriyordu.
func _keep_above_ground(delta: float) -> void:
	var lowest := INF
	for part in bodies:
		lowest = minf(lowest, _part_bottom(part))
	# Gomulme aninda duzeltiliyor; havada kalma (oranlar insandan farkli)
	# yavasca asagi cekiliyor
	# Yukari da asagi da hiz sinirli: aninda kaldirmak "ziplama" gibi duruyordu
	var need := ground_y - lowest
	getup_lift = move_toward(getup_lift, need, delta * (2.5 if need > getup_lift else 1.2))
	if getup_lift != 0.0:
		for b in bodies.values():
			b.global_position.y += getup_lift


func _num(v) -> float:
	return v if (v is float or v is int) else 0.0


# =====================================================================
# Hazir kalkis animasyonu (Quaternius LayToIdle, CC0). livi: "duzken ayaga
# kalkmayi yapamiyorsun, hazir bir animasyonu referans al". Elle yazilan
# anahtar pozlar ziplama, capraz bacak, havada eller uretiyordu.
# Insan iskeletinden sadece govde acisi, omuz->el, kalca->ayak ve kafa yonu
# aliniyor (dirsek/diz yok, Minecraft modeli gibi).
# =====================================================================

const GETUP_CLIP_PATH := "res://anim/laytoidle.json"
## Animasyon hizi (1 = orijinal 1.53 sn)
const GETUP_CLIP_SPEED := 0.72
## Kalkis boyunca profile donme suresi (klip orani)
const GETUP_TURN := 0.35

var getup_clip := []
var clip_len := 0.0


func _load_getup_clip() -> void:
	if not FileAccess.file_exists(GETUP_CLIP_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(GETUP_CLIP_PATH))
	if not (data is Dictionary):
		return
	var frames: Array = data.frames
	var v := func(f: Dictionary, k: String) -> Vector3: return Vector3(f[k][0], f[k][1], f[k][2])
	var scale := 1.5 / float(frames[frames.size() - 1].neck_01[1])
	for f in frames:
		var pel: Vector3 = v.call(f, "pelvis")
		var neck: Vector3 = v.call(f, "neck_01")
		var y_up := (neck - pel).normalized()
		var x_left: Vector3 = v.call(f, "upperarm_l") - v.call(f, "upperarm_r")
		x_left = (x_left - y_up * x_left.dot(y_up)).normalized()
		var basis := Basis(x_left, y_up, x_left.cross(y_up)).orthonormalized()
		var inv := basis.inverse()
		var local := {
			"right_arm": _dir_quat(inv * (v.call(f, "hand_r") - v.call(f, "upperarm_r"))),
			"left_arm": _dir_quat(inv * (v.call(f, "hand_l") - v.call(f, "upperarm_l"))),
			"right_leg": _dir_quat(inv * (v.call(f, "foot_r") - v.call(f, "thigh_r"))),
			"left_leg": _dir_quat(inv * (v.call(f, "foot_l") - v.call(f, "thigh_l"))),
			"head": Quaternion(Vector3.UP, (inv * (v.call(f, "Head") - neck)).normalized()),
		}
		getup_clip.append({"basis": basis, "center": (pel + neck) * 0.5 * scale, "local": local})
	clip_len = float(data.length) / GETUP_CLIP_SPEED


func _begin_clip_getup(body_xf: Transform3D, bb: Basis, start_local: Dictionary, h3: Vector3, supine: bool) -> void:
	# Klip sirt ustu basliyor, sonunda ayaklarin tarafina bakiyor. Klipte kafa
	# -z'de, sonda yuz +z'de: bizde +z -> ayak yonu (-h3).
	var fwd := -h3
	var face0 := atan2(fwd.x, fwd.z)
	var face1 := (1.0 if fwd.x >= 0.0 else -1.0) * FACE_SIDE
	var c0: Vector3 = getup_clip[0].center
	var anchor := Vector3(body_xf.origin.x, 0, body_xf.origin.z)
	var n := getup_clip.size()
	var frame_dt := clip_len / float(n - 1)

	var keys := []
	for i in n:
		var fr: Dictionary = getup_clip[i]
		var frac := float(i) / float(n - 1)
		# Klip bastan profilde: derinlik yonunde (kameraya dogru) yatarken
		# yuvarlanma/kalkis onden bakinca masa gibi tuhaf sekiller cikariyordu.
		# Donus, dustugu pozdan ilk kareye gecerken yerde yapiliyor.
		var face := face1
		var yaw := Basis(Vector3.UP, face)
		var d: Vector3 = fr.center - c0
		var off := yaw * Vector3(d.x, 0, d.z)
		var origin := Vector3(anchor.x + off.x, ground_y + fr.center.y, (anchor.z + off.z) * (1.0 - frac))
		origin.x = lerpf(origin.x, clampf(origin.x, bounds.x, bounds.y), frac)
		keys.append([i * frame_dt, Transform3D(yaw * fr.basis, origin), fr.local])

	# Dustugu pozdan klibin ilk karesine (yerde yana donerek); yuz ustuyse once
	# yan donup sirt ustune
	var lead := 0.6
	var start: Array = [[0.0, Transform3D(bb, body_xf.origin), start_local]]
	if not supine:
		# Yuz ustunden sirt ustune: duz yuz ustu -> yan -> sirt ustu, ~1 sn,
		# yerde kalarak. Onceden 0.4 sn'de donup kollar altta kalinca bir anda
		# yukari "zipliyordu". Yanda kollar gogsun onunde (altina girmesin).
		var first: Transform3D = keys[0][1]
		var arms_front := {
			"right_arm": _dir_quat(Vector3(-0.15, -0.35, 1.0)),
			"left_arm": _dir_quat(Vector3(0.15, -0.35, 1.0)),
			"right_leg": keys[0][2]["right_leg"], "left_leg": keys[0][2]["left_leg"],
			"head": Quaternion.IDENTITY,
		}
		var flat := Transform3D(first.basis * Basis(Vector3.UP, PI), first.origin)
		var side := Transform3D(first.basis * Basis(Vector3.UP, PI / 2.0), first.origin)
		# Yuz ustu duzken kollar govdenin yaninda (ayak yonunde): "gogsun onu"
		# burada zemin; kollar zemine uzaninca vucut kol boyu havaya kalkiyordu
		var arms_side := arms_front.duplicate()
		arms_side["right_arm"] = _dir_quat(Vector3(-0.12, -1.0, 0.0))
		arms_side["left_arm"] = _dir_quat(Vector3(0.12, -1.0, 0.0))
		start.append([0.6, flat, arms_side])
		start.append([1.1, side, arms_front])
		lead = 1.55
	for k in keys:
		k[0] += lead
	getup_keys = start + keys

	if OS.is_debug_build():
		print("[kevin] kalkis: klip (%s)" % ("sirt ustu" if supine else "yuz ustu"))
	getup_time = 0.0
	getup_lift = 0.0
	hard_fall = true
	var last_key: Transform3D = getup_keys[getup_keys.size() - 1][1]
	root_x = clampf(last_key.origin.x, bounds.x, bounds.y)
	facing = face1
	facing_now = face1
	anim_state = "idle"
	mode = Mode.GETTING_UP
	_set_frozen(true)


## Temas acisi (radyan, dikey asagidan; + geri): uzvun ucu tam zemine degsin.
## Govde egimi (lean, radyan, + one) ve govde merkez yuksekligi h (px).
func _contact_angle(kind: String, lean: float, h: float) -> float:
	var arm := kind.begins_with("g")
	# Omuz govde merkezinin 5 px ustunde, kalca 6 px altinda; uzuv 12 px
	var joint_h := h + 5.0 * cos(lean) if arm else h - 6.0 * cos(lean)
	var a := acos(clampf(joint_h / 12.0, -1.0, 1.0))
	return -a if kind.ends_with("f") else a


## Parcanin en alt noktasi (dunya y)
func _part_bottom(part: String) -> float:
	var b: RigidBody3D = bodies[part]
	var h: Vector3 = PARTS[part].size * PX * 0.5
	var lowest := INF
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				lowest = minf(lowest, (b.global_transform * Vector3(h.x * sx, h.y * sy, h.z * sz)).y)
	return lowest


## Kalkis anahtar kareleri. lean: govdenin one egimi (derece, + one / yuz
## asagi, - geriye / sirt ustu). h: govde merkezinin zeminden yuksekligi (px).
## dx: yuzun baktigi yone kayma (px). Uzuv acilari DUNYAYA gore (derece, dikey
## asagidan; + geriye, - one): kollar/bacaklar yere gercekten dayaniyor.
## livi: "sihirli sekilde geri ayaga kalkmasin, kolundan bacagindan destek alsin".
const GETUP_PLANS := {
	# Sirt ustu: bir yana donup o eli yere dayar, eline yaslanip dogrulur, diz
	# coker, tek ayagini basar, diger elini o dizine koyup iterek kalkar.
	# livi: "sag elinden destek aldi, bir ayagini yere basti, diger elini o
	# ayagina atti, ordan destek alip kalkti gibi olmasi lazim".
	# Temas degerleri (aci yerine): "gf"/"gb" el onde/arkada yerde, "kf" ayak
	# onde yerde, "kb" diz arkada yerde. Aci omuz/kalca yuksekliginden
	# hesaplaniyor; elle verilen acilarda eller havada kaliyordu.
	"supine": [
		{"t": 0.0, "lean": -90.0, "h": 2.2, "dx": 0.0, "rarm": -80.0, "larm": -80.0, "rleg": -88.0, "lleg": -86.0, "head": 0.0},
		{"t": 0.45, "lean": -80.0, "roll": 16.0, "h": 3.0, "dx": 0.5, "rarm": "gb", "larm": -60.0, "rleg": -88.0, "lleg": -84.0, "head": 0.4},
		{"t": 1.0, "lean": -35.0, "roll": 10.0, "h": 7.0, "dx": 3.0, "rarm": "gb", "larm": -40.0, "rleg": "kf", "lleg": "kf", "head": 0.25},
		{"t": 1.35, "lean": -28.0, "roll": 8.0, "h": 7.3, "dx": 3.2, "rarm": "gb", "larm": -35.0, "rleg": "kf", "lleg": "kf", "head": 0.2},
		{"t": 1.95, "lean": 45.0, "roll": -4.0, "h": 7.0, "dx": 4.5, "rarm": "gf", "larm": "gf", "rleg": "kf", "lleg": "kf", "head": 0.35},
		{"t": 2.55, "lean": 30.0, "roll": -3.0, "h": 12.0, "dx": 5.5, "rarm": -5.0, "larm": -40.0, "larmroll": 0.02, "rleg": "kf", "lleg": "kf", "head": 0.25},
		{"t": 3.1, "lean": 15.0, "roll": -1.0, "h": 15.5, "dx": 6.0, "rarm": 0.0, "larm": -25.0, "larmroll": 0.04, "rleg": "kf", "lleg": "kf", "head": 0.05},
		{"t": 3.6, "lean": 0.0, "h": 18.0, "dx": 6.0, "rarm": 0.0, "larm": 0.0, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
	],
	"prone": [
		{"t": 0.0, "lean": 90.0, "h": 2.2, "dx": 0.0, "rarm": 80.0, "larm": 80.0, "rleg": 88.0, "lleg": 86.0, "head": 0.0},
		{"t": 0.45, "lean": 88.0, "roll": -8.0, "h": 2.6, "dx": 0.0, "rarm": "gf", "larm": 70.0, "rleg": 88.0, "lleg": 86.0, "head": -0.3},
		{"t": 0.95, "lean": 65.0, "roll": -4.0, "h": 8.5, "dx": -1.0, "rarm": "gf", "larm": "gf", "rleg": "kb", "lleg": "kb", "head": -0.35},
		{"t": 1.3, "lean": 60.0, "roll": -3.0, "h": 8.7, "dx": -1.0, "rarm": "gf", "larm": "gf", "rleg": "kb", "lleg": "kb", "head": -0.25},
		{"t": 1.9, "lean": 45.0, "roll": 3.0, "h": 9.5, "dx": -2.0, "rarm": "gf", "larm": "gf", "rleg": "kb", "lleg": "kb", "head": 0.2},
		{"t": 2.5, "lean": 35.0, "roll": 2.0, "h": 12.0, "dx": -3.0, "rarm": -5.0, "larm": -20.0, "larmroll": 0.04, "rleg": "kb", "lleg": "kb", "head": 0.2},
		{"t": 3.05, "lean": 18.0, "roll": 1.0, "h": 15.2, "dx": -3.5, "rarm": 0.0, "larm": -10.0, "rleg": "kb", "lleg": "kb", "head": 0.05},
		{"t": 3.55, "lean": 0.0, "h": 18.0, "dx": -3.5, "rarm": 0.0, "larm": 0.0, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
	],
	# livi: "put gibi duruyor, dususu biraz soft olsun": derin comelme, kollar
	# denge icin acik, dogrulurken hafif geriye esneyip toparlanma
	"upright": [
		{"t": 0.0, "lean": 10.0, "roll": 8.0, "h": 16.5, "dx": 0.0, "arm": -20.0, "aroll": 0.6, "rleg": -10.0, "lleg": 8.0, "lroll": 0.25, "head": 0.05},
		{"t": 0.18, "lean": 24.0, "roll": -7.0, "h": 13.0, "dx": 0.3, "arm": -40.0, "aroll": 1.15, "rleg": -25.0, "lleg": 20.0, "lroll": 0.38, "head": 0.2},
		{"t": 0.45, "lean": 16.0, "roll": 8.0, "h": 13.8, "dx": 0.5, "arm": -30.0, "aroll": 0.95, "rleg": -15.0, "lleg": 10.0, "lroll": 0.3, "head": -0.1},
		{"t": 0.75, "lean": -4.0, "roll": -5.0, "h": 16.4, "dx": 0.5, "arm": -15.0, "aroll": 0.5, "rleg": -5.0, "lleg": 4.0, "lroll": 0.15, "head": 0.05},
		{"t": 1.05, "lean": 2.0, "roll": 2.0, "h": 17.6, "dx": 0.5, "arm": -5.0, "aroll": 0.25, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
		{"t": 1.35, "lean": 0.0, "h": 18.0, "dx": 0.5, "arm": 0.0, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
	],
}
## Kenara yakin dustuyse diz cokme sonrasi: kenara don, elleri duvara dayayip
## iterek kalk (livi: "ekranin kenarindaysa duvardan destek alabilir").
## t: diz cokme karesinden sonraki sure.
const GETUP_WALL_TAIL := [
	{"t": 0.5, "lean": 20.0, "h": 12.8, "arm": -110.0, "rleg": 45.0, "lleg": 50.0, "head": -0.25},
	{"t": 1.0, "lean": 12.0, "h": 15.0, "arm": -95.0, "rleg": -30.0, "lleg": 25.0, "head": -0.1},
	{"t": 1.5, "lean": 4.0, "h": 17.4, "arm": -70.0, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
	{"t": 1.9, "lean": 0.0, "h": 18.0, "arm": 0.0, "rleg": 0.0, "lleg": 0.0, "head": 0.0},
]
## Duvar destegi icin kenara en fazla bu kadar yakin (birim)
const WALL_NEAR := 0.9
## Duvara dayanirken govdenin duvardan uzakligi (birim)
const WALL_STAND_OFF := 0.5

## Dustugu pozdan planin ilk karesine (yere duzgun yatis) gecis
const GETUP_SETTLE := 0.45


func _begin_getup() -> void:
	var body_xf: Transform3D = bodies["body"].global_transform
	var bb := body_xf.basis.orthonormalized()
	var start_local := {}
	for limb in LIMBS.keys():
		var local: Basis = bb.inverse() * bodies[limb].global_transform.basis.orthonormalized()
		start_local[limb] = local.get_rotation_quaternion()

	# Kafa hangi yonde (yatay duzlemde, derinlik dahil), yuz yukari mi asagi mi?
	# Onceden hep profile cevriliyordu: kameraya donuk yatan karakter kalkarken
	# bir anda yana "isinlaniyordu".
	var h3: Vector3 = bodies["head"].global_position - body_xf.origin
	h3.y = 0.0
	if h3.length() < 0.05:
		h3 = Vector3(bb.y.x, 0, bb.y.z)
	if h3.length() < 0.05:
		h3 = Vector3.RIGHT
	h3 = h3.normalized()
	var supine := bb.z.y >= 0.0
	# Sadece gercekten dik (ayaklarinin ustunde) ise comelip kalk; 60 dereceye
	# kadar egik yatan govde "dik" sayilip direk gibi kalkiyordu.
	var upright := bb.y.y > 0.85
	if not upright and not getup_clip.is_empty():
		_begin_clip_getup(body_xf, bb, start_local, h3, supine)
		return
	var plan_name := "upright" if upright else ("supine" if supine else "prone")
	var plan: Array = (GETUP_PLANS[plan_name] as Array).duplicate()
	if OS.is_debug_build():
		print("[kevin] kalkis: ", plan_name)

	# Kenara yakin mi? Oyleyse son iki kare (tek diz, ayakta) yerine duvar destegi
	var wall_dir := 0.0
	if not upright:
		if body_xf.origin.x - bounds.x < WALL_NEAR:
			wall_dir = -1.0
		elif bounds.y - body_xf.origin.x < WALL_NEAR:
			wall_dir = 1.0
	var wall_x := (bounds.x - 0.45) if wall_dir < 0.0 else (bounds.y + 0.45)
	if wall_dir != 0.0:
		plan.resize(plan.size() - 2)
		var base_t: float = plan[plan.size() - 1].t
		var base_key: Dictionary = plan[plan.size() - 1]
		for n in GETUP_WALL_TAIL.size():
			var k: Dictionary = GETUP_WALL_TAIL[n].duplicate()
			k.t = base_t + k.t
			k.wall = true
			# Bacaklar ayni yonde kalsin (one/arkaya gecip capraz olmasin),
			# son karede dik
			if n < GETUP_WALL_TAIL.size() - 1:
				k.rleg = base_key.get("rleg", 0.0)
				k.lleg = base_key.get("lleg", 0.0)
			plan.append(k)
	# Sirt ustu kalkan ayaklarinin tarafina, yuz ustu kalkan kafasinin tarafina bakar
	var fwd := -h3 if supine else h3
	if upright:
		fwd = Vector3(bb.z.x, 0, bb.z.z).normalized() if Vector2(bb.z.x, bb.z.z).length() > 0.05 else Vector3.BACK
	var face := atan2(fwd.x, fwd.z)
	# Yattigi yonden baslayip ilk ~0.9 sn icinde profile donuyor: kameraya dogru
	# uzanmis yatarken oturma/diz cokme derinlikte kaliyor, onden bakinca
	# "direk gibi" kalkiyormus gibi gorunuyordu. Birden donunce de isinlaniyordu.
	var face_profile := (1.0 if fwd.x >= 0.0 else -1.0) * FACE_SIDE

	var x0 := body_xf.origin.x
	var z0 := body_xf.origin.z
	var settle := GETUP_SETTLE if not upright else 0.12
	getup_keys = [[0.0, Transform3D(bb, body_xf.origin), start_local]]
	var face_wall := wall_dir * FACE_SIDE
	var mirror := randf() < 0.5
	for key in plan:
		var lean := deg_to_rad(key.lean)
		var on_wall: bool = key.get("wall", false)
		var face_k := face if upright else lerp_angle(face, face_profile, clampf(key.t / 0.9, 0.0, 1.0))
		if on_wall:
			face_k = face_wall
		var basis := Basis(Vector3.UP, face_k) * Basis(Vector3.RIGHT, lean) \
			* Basis(Vector3.BACK, deg_to_rad(key.get("roll", 0.0)) * (-1.0 if mirror else 1.0))
		var fwd_k := Vector3(sin(face_k), 0, cos(face_k))
		var along: float = key.t / plan[plan.size() - 1].t
		var origin: Vector3 = Vector3(x0, ground_y + key.h * PX, z0 * (1.0 - along)) + fwd_k * float(key.get("dx", 0.0)) * PX
		origin.x = lerpf(origin.x, clampf(origin.x, bounds.x, bounds.y), along)
		if on_wall:
			origin.x = wall_x - wall_dir * WALL_STAND_OFF
		var local := {}
		# Rastgele ayna: bazen sol elden, bazen sag elden baslasin
		var rk := "l" if mirror else "r"
		var lk := "r" if mirror else "l"
		var contact := {"head": "", "right_arm": "", "left_arm": "", "right_leg": "", "left_leg": ""}
		for pair in [["right_arm", rk + "arm"], ["left_arm", lk + "arm"], ["right_leg", rk + "leg"], ["left_leg", lk + "leg"]]:
			if key.get(pair[1]) is String:
				contact[pair[0]] = key[pair[1]]
		for limb in LIMBS.keys():
			var world_a := 0.0
			var roll := 0.0
			match limb:
				"right_arm":
					world_a = _num(key.get(rk + "arm", key.get("arm", 0.0)))
					roll = -key.get(rk + "armroll", key.get("aroll", 0.12))
				"left_arm":
					world_a = _num(key.get(lk + "arm", key.get("arm", 0.0)))
					roll = key.get(lk + "armroll", key.get("aroll", 0.12))
				"right_leg":
					world_a = _num(key.get(rk + "leg", 0.0))
					roll = -key.get("lroll", 0.04)
				"left_leg":
					world_a = _num(key.get(lk + "leg", 0.0))
					roll = key.get("lroll", 0.04)
			var e := Vector3(deg_to_rad(world_a) - lean, 0, roll)
			if contact[limb] != "":
				e.x = _contact_angle(contact[limb], lean, key.h) - lean
			if limb == "head":
				e = Vector3(key.head, 0, 0)
			local[limb] = Quaternion.from_euler(e)
		# Ilk karede uzuvlar dustukleri pozdan tam duzlesmesin (tahta gibi
		# duzlesip oyle kalkiyordu): yari yolda kalsin
		if getup_keys.size() == 1:
			for limb in LIMBS.keys():
				local[limb] = (start_local[limb] as Quaternion).slerp(local[limb], 0.45)
		getup_keys.append([settle + key.t, Transform3D(basis, origin), local])

	getup_time = 0.0
	getup_lift = 0.0
	hard_fall = not upright
	var last_key: Transform3D = getup_keys[getup_keys.size() - 1][1]
	root_x = clampf(last_key.origin.x, bounds.x, bounds.y)
	if wall_dir != 0.0:
		face = face_wall
	elif not upright:
		face = face_profile
	facing = face
	facing_now = face
	anim_state = "idle"
	mode = Mode.GETTING_UP
	_set_frozen(true)


func _advance_getup(delta: float) -> void:
	getup_time += delta
	var last: Array = getup_keys[getup_keys.size() - 1]
	var t := minf(getup_time, last[0])
	var i := 0
	while i < getup_keys.size() - 2 and t > getup_keys[i + 1][0]:
		i += 1
	var a: Array = getup_keys[i]
	var b: Array = getup_keys[i + 1]
	var span: float = b[0] - a[0]
	var k := clampf((t - a[0]) / maxf(0.001, span), 0.0, 1.0)
	# Sik kareli klipte duz; seyrek anahtar pozlarda yumusak
	if span > 0.1:
		k = smoothstep(0.0, 1.0, k)

	var xa: Transform3D = a[1]
	var xb: Transform3D = b[1]
	var body_xf := Transform3D(
		Basis(xa.basis.get_rotation_quaternion().slerp(xb.basis.get_rotation_quaternion(), k)),
		xa.origin.lerp(xb.origin, k),
	)
	var local := {}
	for limb in LIMBS.keys():
		local[limb] = (a[2][limb] as Quaternion).slerp(b[2][limb], k)
	_apply_pose(local, body_xf)
	_keep_above_ground(delta)

	if getup_time >= last[0]:
		# Kalkis eklem tabanli ayakta pozda bitiyor; paketin pozu ondan birkac
		# piksel farkli, sicramasin diye kisa bir gecisle devraliyor.
		cem_blend = 0.0
		limb_speed = 0.0
		for part in bodies:
			cem_blend_from[part] = bodies[part].global_transform
		mode = Mode.ANIMATED
		anim_t = 0.0
		_set_state("idle", randf_range(1.0, 2.0))
		# Sert dustuyse ara sira sersemlemis gibi kafasini sallasin
		if hard_fall and randf() < 0.5:
			play_emote("shake", 1.6)


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
