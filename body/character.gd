extends Node3D
## Minecraft karakteri.
##
## Uc hali var:
##  ANIMATED   - ayakta; prosedurel animasyonla yuruyor, bakiniyor, fareye bakiyor
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
const WALK_SPEED := 1.1
const TURN_SPEED := 6.0
const FACE_SIDE := 0.95
const GETUP_DELAY := 1.0
const GETUP_TIME := 0.9
const SETTLE_ENERGY := 0.12
const MAX_LYING_TIME := 4.0

enum Mode { ANIMATED, RAGDOLL, GETTING_UP }

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

# Fareye bakma (main her karede fare konumunu dunya birimi olarak veriyor)
var look_point := Vector3(0, 3, 0)
var look_yaw := 0.0
var look_pitch := 0.0

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
	var origin := Vector3(root_x, BODY_REST_PX.y * PX + lift, 0)
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
# Animasyonlar (eski Electron surumunun poz motorundan)
# =====================================================================

const ARM_REST := PI * 0.02

func _animated_pose(t: float) -> Dictionary:
	var p := {
		"head": Vector3.ZERO,
		"right_arm": Vector3(0, 0, -ARM_REST),
		"left_arm": Vector3(0, 0, ARM_REST),
		"right_leg": Vector3.ZERO,
		"left_leg": Vector3.ZERO,
	}

	match anim_state:
		"idle":
			p.right_arm = Vector3(0, 0, -ARM_REST - cos(t * 2.0) * 0.03)
			p.left_arm = Vector3(0, 0, ARM_REST + cos(t * 2.0) * 0.03)
		"walk":
			var w := t * 8.0
			p.right_leg = Vector3(sin(w) * 0.55, 0, 0)
			p.left_leg = Vector3(-sin(w) * 0.55, 0, 0)
			p.right_arm = Vector3(-sin(w) * 0.5, 0, -ARM_REST)
			p.left_arm = Vector3(sin(w) * 0.5, 0, ARM_REST)
		"look_around":
			p.right_arm = Vector3(0, 0, -ARM_REST - cos(t * 2.0) * 0.03)
			p.left_arm = Vector3(0, 0, ARM_REST + cos(t * 2.0) * 0.03)

	# Kafa: bakinma animasyonu ya da fareye bakis (govdeye gore)
	var head_yaw := look_yaw
	var head_pitch := look_pitch
	if anim_state == "look_around":
		head_yaw = sin(t * 1.5) * 0.7
		head_pitch = sin(t * 0.8) * 0.12
	elif anim_state == "walk":
		head_yaw = sin(t * 2.0) * 0.12
		head_pitch = 0.0
	p.head = Vector3(head_pitch, head_yaw, 0)
	return p


func _walk_bob(t: float) -> float:
	if anim_state != "walk":
		return sin(t * 2.0) * 0.004
	return abs(sin(t * 8.0)) * 0.035


# =====================================================================
# Davranis (ayaktayken)
# =====================================================================

func _update_behaviour(delta: float) -> void:
	anim_t += delta
	state_timer -= delta

	match anim_state:
		"idle", "look_around":
			if state_timer <= 0.0:
				_choose_next()
		"walk":
			var dir := signf(walk_target - root_x)
			root_x += dir * WALK_SPEED * delta
			facing = dir * FACE_SIDE
			if (dir > 0 and root_x >= walk_target) or (dir < 0 and root_x <= walk_target):
				root_x = walk_target
				_set_state("idle", randf_range(2.0, 5.0))

	# Yurumuyorken izleyiciye (kameraya) don
	if anim_state != "walk":
		facing = 0.0
	facing_now = move_toward(facing_now, facing, TURN_SPEED * delta)
	root_x = clampf(root_x, bounds.x, bounds.y)

	_update_look(delta)


func _choose_next() -> void:
	var roll := randf()
	if roll < 0.55:
		var span := bounds.y - bounds.x
		walk_target = clampf(root_x + randf_range(-0.45, 0.45) * span, bounds.x + 0.4, bounds.y - 0.4)
		if absf(walk_target - root_x) < 0.5:
			walk_target = clampf(root_x + 1.5 * (1 if randf() < 0.5 else -1), bounds.x + 0.4, bounds.y - 0.4)
		_set_state("walk", 0.0)
	elif roll < 0.8:
		_set_state("look_around", randf_range(2.5, 4.0))
	else:
		_set_state("idle", randf_range(2.0, 4.0))


func _set_state(state: String, duration: float) -> void:
	anim_state = state
	state_timer = duration


## Kafa fareye donuyor (govdeye gore, sinirli)
func _update_look(delta: float) -> void:
	var head_pos := Vector3(root_x, (LIMBS.head.joint.y + 4) * PX, 0)
	var to := look_point - head_pos
	var target_yaw := clampf(atan2(to.x, 3.0) - facing_now, -0.9, 0.9)
	var target_pitch := clampf(-atan2(to.y, 3.0), -0.5, 0.45)
	look_yaw = lerpf(look_yaw, target_yaw, minf(1.0, delta * 5.0))
	look_pitch = lerpf(look_pitch, target_pitch, minf(1.0, delta * 5.0))


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
			_apply_pose(_animated_pose(anim_t), _body_transform(_walk_bob(anim_t), 0.0))
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
