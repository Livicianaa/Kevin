extends Node3D
## Sahne: dunya = TUM MASAUSTU (butun ekranlar), pencere ise sadece karakterin
## etrafi kadar ve karakteri takip ediyor.
##
## Neden kucuk pencere: tam ekran seffaf pencere butun tiklamalari yutuyordu.
## Karakterin siluetini tiklama alani yapma yontemi (mouse_passthrough) Hyprland'in
## XWayland'inde uygulanmiyor. Kucuk takip penceresi her yerde calisiyor ve
## karakterin ekranlar arasinda gezmesinin de temeli.

const Character := preload("res://character.gd")

## Ekranda 1 dunya biriminin kac piksel oldugu. Karakter 2 birim boyunda.
const PX_PER_UNIT := 118.0
## Takip penceresi (piksel): ragdoll'da uzuvlar acilsa da sigacak kadar
const WIN_SIZE := Vector2i(430, 500)
## Pencere karakteri ne kadar hizli takip etsin (0-1, kare basina)
const FOLLOW := 0.55

var character: Node3D
var camera: Camera3D
var holder: AnimatableBody3D = null
var pin: PinJoint3D
var holding := false
var holder_target := Vector3.ZERO

## Masaustu sinirlari (piksel, X11 koordinatlari - y asagi)
var desk_rect := Rect2i()
var screens: Array[Rect2i] = []
var win_pos := Vector2.ZERO

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
var test_throw := false


func _ready() -> void:
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
		elif arg == "--throw":
			test_throw = true

	_read_screens()
	DisplayServer.window_set_size(WIN_SIZE)

	_build_camera()
	_build_lights()
	_build_world_edges()

	character = Character.new()
	add_child(character)
	var margin := 0.6
	character.bounds = Vector2(_px_to_world_x(desk_rect.position.x) + margin, _px_to_world_x(desk_rect.end.x) - margin)
	# Baslangicta farenin bulundugu ekranin ortasinda dursun
	var start_screen := screens[DisplayServer.window_get_current_screen()] if DisplayServer.window_get_current_screen() < screens.size() else screens[0]
	character.root_x = _px_to_world_x(start_screen.get_center().x)

	win_pos = _desired_window_pos()
	_apply_window()


# =====================================================================
# Masaustu <-> dunya donusumu
# =====================================================================

func _read_screens() -> void:
	screens.clear()
	desk_rect = Rect2i()
	for i in DisplayServer.get_screen_count():
		var r := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		screens.append(r)
		desk_rect = r if screens.size() == 1 else desk_rect.merge(r)
	# Bassiz testte ekran bilgisi yok: iki ekranli ornek masaustu
	if screens.is_empty():
		screens = [Rect2i(0, 0, 1920, 1080), Rect2i(1920, 0, 1920, 1080)]
		desk_rect = Rect2i(0, 0, 3840, 1080)


## Dunya: x = masaustu x / olcek; y = (masaustunun en alti - masaustu y) / olcek
## Boylece y=0 ekranlarin alt kenari, y yukari dogru artiyor.
func _px_to_world_x(px: float) -> float:
	return px / PX_PER_UNIT


func _px_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x / PX_PER_UNIT, (desk_rect.end.y - p.y) / PX_PER_UNIT, 0)


func _world_to_px(w: Vector3) -> Vector2:
	return Vector2(w.x * PX_PER_UNIT, desk_rect.end.y - w.y * PX_PER_UNIT)


# =====================================================================
# Kurulum
# =====================================================================

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = WIN_SIZE.y / PX_PER_UNIT
	camera.near = 0.1
	camera.far = 100.0
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


## Her ekranin alt kenari bir zemin; masaustunun dis kenarlari ve tavani duvar.
## Ekranlar farkli yukseklikteyse her biri kendi zeminini aliyor.
func _build_world_edges() -> void:
	for r in screens:
		var floor_y := (desk_rect.end.y - r.end.y) / PX_PER_UNIT
		var width := r.size.x / PX_PER_UNIT
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 2.0, 20.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(r.position.x / PX_PER_UNIT + width / 2.0, floor_y - 1.0, 0)
		add_child(body)

	var left := desk_rect.position.x / PX_PER_UNIT
	var right := desk_rect.end.x / PX_PER_UNIT
	var top := (desk_rect.end.y - desk_rect.position.y) / PX_PER_UNIT
	for e in [[Vector3(left, 0, 0), Vector3.RIGHT], [Vector3(right, 0, 0), Vector3.LEFT], [Vector3(0, top, 0), Vector3.DOWN]]:
		var wall := StaticBody3D.new()
		var ws := CollisionShape3D.new()
		var plane := WorldBoundaryShape3D.new()
		plane.plane = Plane(e[1], 0.0)
		ws.shape = plane
		wall.add_child(ws)
		wall.position = e[0]
		add_child(wall)


# =====================================================================
# Takip penceresi
# =====================================================================

## Karakterin merkezi (govde) - ragdoll'da da, ayaktayken de
func _character_center() -> Vector3:
	return character.bodies["body"].global_position


func _desired_window_pos() -> Vector2:
	var center_px := _world_to_px(_character_center())
	var pos := center_px - Vector2(WIN_SIZE) / 2.0
	# Pencere masaustu disina tasmasin (karakter zemindeyken pencere ekranin
	# altina yapisik kaliyor, ayaklar ekranin gercek alt kenarinda gorunuyor)
	pos.x = clampf(pos.x, desk_rect.position.x, desk_rect.end.x - WIN_SIZE.x)
	pos.y = clampf(pos.y, desk_rect.position.y, desk_rect.end.y - WIN_SIZE.y)
	return pos


func _apply_window() -> void:
	DisplayServer.window_set_position(Vector2i(roundi(win_pos.x), roundi(win_pos.y)))
	# Kamera pencerenin dunyadaki merkezine bakiyor
	var center := _px_to_world(win_pos + Vector2(WIN_SIZE) / 2.0)
	camera.position = Vector3(center.x, center.y, 30)


func _update_window() -> void:
	var target := _desired_window_pos()
	# Tutarken ve dusarken hizli, yururken yumusak takip
	var k := 1.0 if holding or character.is_ragdoll() else FOLLOW
	win_pos = win_pos.lerp(target, k)
	_apply_window()


func is_holding() -> bool:
	return holding


# =====================================================================
# Fare
# =====================================================================

## Fare masaustu koordinatinda: pencere tasinsa da tutma noktasi kaymasin.
func _mouse_world() -> Vector3:
	return _px_to_world(Vector2(DisplayServer.mouse_get_position()))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_grab(event.position)
		else:
			_release()


func _try_grab(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or not (hit.collider is RigidBody3D):
		return
	_grab_body(hit.collider, hit.position)


func _grab_body(body: RigidBody3D, point: Vector3) -> void:
	character.start_ragdoll()

	# Tutucu her tutmada YENIDEN ve dogru konumda yaratiliyor: ayni tutucuyu
	# tasiyip ayni karede eklem kurmak ofseti iki kat hesaplatiyordu.
	if holder:
		holder.queue_free()
	holder = AnimatableBody3D.new()
	holder.sync_to_physics = true
	holder.position = point
	add_child(holder)
	holder_target = point
	grab_offset = point - _mouse_world()
	grab_offset.z = 0

	pin = PinJoint3D.new()
	pin.position = point
	add_child(pin)
	pin.node_a = pin.get_path_to(body)
	pin.node_b = pin.get_path_to(holder)
	pin.set_param(PinJoint3D.PARAM_DAMPING, 1.0)
	holding = true


var grab_offset := Vector3.ZERO


func _release() -> void:
	if pin:
		pin.queue_free()
		pin = null
	if holding:
		holding = false
		character.release_ragdoll()


# =====================================================================
# Kare dongusu
# =====================================================================

func _physics_process(delta: float) -> void:
	if holding and holder:
		# Pencere disina tasan hizli fare hareketinde de takip: masaustu koordinati
		if test_grab == "":
			var m := _mouse_world() + grab_offset
			var z := holder_target.z
			holder_target = Vector3(m.x, maxf(m.y, 0.1), z)
			# Fare birakildiysa (pencere disinda birakilmis olabilir)
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_release()
		holder.global_position = holder.global_position.lerp(holder_target, 0.6)

	character.look_point = _mouse_world()

	if test_grab != "":
		_run_grab_test(delta)


func _process(delta: float) -> void:
	_update_window()
	_update_mouse_passthrough(delta)
	_process_shots(delta)


# --- Tiklanabilir alan (Windows ve X11'de etkili; Hyprland XWayland'de degil) ---

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
	if test_time > 0.8 and not test_grabbed:
		var body: RigidBody3D = character.bodies.get(test_grab)
		if body:
			test_grabbed = true
			var point := body.global_position + Vector3(0, 0.3, 0)
			test_grab_origin = point
			_grab_body(body, point)
	if holding:
		var t := test_time - 0.8
		if test_throw:
			# Firlatma: sag ekrana dogru hizla savur, sonra birak
			holder_target = test_grab_origin + Vector3(t * 9.0, minf(t * 3.0, 1.6), 0)
			if t > 0.9:
				_release()
		else:
			var lift_max: float = 1.45 if test_grab.ends_with("leg") else 0.9
			var lift: float = minf(t * 1.2, lift_max)
			var sway: float = sin(t * 3.0) * 0.5 * clampf(t - 0.8, 0.0, 1.0) * clampf(2.4 - t, 0.0, 1.0)
			holder_target = test_grab_origin + Vector3(sway, lift, 0)
			if t > 3.2:
				_release()

	if test_diag:
		diag_clock += delta
		if diag_clock >= 0.5:
			diag_clock = 0.0
			var b: Dictionary = character.bodies
			var c := _character_center()
			var cpx := _world_to_px(c)
			var screen_idx := -1
			for i in screens.size():
				if screens[i].has_point(Vector2i(cpx)):
					screen_idx = i
			print("DIAG t=%.1f mod=%s  govde_x=%.2f (ekran %d)  pencere=%s  kafa_y=%.2f  bosluk=%.2fpx" % [
				test_time, ["ANIMATED", "RAGDOLL", "GETTING_UP"][character.mode],
				c.x, screen_idx, str(Vector2i(win_pos)), b["head"].global_position.y,
				character.joint_gaps().values().max()])
		if test_time > 10.0:
			get_tree().quit()


func _process_shots(delta: float) -> void:
	if shot_prefix == "":
		return
	shot_clock += delta
	if shot_index < shot_times.size() and shot_clock >= shot_times[shot_index]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shot_prefix, shot_index])
		shot_index += 1
		if shot_index >= shot_times.size():
			get_tree().quit()
