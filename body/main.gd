extends Node3D
## Sahne: kamera, isik, zemin, karakter ve fareyle 3B tutma.
##
## Tiklanan noktaya kameradan isin atiliyor; isabet eden uzuv (RigidBody3D) o
## noktadan farenin tutucusuna eklemle baglaniyor. Fare hareket ettikce tutucu
## ayni derinlikte kalarak ilerliyor - tutulan uzuv onu takip ediyor, gerisi sarkiyor.

const Character := preload("res://character.gd")

var character: Node3D
var camera: Camera3D
var holder: AnimatableBody3D = null
var pin: PinJoint3D
var holding := false
var grab_depth := 0.0
var holder_target := Vector3.ZERO

# Test: `-- --grab=left_arm` o uzvu otomatik tutup yukari kaldiriyor
var test_grab := ""
var test_time := 0.0
var test_grab_origin := Vector3.ZERO
var test_diag := false
var diag_clock := 0.0
var test_drop := false


func _ready() -> void:
	get_viewport().transparent_bg = true
	_build_camera()
	_build_lights()
	_build_ground()

	character = Character.new()
	add_child(character)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grab="):
			test_grab = arg.substr(7)
		elif arg == "--diag":
			test_diag = true
		elif arg == "--drop":
			test_drop = true


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0.35, 1.25, 4.6)
	add_child(camera)
	camera.look_at(Vector3(0, 1.05, 0))


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
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


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)


func is_holding() -> bool:
	return holding


# --- Sadece karakter tiklanabilsin ---
#
# Pencere seffaf bir dikdortgen; ama tiklanabilir alan karakterin SILUETI olmali,
# etrafindaki bos alan tiklamayi alttaki pencereye gecirmeli. Her uzvun 3B kutusu
# ekrana izdusuruluyor, noktalarin disbukey kabugu tiklama alani oluyor.
# (X11/XWayland ve Windows'ta calisiyor; saf Wayland cokgen kabul etmiyor.)

const PASSTHROUGH_INTERVAL := 1.0 / 20.0
var passthrough_clock := 0.0


func _update_mouse_passthrough(delta: float) -> void:
	passthrough_clock += delta
	if passthrough_clock < PASSTHROUGH_INTERVAL:
		return
	passthrough_clock = 0.0

	# Tutarken butun pencere tiklanabilir kalsin: fare siluetin disina cikinca
	# surukleme kopmasin.
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


# --- Fare ---

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
	var to := from + camera.project_ray_normal(screen_pos) * 50.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or not (hit.collider is RigidBody3D):
		return
	_grab_body(hit.collider, hit.position)


func _grab_body(body: RigidBody3D, point: Vector3) -> void:
	character.start_ragdoll()

	var forward := -camera.global_transform.basis.z
	grab_depth = (point - camera.global_position).dot(forward)

	# Tutucu her tutmada YENIDEN ve dogru konumda yaratiliyor. Onceden ayni tutucu
	# tasinip ayni karede eklem kuruluyordu: fizik motoru tutucuyu hala eski yerinde
	# (0,0,0) sandigi icin eklem ofseti iki kat hesaplaniyor, tutma noktasi ~1.4 birim
	# yukarida kaliyordu - karakter "yukaridan cekiliyor" gibi tutulan noktanin
	# USTUNDE duruyordu.
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


## Fare isininin, tutma aninda kameradan ayni uzaklikta olan duzlemle kesisimi
func _point_at_depth(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var forward := -camera.global_transform.basis.z
	return from + dir * (grab_depth / dir.dot(forward))


func _physics_process(delta: float) -> void:
	if holding and holder:
		# Tutucuyu fizik adiminda tasiyoruz: sync_to_physics ile hiz hesaplaniyor,
		# boylece fare hareketi uzuvlara ivme olarak geciyor.
		holder.global_position = holder.global_position.lerp(holder_target, 0.6)

	_update_mouse_passthrough(delta)

	if test_grab != "":
		_run_grab_test(delta)

	# Teshis: tutmadan serbest birak - yercekimi dogru mu, eklemler itiyor mu
	if test_drop:
		test_time += delta
		if test_time > 0.3 and not character.ragdoll_active and test_time < 0.4:
			character.start_ragdoll()
		diag_clock += delta
		if diag_clock >= 0.4:
			diag_clock = 0.0
			var b: Dictionary = character.bodies
			print("DROP t=%.1f  kafa_y=%.2f govde_y=%.2f sol_bacak_y=%.2f  govde_hiz=%.2f  bosluk %s" % [
				test_time, b["head"].position.y, b["body"].position.y, b["left_leg"].position.y,
				b["body"].linear_velocity.length(), str(character.joint_gaps())])
		if test_time > 3.2:
			get_tree().quit()


func _run_grab_test(delta: float) -> void:
	test_time += delta
	if test_time > 0.8 and not holding:
		var body: RigidBody3D = character.bodies.get(test_grab)
		if body:
			# Uzvun ust ucundan tut (kol/bacakta el/ayak ucu yerine ust kenar yeterli)
			var point := body.global_position + Vector3(0, 0.3, 0)
			test_grab_origin = point
			_grab_body(body, point)
	if holding:
		# Tutuldugu yerden biraz kaldir ve iki yana salla. Pencere icinde kalsin:
		# onceki surum kolu 2.7 birime kadar kaldirip karakteri cerceveden cikariyordu.
		var t := test_time - 0.8
		# Bacaktan tutulan karakter bas asagi doner: kafasi zemine surtmesin diye
		# boyu kadar yukari kaldiriliyor.
		var lift_max: float = 1.45 if test_grab.ends_with("leg") else 0.45
		var lift: float = min(t * 1.2, lift_max)
		# Salla, sonra dur: durulmus haldeki titremeyi olcebilmek icin
		var sway: float = sin(t * 3.0) * 0.35 * clampf(t - 0.8, 0.0, 1.0) * clampf(2.4 - t, 0.0, 1.0)
		holder_target = test_grab_origin + Vector3(sway, lift, 0)

	# Teshis: her yarim saniyede eklem acikliklarini yaz
	if test_diag and holding:
		diag_clock += delta
		if diag_clock >= 0.5:
			diag_clock = 0.0
			var b: Dictionary = character.bodies
			var hy: float = holder.global_position.y
			var spin := 0.0
			for body in b.values():
				spin = max(spin, body.angular_velocity.length())
			print("DIAG t=%.1f  kafa_y=%.2f govde_y=%.2f ayak_y=%.2f  govde_tutucunun_%s  bosluk=%.2fpx  en_hizli_donus=%.2f rad/s" % [
				test_time, b["head"].position.y, b["body"].position.y, b["right_leg"].position.y,
				"ALTINDA" if b["body"].position.y < hy else "USTUNDE",
				character.joint_gaps().values().max(), spin])
		if test_time > 5.0:
			get_tree().quit()


# Test: `-- --shot=/yol/on_ek` belirli anlarda kendi render ciktisini PNG kaydediyor
# (ekran yakalamaktan bagimsiz, karakterin gercekten cizilip cizilmedigini gosterir)
var shot_prefix := ""
var shot_times := [0.5, 2.0, 3.2, 4.4]
var shot_index := 0
var shot_clock := 0.0


func _process(delta: float) -> void:
	if shot_prefix == "":
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--shot="):
				shot_prefix = arg.substr(7)
		if shot_prefix == "":
			set_process(false)
			return
	shot_clock += delta
	if shot_index < shot_times.size() and shot_clock >= shot_times[shot_index]:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [shot_prefix, shot_index])
		shot_index += 1
		if shot_index >= shot_times.size():
			get_tree().quit()
