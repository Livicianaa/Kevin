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
## Takip penceresi (piksel), SABIT. Tutarken buyuyup ayaktayken kuculen bir
## surum denendi: Hyprland pencere boyutunu kamerayla ayni anda degistirmeyince
## karakter tutuldugunda kuculuyordu. 430x500 ise "asiri buyuktu".
const WIN_SIZE := Vector2i(300, 300)
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
## Panellerin disinda kalan yatay alan (karakterin girebildigi)
var usable_left := 0.0
var usable_right := 0.0
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
## Test: pencere ekranda gorunmesin (render yine aliniyor)
var test_offscreen := false
## Test: karakter hep bu durumda kalsin (walk, idle, look_around)
var test_anim := ""
## Test: acilista bu emote oynasin
var test_emote := ""
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
		elif arg == "--offscreen":
			test_offscreen = true
		elif arg.begins_with("--anim="):
			test_anim = arg.substr(7)
		elif arg.begins_with("--emote="):
			test_emote = arg.substr(8)
		elif arg.begins_with("--shots="):
			shot_times = []
			for v in arg.substr(8).split(","):
				shot_times.append(float(v))

	_read_screens()
	if usable_right <= usable_left:
		usable_left = desk_rect.position.x
		usable_right = desk_rect.end.x
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

	# Hyprland pencere kenarligini (ve kose yuvarlamasini) kaldir. Bu ozellikler
	# kural dosyasiyla degil, pencere ACILDIKTAN sonra setprop ile veriliyor.
	if OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE") != "":
		get_tree().create_timer(0.6).timeout.connect(_strip_decorations)


func _strip_decorations() -> void:
	for prop in [["decorate", "0"], ["rounding", "0"]]:
		OS.execute("hyprctl", ["dispatch", "setprop", "class:^(Kevin)$", prop[0], prop[1]])


# =====================================================================
# Masaustu <-> dunya donusumu
# =====================================================================

func _read_screens() -> void:
	screens.clear()
	desk_rect = Rect2i()

	# Hyprland'deysek ekranlari ONDAN oku: XWayland olcekli ekranlari fiziksel
	# boyutuyla (1920x1080) raporluyor, Hyprland ise mantiksal boyutla (1280x720)
	# yonetiyor. Zemin yanlis hesaplaninca karakter laptop ekraninin altina
	# gomuluyordu.
	var hypr := _hyprland_screens()
	if not hypr.is_empty():
		for r in hypr:
			screens.append(r)
			desk_rect = r if screens.size() == 1 else desk_rect.merge(r)
		_read_usable_area()
		return

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


func _hyprland_screens() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	if OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE") == "":
		return result
	var out := []
	if OS.execute("hyprctl", ["monitors", "-j"], out) != 0 or out.is_empty():
		return result
	var data = JSON.parse_string(out[0])
	if not (data is Array):
		return result
	for m in data:
		var scale: float = float(m.get("scale", 1.0))
		var w := roundi(float(m.width) / scale)
		var h := roundi(float(m.height) / scale)
		# 90/270 derece dondurulmus ekranlarda en/boy yer degistiriyor
		if int(m.get("transform", 0)) % 2 == 1:
			var tmp := w
			w = h
			h = tmp
		result.append(Rect2i(int(m.x), int(m.y), w, h))
	return result


## Panellerin kapladigi kenarlari bul. hyprctl'in "reserved" bilgisi yaniltici
## olabiliyor (caelestia bari solda dururken "ustte 60px" diyordu); tiling
## pencerelerin gercekte nereden basladigi daha guvenilir.
func _read_usable_area() -> void:
	usable_left = desk_rect.position.x
	usable_right = desk_rect.end.x
	var out := []
	if OS.execute("hyprctl", ["clients", "-j"], out) != 0 or out.is_empty():
		return
	var clients = JSON.parse_string(out[0])
	if not (clients is Array):
		return
	var min_x := INF
	var max_x := -INF
	for c in clients:
		if c.get("floating", true) or not c.get("mapped", false):
			continue
		var at: Array = c.get("at", [0, 0])
		var size: Array = c.get("size", [0, 0])
		if float(size[0]) < 200 or float(size[1]) < 200:
			continue
		min_x = minf(min_x, float(at[0]))
		max_x = maxf(max_x, float(at[0]) + float(size[0]))
	if min_x < INF:
		usable_left = maxf(usable_left, min_x - 10.0)
	if max_x > -INF:
		usable_right = minf(usable_right, max_x + 10.0)


## Karakterin bulundugu ekran (govdenin x'ine gore)
func _screen_at_x(px_x: float) -> Rect2i:
	for r in screens:
		if px_x >= r.position.x and px_x < r.end.x:
			return r
	return screens[0] if px_x < screens[0].position.x else screens[screens.size() - 1]


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
	# Her ekranin zemini masaustunun en altina kadar DOLU bir blok: alcak ekranin
	# (laptop, alti 720'de) altinda ekrani olmayan bos alan var, karakter oraya
	# dusup gorunmez olmasin. Yan yana farkli yukseklikte ekranlar arasinda bu
	# blok bir basamak olusturuyor; yuruyerek gecilmiyor, firlatinca geciliyor.
	for r in screens:
		var floor_y := (desk_rect.end.y - r.end.y) / PX_PER_UNIT
		var width := r.size.x / PX_PER_UNIT
		var depth := floor_y + 3.0
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, depth, 20.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(r.position.x / PX_PER_UNIT + width / 2.0, floor_y - depth / 2.0, 0)
		add_child(body)

	# Yan duvarlar ekranin fiziksel kenarinda degil, panellerin (caelestia bari
	# solda 0-82 arasi) bittigi yerde: karakter barin arkasina girmesin.
	var left := usable_left / PX_PER_UNIT
	var right := usable_right / PX_PER_UNIT
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
	var screen := _screen_at_x(center_px.x)
	var pos := center_px - Vector2(WIN_SIZE) / 2.0

	# Ayaktayken pencerenin alt kenari ekranin alt kenarinda: ayaklar ekranin
	# gercek altina basiyor ve pencere karakterden buyuk olmuyor.
	if character.mode == 0:
		pos.y = screen.end.y - WIN_SIZE.y

	# Karakterin bulundugu ekranin disina tasmasin
	pos.x = clampf(pos.x, desk_rect.position.x, desk_rect.end.x - WIN_SIZE.x)
	pos.y = clampf(pos.y, screen.position.y, screen.end.y - WIN_SIZE.y)
	return pos


## Karakter hangi ekrandaysa onun zemini ve yatay siniri. Ayaktayken yuruyerek
## ekran degistirmiyor (farkli yukseklikteki ekranlar arasinda basamak var);
## firlatilinca geciyor, dustugu ekranda kalkiyor.
func _update_character_screen() -> void:
	var center_px := _world_to_px(_character_center())
	var screen := _screen_at_x(center_px.x)
	var margin := 0.45
	character.ground_y = (desk_rect.end.y - screen.end.y) / PX_PER_UNIT
	character.bounds = Vector2(
		maxf(screen.position.x, usable_left) / PX_PER_UNIT + margin,
		minf(screen.end.x, usable_right) / PX_PER_UNIT - margin,
	)




func _apply_window() -> void:
	if test_offscreen:
		DisplayServer.window_set_position(Vector2i(9000, 9000))
	else:
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


## Basildigi an tutar. (Tik/surukleme ayrimi icin 6 px esik denendi; karakter
## yururken tutma noktasi kaydi ve tutmak zorlasti. Tik ile konusma, beyin
## baglaninca surukleme mesafesine bakilarak birakma aninda ayirt edilecek.)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit_at(event.position)
			if not hit.is_empty():
				_grab_body(hit.collider, hit.position)
		else:
			_release()


func _hit_at(screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or not (hit.collider is RigidBody3D):
		return {}
	return hit


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
	_update_character_screen()
	if test_emote != "" and character.mode == 0 and character.anim_state != "emote":
		character.play_emote(test_emote, 999.0)
	if test_anim != "" and character.mode == 0 and character.anim_state != test_anim:
		character.walk_target = character.bounds.y if test_anim == "walk" else character.root_x
		character._set_state(test_anim, 999.0)
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
			holder_target = test_grab_origin + Vector3(t * 16.0, minf(t * 4.0, 3.5), 0)
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
