extends Node3D
## Minecraft karakteri: 6 rijit govde, eklemlerle bagli, Godot'nun fizik motoruyla.
##
## Normalde ayakta durur (govdeler dondurulmus). Bir uzvundan tutulunca fizik
## devralir: tutulan nokta farede kalir, gerisi yercekimiyle sarkar ve fare
## hareketinden ivme alir. Birakilinca duser, sonra ayaga kalkar.

const PX := 1.0 / 16.0
const SKIN_SIZE := 64.0

## Parca tanimlari (piksel): boyut, ayakta merkez konumu, skin UV koku (ic/dis katman), kutle
const PARTS := {
	"head":      { "size": Vector3(8, 8, 8),  "center": Vector3(0, 28, 0),  "uv": Vector2(0, 0),   "overlay": Vector2(32, 0),  "mass": 4.0 },
	"body":      { "size": Vector3(8, 12, 4), "center": Vector3(0, 18, 0),  "uv": Vector2(16, 16), "overlay": Vector2(16, 32), "mass": 10.0 },
	"right_arm": { "size": Vector3(4, 12, 4), "center": Vector3(-6, 18, 0), "uv": Vector2(40, 16), "overlay": Vector2(40, 32), "mass": 2.5 },
	"left_arm":  { "size": Vector3(4, 12, 4), "center": Vector3(6, 18, 0),  "uv": Vector2(32, 48), "overlay": Vector2(48, 48), "mass": 2.5 },
	"right_leg": { "size": Vector3(4, 12, 4), "center": Vector3(-2, 6, 0),  "uv": Vector2(0, 16),  "overlay": Vector2(0, 32),  "mass": 4.0 },
	"left_leg":  { "size": Vector3(4, 12, 4), "center": Vector3(2, 6, 0),   "uv": Vector2(16, 48), "overlay": Vector2(0, 48),  "mass": 4.0 },
}

## Eklemler (piksel): hangi iki parca, dunya noktasi, koni acisi (derece)
const JOINTS := [
	["body", "head",      Vector3(0, 24, 0),  32.0],
	["body", "right_arm", Vector3(-5, 23, 0), 105.0],
	["body", "left_arm",  Vector3(5, 23, 0),  105.0],
	["body", "right_leg", Vector3(-2, 12, 0), 50.0],
	["body", "left_leg",  Vector3(2, 12, 0),  50.0],
]

const GETUP_DELAY := 1.6
const GETUP_TIME := 0.7

var bodies := {}
var rest_transforms := {}
var joint_probes := []
var skin_texture: Texture2D

var ragdoll_active := false
var settle_timer := 0.0
var getting_up := false
var getup_progress := 0.0
var getup_from := {}


func _ready() -> void:
	skin_texture = load("res://skins/totem.png")
	for part_name in PARTS.keys():
		_build_part(part_name)
	for j in JOINTS:
		_build_joint(j[0], j[1], j[2] * PX, deg_to_rad(j[3]))
	# Govdenin kendi parcalari birbirine carpmasin. Minecraft modelinde bacaklar
	# yan yana TEMAS halinde basliyor; carpisma acikken surekli itisiyorlardi ve
	# bu karakterin titremesine yol aciyordu. Katlanmayi eklem sinirlari onluyor.
	var names := bodies.keys()
	for i in names.size():
		for k in range(i + 1, names.size()):
			bodies[names[i]].add_collision_exception_with(bodies[names[k]])
	_set_frozen(true)


# --- Kurulum ---

func _build_part(part_name: String) -> void:
	var spec: Dictionary = PARTS[part_name]
	var size: Vector3 = spec.size * PX

	var body := RigidBody3D.new()
	body.name = part_name
	body.mass = spec.mass
	body.position = spec.center * PX
	# Havada asili cok parcali sarkac: sonum dusukken sallanma surup gidiyordu
	# (durgunken bile ~1 rad/s). Ivme hissi kalsin ama salinim sonsun.
	body.linear_damp = 1.0
	body.angular_damp = 6.0
	body.continuous_cd = true
	body.set_meta("part", part_name)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	body.add_child(_make_box_mesh(spec.size, spec.uv, 0.0))
	body.add_child(_make_box_mesh(spec.size, spec.overlay, 0.5))

	add_child(body)
	bodies[part_name] = body
	rest_transforms[part_name] = body.transform


func _build_joint(a_name: String, b_name: String, world_point: Vector3, swing: float) -> void:
	var a: RigidBody3D = bodies[a_name]
	var b: RigidBody3D = bodies[b_name]

	var joint := ConeTwistJoint3D.new()
	joint.position = world_point
	# Eklem ekseni yukari (Y): koni, uzvun govdeden asagi sarkma yonu etrafinda
	joint.rotation = Vector3(0, 0, PI / 2)
	add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25))
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
	# Bitisik parcalar birbirine carpmasin
	a.add_collision_exception_with(b)
	# Teshis: eklem noktasinin iki govdeye gore yerel konumu (kopma olcumu icin)
	joint_probes.append([a, a.transform.affine_inverse() * world_point,
		b, b.transform.affine_inverse() * world_point, "%s-%s" % [a_name, b_name]])


## Her eklemde iki govdenin eklem noktalari arasindaki aciklik (piksel).
## 0'a yakin olmali; buyukse uzuvlar kopuyor demektir.
func joint_gaps() -> Dictionary:
	var out := {}
	for p in joint_probes:
		var pa: Vector3 = p[0].transform * p[1]
		var pb: Vector3 = p[2].transform * p[3]
		out[p[4]] = snappedf(pa.distance_to(pb) / PX, 0.01)
	return out


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

	# Her yuz: normal, dis taraftan bakinca sol-ust/sag-ust/sag-alt/sol-alt kose, UV dikdortgeni
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


# --- Ragdoll durumu ---

func _set_frozen(frozen: bool) -> void:
	for body in bodies.values():
		body.freeze = frozen
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		if not frozen:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO


func start_ragdoll() -> void:
	getting_up = false
	ragdoll_active = true
	settle_timer = 0.0
	_set_frozen(false)


func release_ragdoll() -> void:
	settle_timer = 0.0


func _physics_process(delta: float) -> void:
	if getting_up:
		_advance_getup(delta)
		return
	if not ragdoll_active:
		return
	if get_parent().has_method("is_holding") and get_parent().is_holding():
		settle_timer = 0.0
		return

	# Birakildi: govde durulunca ayaga kalk
	var energy := 0.0
	for body in bodies.values():
		energy += body.linear_velocity.length_squared()
	if energy < 0.02:
		settle_timer += delta
		if settle_timer > GETUP_DELAY:
			_begin_getup()
	else:
		settle_timer = 0.0


func _begin_getup() -> void:
	ragdoll_active = false
	getting_up = true
	getup_progress = 0.0
	getup_from.clear()
	# Karakter nereye dustuyse orada kalksin: dinlenme duzenini oraya tasi
	var fallen_x: float = bodies["body"].global_position.x
	for part_name in bodies.keys():
		getup_from[part_name] = bodies[part_name].transform
	_set_frozen(true)
	for part_name in rest_transforms.keys():
		var t: Transform3D = rest_transforms[part_name]
		t.origin.x += fallen_x - rest_transforms["body"].origin.x
		rest_transforms[part_name] = t


func _advance_getup(delta: float) -> void:
	getup_progress = min(1.0, getup_progress + delta / GETUP_TIME)
	var k := ease(getup_progress, -2.0)
	for part_name in bodies.keys():
		var from: Transform3D = getup_from[part_name]
		var to: Transform3D = rest_transforms[part_name]
		bodies[part_name].transform = from.interpolate_with(to, k)
	if getup_progress >= 1.0:
		getting_up = false
