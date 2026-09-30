extends Node3D
## Sahne: ekranin tamamini kaplayan SAYDAM pencere, ekran piksellerine eslenmis
## kamera, zemin = ekranin gercek alt kenari, kenarlarda gorunmez duvarlar.
##
## Karakter ekranin her yerine tasinabiliyor; tiklanabilir alan sadece silueti,
## geri kalan her sey tiklamayi alttaki pencerelere geciriyor.

const Character := preload("res://character.gd")

## Ekranda 1 dunya biriminin kac piksel oldugu. Karakter 2 birim boyunda.
const PX_PER_UNIT := 118.0

var character: Node3D
var camera: Camera3D
var holder: AnimatableBody3D = null
var pin: PinJoint3D
var holding := false
var grab_depth := 0.0
var holder_target := Vector3.ZERO

var world_width := 16.0
var world_height := 9.0

# Test bayraklari
var test_grab := ""
var test_time := 0.0
var test_grab_origin := Vector3.ZERO
var test_grabbed := false
var test_diag := false
var diag_clock := 0.0
var shot_prefix := ""
var shot_times := [0.6, 3.0, 6.95, 9.5]
var shot_index := 0
var shot_clock := 0.0
var windowed_test := false


func _ready() -> void:
	# Arka plan: SAYDAM. Onceki surum BG_CLEAR_COLOR kullaniyordu ve varsayilan
	# temizleme rengi opak griydi - pencere seffaf olsa bile ustune gri boyaniyordu.
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_viewport().transparent_bg = true
	Engine.max_fps = 60

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grab="):
			test_grab = arg.substr(7)
		elif arg == "--diag":
			test_diag = true
		elif arg.begins_with("--shot="):
			shot_prefix = arg.substr(7)
		elif arg == "--windowed":
			windowed_test = true

	_fit_to_screen()
	_build_camera()
	_build_lights()
	_build_world_edges()

	character = Character.new()
	add_child(character)
	character.bounds = Vector2(-world_width / 2.0 + 0.6, world_width / 2.0 - 0.6)


## Pencereyi bulundugu ekranin tamamina yayar. Dunya boyutu ekran pikselinden cikar:
## boylece zemin (y=0) tam olarak ekranin alt kenarina denk geliyor.
func _fit_to_screen() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var pos := DisplayServer.screen_get_position(screen)
	var size := DisplayServer.screen_get_size(screen)

	if windowed_test:
		size = Vector2i(900, 600)
	else:
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(pos)

	world_width = size.x / PX_PER_UNIT
	world_height = size.y / PX_PER_UNIT


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = world_height
	camera.near = 0.1
	camera.far = 100.0
	# Ekranin alt kenari y=0: kamera ekranin dikey ortasinda
	camera.position = Vector3(0, world_height / 2.0, 30)
	add_child(camera)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.0
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## Zemin = ekranin alt kenari; iki yan kenar ve tavan gorunmez duvar.
func _build_world_edges() -> void:
	var edges := [
		[Vector3(0, 0, 0), Vector3.UP],
		[Vector3(-world_width / 2.0, 0, 0), Vector3.RIGHT],
		[Vector3(world_width / 2.0, 0, 0), Vector3.LEFT],
		[Vector3(0, world_height, 0), Vector3.DOWN],
	]
	for e in edges:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var plane := WorldBoundaryShape3D.new()
		plane.plane = Plane(e[1], 0.0)
		shape.shape = plane
		body.add_child(shape)
		body.position = e[0]
		add_child(body)


func is_holding() -> bool:
	return holding


# =====================================================================
# Fare
# =====================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_grab(event.position)
		else:
			_release()
	elif event is InputEventMouseMotion and holding:
		holder_target = _point_at_depth(event.position)


func _try_grab(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or not (hit.collider is RigidBody3D):
		return
	_grab_body(hit.collider, hit.position)


func _grab_body(body: RigidBody3D, point: Vector3) -> void:
	character.start_ragdoll()

	var forward := -camera.global_transform.basis.z
	grab_depth = (point - camera.global_position).dot(forward)

	# Tutucu her tutmada YENIDEN ve dogru konumda yaratiliyor: ayni tutucuyu
	# tasiyip ayni karede eklem kurmak ofseti iki kat hesaplatiyordu.
	if holder:
		holder.queue_free()
	holder = AnimatableBody3D.new()
	holder.sync_to_physics = true
	holder.position = point
	add_child(holder)
	holder_target = point

	pin = PinJoint3D.new()
	pin.position = point
	add_child(pin)
	pin.node_a = pin.get_path_to(body)
	pin.node_b = pin.get_path_to(holder)
	pin.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
	holding = true


func _release() -> void:
	if pin:
		pin.queue_free()
		pin = null
	if holding:
		holding = false
		character.release_ragdoll()


func _point_at_depth(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var forward := -camera.global_transform.basis.z
	var p := from + dir * (grab_depth / dir.dot(forward))
	# Ekranin disina surukleme olmasin
	p.x = clampf(p.x, -world_width / 2.0, world_width / 2.0)
	p.y = clampf(p.y, 0.1, world_height)
	return p


# =====================================================================
# Kare dongusu
# =====================================================================

func _physics_process(delta: float) -> void:
	if holding and holder:
		holder.global_position = holder.global_position.lerp(holder_target, 0.6)

	# Karakter fareye baksin
	var mouse := get_viewport().get_mouse_position()
	character.look_point = _mouse_world(mouse)

	_update_mouse_passthrough(delta)

	if test_grab != "":
		_run_grab_test(delta)


func _mouse_world(screen_pos: Vector2) -> Vector3:
	var p := camera.project_ray_origin(screen_pos)
	return Vector3(p.x, p.y, 0)


# --- Sadece karakter tiklanabilsin ---

const PASSTHROUGH_INTERVAL := 1.0 / 20.0
var passthrough_clock := 0.0


func _update_mouse_passthrough(delta: float) -> void:
	passthrough_clock += delta
	if passthrough_clock < PASSTHROUGH_INTERVAL:
		return
	passthrough_clock = 0.0

	if holding:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
		return

	var points := PackedVector2Array()
	for body in character.bodies.values():
		var shape: BoxShape3D = body.get_child(0).shape
		var h: Vector3 = shape.size * 0.5
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					var corner: Vector3 = body.global_transform * Vector3(h.x * sx, h.y * sy, h.z * sz)
					points.append(camera.unproject_position(corner))

	var hull := Geometry2D.convex_hull(points)
	if hull.size() >= 3:
		DisplayServer.window_set_mouse_passthrough(hull)


# =====================================================================
# Testler
# =====================================================================

func _run_grab_test(delta: float) -> void:
	test_time += delta
	# Tek seferlik: onceden karakter kalkmaya basladigi an (artik ragdoll degil)
	# test onu tekrar tutuyordu ve sonsuz dusme dongusu olusuyordu.
	if test_time > 0.8 and not test_grabbed:
		var body: RigidBody3D = character.bodies.get(test_grab)
		if body:
			test_grabbed = true
			var point := body.global_position + Vector3(0, 0.3, 0)
			test_grab_origin = point
			_grab_body(body, point)
	if holding:
		var t := test_time - 0.8
		var lift_max: float = 1.45 if test_grab.ends_with("leg") else 0.9
		var lift: float = minf(t * 1.2, lift_max)
		var sway: float = sin(t * 3.0) * 0.5 * clampf(t - 0.8, 0.0, 1.0) * clampf(2.4 - t, 0.0, 1.0)
		holder_target = test_grab_origin + Vector3(sway, lift, 0)
		# 3.2 sn sonra birak: dusme + ayaga kalkma da gorulsun
		if t > 3.2:
			_release()

	if test_diag:
		diag_clock += delta
		if diag_clock >= 0.5:
			diag_clock = 0.0
			var b: Dictionary = character.bodies
			var feet: float = minf(b["right_leg"].global_position.y, b["left_leg"].global_position.y) - 6.0 / 16.0
			var energy := 0.0
			var spin := 0.0
			for body in b.values():
				energy += body.linear_velocity.length_squared()
				spin = maxf(spin, body.angular_velocity.length())
			print("DIAG t=%.1f mod=%s  ayak_alt_y=%.3f  kafa_y=%.2f  bosluk=%.2fpx  enerji=%.4f donus=%.2f bekleme=%.2f" % [
				test_time, ["ANIMATED", "RAGDOLL", "GETTING_UP"][character.mode],
				feet, b["head"].global_position.y, character.joint_gaps().values().max(),
				energy, spin, character.settle_timer])
		if test_time > 10.0:
			get_tree().quit()


func _process(delta: float) -> void:
	if shot_prefix == "":
		return
	shot_clock += delta
	if shot_index < shot_times.size() and shot_clock >= shot_times[shot_index]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shot_prefix, shot_index])
		shot_index += 1
		if shot_index >= shot_times.size():
			get_tree().quit()
