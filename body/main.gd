extends Node3D
## Sahne: dunya = TUM MASAUSTU (butun ekranlar), pencere ise sadece karakterin
## etrafi kadar ve karakteri takip ediyor.
##
## Neden kucuk pencere: tam ekran seffaf pencere butun tiklamalari yutuyordu.
## Karakterin siluetini tiklama alani yapma yontemi (mouse_passthrough) Hyprland'in
## XWayland'inde uygulanmiyor. Kucuk takip penceresi her yerde calisiyor ve
## karakterin ekranlar arasinda gezmesinin de temeli.

const Character := preload("res://character.gd")
const Settings := preload("res://settings.gd")
const Menu := preload("res://menu.gd")
const Brain := preload("res://brain.gd")
const Splash := preload("res://splash.gd")
const I18n := preload("res://i18n.gd")
const SysProfile := preload("res://sysprofile.gd")

## Ekranda 1 dunya biriminin kac piksel oldugu. Karakter 2 birim boyunda.
var PX_PER_UNIT := 118.0
## Takip penceresi (piksel), SABIT. Tutarken buyuyup ayaktayken kuculen bir
## surum denendi: Hyprland pencere boyutunu kamerayla ayni anda degistirmeyince
## karakter tutuldugunda kuculuyordu. 430x500 ise "asiri buyuktu".
var WIN_SIZE := Vector2i(300, 300)
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
## Ekran basina kullanilabilir yatay alan (px): x = sol, y = sag
var usable: Array[Vector2] = []
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
var test_led := false
var test_splash := false
## Test: 1. saniyede menuyu ac (deger: acilacak sekme)
var test_menu := ""
var test_menu_clock := 0.0
var shot_times := [0.6, 3.0, 6.95, 9.5]
var shot_index := 0
var shot_clock := 0.0
var test_throw := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	get_viewport().transparent_bg = true
	# Donen kutularin kenarlari merdiven/cizgi gibi gorunuyordu (MSAA asagida)
	# Bilgisayarin gucune gore kare hizi ve hareketlilik (her acilista)
	sys_profile = SysProfile.detect()
	Engine.max_fps = SysProfile.max_fps(sys_profile)
	# Zayif makinede kenar yumusatma daha hafif
	get_viewport().msaa_3d = Viewport.MSAA_2X if sys_profile.tier == SysProfile.TIER_LOW else Viewport.MSAA_4X
	print("[kevin] sistem: %d cekirdek, %.1f GB, %s, %d ekran %d Hz -> %s, %d fps" % [sys_profile.cores, sys_profile.ram_gb, sys_profile.gpu, sys_profile.screens, sys_profile.refresh, sys_profile.tier, Engine.max_fps])

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grab="):
			test_grab = arg.substr(7)
		elif arg == "--diag":
			test_diag = true
		elif arg.begins_with("--shot="):
			shot_prefix = arg.substr(7)
		elif arg.begins_with("--menu"):
			test_menu = arg.substr(7) if arg.length() > 6 else "karakter"
		elif arg == "--splash":
			test_splash = true
		elif arg == "--led":
			test_led = true
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

	# Menuden kaydedilen govde ayarlari (boyut, model, skin, davranis)
	body_settings = Settings.load_body()
	var scale := clampf(float(body_settings.scale), 0.6, 2.0)
	PX_PER_UNIT = 118.0 * scale
	WIN_SIZE = Vector2i(roundi(300 * scale), roundi(300 * scale))

	_read_screens()
	if usable_right <= usable_left:
		usable_left = desk_rect.position.x
		usable_right = desk_rect.end.x
	get_window().size = WIN_SIZE

	_build_camera()
	_build_menu_bg()
	_build_lights()
	_build_world_edges()

	character = Character.new()
	character.slim = body_settings.slim
	character.skin_path = body_settings.skin
	_apply_behaviour(body_settings)
	add_child(character)
	var margin := 0.6
	character.bounds = Vector2(_px_to_world_x(desk_rect.position.x) + margin, _px_to_world_x(desk_rect.end.x) - margin)
	# Baslangicta farenin bulundugu ekranin ortasinda dursun
	var start_screen := screens[DisplayServer.window_get_current_screen()] if DisplayServer.window_get_current_screen() < screens.size() else screens[0]
	character.root_x = _px_to_world_x(start_screen.get_center().x)

	win_pos = _desired_window_pos()
	_apply_window()

	if (not testing_flags() or test_splash) and OS.get_environment("KEVIN_NO_SPLASH") == "":
		_start_splash()

	# Beyin (ses, sohbet): testlerde baslatma
	var testing := test_offscreen or test_grab != "" or test_diag or shot_prefix != "" or test_menu != "" or test_emote != "" or test_anim != ""
	if not testing and OS.get_environment("KEVIN_NO_BRAIN") == "":
		brain = Brain.new()
		add_child(brain)
		brain.state_changed.connect(character.on_brain_state)
		brain.played.connect(character.on_brain_play)
		brain.mood.connect(character.on_brain_mood)
		brain.said.connect(func(t): print("[kevin] diyor: ", t))
		brain.heard.connect(func(t): print("[kevin] duydu: ", t))

	# Hyprland pencere kenarligini (ve kose yuvarlamasini) kaldir. Bu ozellikler
	# kural dosyasiyla degil, pencere ACILDIKTAN sonra setprop ile veriliyor.
	if OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE") != "":
		get_tree().create_timer(0.6).timeout.connect(_strip_decorations)


var body_settings := {}
var sys_profile := {}


func testing_flags() -> bool:
	return test_offscreen or test_grab != "" or test_diag or shot_prefix != "" or test_menu != "" or test_emote != "" or test_anim != ""
var brain: Node = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if brain:
			brain.stop()


func _apply_behaviour(cfg: Dictionary) -> void:
	var activity := SysProfile.activity(sys_profile) if not sys_profile.is_empty() else 1.0
	character.walk_factor = float(cfg.walk) * activity
	character.emote_factor = float(cfg.emotes) * activity
	character.look_enabled = cfg.look
	character.wall_sit_enabled = cfg.wall_sit
	character.fun_enabled = cfg.fun
	character.walk_speed_factor = float(cfg.walk_speed)
	character.dance_enabled = cfg.dance
	character.mood_enabled = cfg.mood


func _strip_decorations() -> void:
	for prop in [["decorate", "0"], ["rounding", "0"]]:
		OS.execute("hyprctl", ["dispatch", "setprop", "class:^(Kevin)$", prop[0], prop[1]])


# =====================================================================
# Masaustu <-> dunya donusumu
# =====================================================================

var edge_nodes: Array[Node] = []
var screen_check_t := 0.0
var screen_signature := ""


## Ekran takilip cikarilinca, cozunurluk/olcek degisince ya da pencereler
## acilip kapaninca (kullanilabilir alan) her birkac saniyede bir yeniden bak.
## Degistiyse zemin ve duvarlar yeniden kurulur; Kevin yeni duzene uyar.
func _check_screens(delta: float) -> void:
	screen_check_t += delta
	if screen_check_t < 4.0 or holding or character.is_ragdoll():
		return
	screen_check_t = 0.0
	_read_screens()
	if usable_right <= usable_left:
		usable_left = desk_rect.position.x
		usable_right = desk_rect.end.x
	var sig := "%s|%s|%s|%s" % [str(screens), str(usable), usable_left, usable_right]
	if sig == screen_signature:
		return
	if screen_signature != "":
		print("[kevin] ekran duzeni degisti, yeniden kuruluyor")
		_build_world_edges()
	screen_signature = sig


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
	# Her ekranin kendi paneli olabilir (caelestia her monitorde solda):
	# kullanilabilir yatay alan ekran ekran. Onceden sadece genel sol/sag
	# vardi, Kevin ikinci ekranin barinin altina oturuyordu.
	usable.clear()
	for i in screens.size():
		usable.append(Vector2(screens[i].position.x, screens[i].end.x))
	for c in clients:
		if c.get("floating", true) or not c.get("mapped", false):
			continue
		var at: Array = c.get("at", [0, 0])
		var size: Array = c.get("size", [0, 0])
		if float(size[0]) < 200 or float(size[1]) < 200:
			continue
		var cx := float(at[0]) + float(size[0]) / 2.0
		for i in screens.size():
			if cx >= screens[i].position.x and cx < screens[i].end.x:
				var u: Vector2 = usable[i]
				# Ilk goruldugunde ekran siniri yerine pencerenin kenari
				if u.x == screens[i].position.x or float(at[0]) - 10.0 < u.x:
					u.x = maxf(screens[i].position.x, float(at[0]) - 10.0)
				if u.y == screens[i].end.x or float(at[0]) + float(size[0]) + 10.0 > u.y:
					u.y = minf(screens[i].end.x, float(at[0]) + float(size[0]) + 10.0)
				usable[i] = u
	usable_left = usable[0].x if not usable.is_empty() else usable_left
	usable_right = usable[usable.size() - 1].y if not usable.is_empty() else usable_right


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


const MENU_BG_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float alpha = 0.0;
uniform vec2 rect_px = vec2(1000.0, 700.0);
uniform float radius_px = 28.0;
void fragment() {
	vec3 col = mix(vec3(0.19, 0.13, 0.40), vec3(0.08, 0.06, 0.19), UV.y);
	vec2 g = fract(FRAGCOORD.xy / 22.0) - 0.5;
	col += (1.0 - smoothstep(0.08, 0.13, length(g))) * 0.045;
	float v = smoothstep(0.95, 0.2, length(UV - vec2(0.33, 0.45)));
	col *= mix(0.65, 1.12, v);
	// Yuvarlak koseli pencere + koyu kalin kenar (referanstaki gibi)
	vec2 p = (UV - 0.5) * rect_px;
	vec2 q = abs(p) - (rect_px * 0.5 - vec2(radius_px));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius_px;
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);
	float border = smoothstep(-6.0, -4.5, d);
	col = mix(col, vec3(0.08, 0.066, 0.17), border);
	ALBEDO = col;
	ALPHA = alpha * inside;
}
"""
var menu_bg: MeshInstance3D


## Menu arka plani: kameraya bagli, karakterin ARKASINDA bir duzlem (2B katman
## karakterin ustune cizilirdi)
func _build_menu_bg() -> void:
	menu_bg = MeshInstance3D.new()
	menu_bg.mesh = QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = MENU_BG_SHADER
	menu_bg.material_override = mat
	menu_bg.position = Vector3(0, 0, -40)
	menu_bg.visible = false
	camera.add_child(menu_bg)


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
	for n in edge_nodes:
		n.queue_free()
	edge_nodes.clear()
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
		edge_nodes.append(body)

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
		edge_nodes.append(wall)


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
	var u := Vector2(screen.position.x, screen.end.x)
	var idx := screens.find(screen)
	if idx >= 0 and idx < usable.size():
		u = usable[idx]
	character.bounds = Vector2(u.x / PX_PER_UNIT + margin, u.y / PX_PER_UNIT - margin)




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
## Ayaktayken koldan/kafadan/govdeden tutulunca once sendeleme (LED): yavas
## cekince o yone yuruyor, hizli ya da yukari cekince ragdoll. Bacaktan
## tutulunca dogrudan ragdoll (tokezleyip dusuyor).
const LED_PARTS := ["right_arm", "left_arm"]
var led := false
var led_body: RigidBody3D = null
var last_led_target := Vector3.INF
var led_speed := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if splash_state != SPLASH_NONE:
		if event is InputEventMouseButton and event.pressed and splash_state == SPLASH_SHOW:
			_end_splash()
		return
	if menu_state != MENU_CLOSED:
		_menu_input(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not _hit_at(event.position).is_empty():
			_open_menu()
		return
	# Orta tik: adi soylenmis gibi ("Efendim?")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
		if brain and not _hit_at(event.position).is_empty():
			brain.send({"type": "wake"})
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _hit_at(event.position)
			if not hit.is_empty():
				_press_body(hit.collider, hit.position)
		else:
			_release()


func _press_body(body: RigidBody3D, point: Vector3) -> void:
	if character.mode == 0 and str(body.name) in LED_PARTS:
		character.start_led(str(body.name), body.global_transform.affine_inverse() * point)
		led = true
		led_body = body
		last_led_target = Vector3.INF
		led_speed = 0.0
		grab_offset = point - _mouse_world()
		grab_offset.z = 0
		return
	_grab_body(body, point)


func _update_led(target: Vector3) -> void:
	target.z = character.led_grab_point().z
	var dt := get_physics_process_delta_time()
	if last_led_target != Vector3.INF:
		led_speed = lerpf(led_speed, target.distance_to(last_led_target) / dt, 0.5)
	last_led_target = target
	if character.led_update(target, led_speed):
		led = false
		var point: Vector3 = character.led_grab_point()
		_grab_body(led_body, point)
		if test_led:
			test_grab_origin = point
			test_time = 0.8


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
	character.held_part = str(body.name)
	character.hold_point = point


var grab_offset := Vector3.ZERO


func _release() -> void:
	if led:
		led = false
		character.end_led()
	if pin:
		pin.queue_free()
		pin = null
	character.held_part = ""
	if holding:
		holding = false
		character.release_ragdoll()


# =====================================================================
# Kare dongusu
# =====================================================================

func _physics_process(delta: float) -> void:
	var mw := _mouse_world()
	if led and test_grab == "":
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_release()
		else:
			_update_led(mw + grab_offset)

	if holding and holder:
		character.hold_point = holder.global_position
		# Pencere disina tasan hizli fare hareketinde de takip: masaustu koordinati
		if test_grab == "":
			var m := _mouse_world() + grab_offset
			var z := holder_target.z
			holder_target = Vector3(m.x, maxf(m.y, 0.1), z)
			# Fare birakildiysa (pencere disinda birakilmis olabilir)
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_release()
		holder.global_position = holder.global_position.lerp(holder_target, 0.6)

	if not led:
		character.look_point = mw

	if test_grab != "":
		_run_grab_test(delta)
	elif test_diag:
		test_time += delta
	if test_diag:
		_run_diag(delta)
		if test_time > (10.0 if test_grab != "" else 20.0):
			get_tree().quit()


# =====================================================================
# Menu: sag tik -> Kevin ekranin ortasina ucar, pencere o ekrani kaplar,
# kamera yaklasir, menu ustten ve yanlardan gelir.
# =====================================================================

enum { MENU_CLOSED, MENU_FLYING, MENU_RESIZING, MENU_OPEN, MENU_CLOSING }
const MENU_FLY_TIME := 0.9
## Kevin kendi kucuk penceresiyle menunun ortasina ucma suresi
const MENU_TRAVEL_TIME := 1.0
var menu_travel_t := 0.0
## Menunun ortasina gelince (1:1 boyutta) ayaklarinin yerden yuksekligi
var menu_fly_lift := 0.0
var menu_state := MENU_CLOSED
var menu_screen := Rect2i()
var menu_k := 0.0
var menu_from_x := 0.0
var menu_target_x := 0.0
var menu_layer: CanvasLayer
var menu_ui: Control
var menu_rotating := false
var menu_auto_rotate := false
var menu_reload := false
var menu_ground_y := 0.0
var menu_vp: SubViewport
var replay_splash := false
## Menu acilinca kendiliginden acilacak sayfa (ilk kurulum)
var onboard_tab := ""


func _open_menu() -> void:
	if character.mode != 0:
		return
	# Tam ekran degil: ekranin ortasinda yuvarlak koseli bir pencere
	# (livi: "neden tam ekran oluyor")
	var scr := _screen_at_x(_world_to_px(_character_center()).x)
	menu_ground_y = (desk_rect.end.y - scr.end.y) / PX_PER_UNIT
	# Sadece Kevin'in alani + sag sutun kadar genis (arada bosluk kalmasin)
	var sz := Vector2i(roundi(clampf(scr.size.x * 0.46, 760.0, 1000.0)), roundi(scr.size.y * 0.82))
	menu_screen = Rect2i(scr.position + (scr.size - sz) / 2, sz)
	# Normal moddaki siluet tiklama alani menude kalirsa hicbir dugmeye
	# basilamiyordu
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	# Once Kevin kendi penceresiyle menunun ortasina gercekten ucar, menu
	# orada acilir (livi: "menuye gelirken gercekten oraya gitsin")
	menu_state = MENU_FLYING
	menu_travel_t = 0.0
	menu_k = 0.0
	menu_from_x = character.root_x
	menu_target_x = _px_to_world_x(menu_screen.get_center().x)
	menu_fly_lift = maxf(0.0, _px_to_world(Vector2(menu_screen.get_center())).y - character.ground_y - 1.0)
	menu_reload = false
	character.enter_menu()
	# Menudeyken Kevin duymasin (ayar yaparken konusulanlar ona gitmesin)
	if brain:
		brain.send({"type": "menu", "open": true})


func _close_menu() -> void:
	if menu_state == MENU_CLOSED or menu_state == MENU_CLOSING:
		return
	menu_state = MENU_CLOSING
	menu_rotating = false
	if menu_ui:
		menu_ui.animate_out(Vector2(menu_screen.size))


func _finish_close() -> void:
	menu_state = MENU_CLOSED
	if menu_layer:
		menu_layer.queue_free()
		menu_layer = null
		menu_ui = null
	menu_bg.visible = false
	if menu_vp:
		menu_vp.queue_free()
		menu_vp = null
	if brain:
		brain.send({"type": "menu", "open": false})
	# Kamera menude yakinlastirilmisti; geri alinmazsa Kevin minicik kaliyordu
	camera.size = WIN_SIZE.y / PX_PER_UNIT
	if menu_reload:
		character.exit_menu()
		get_tree().reload_current_scene()
		return
	if replay_splash:
		replay_splash = false
		character.exit_menu()
		_start_splash()
		return
	# Menunun ortasinda havada: acilis ekranindaki gibi oradan masaustune
	# duser, sonra kalkar (livi: "girisdeki gibi oradan asagi dussun")
	character.emote = null
	character.hold_pose = false
	character.menu_yaw = 0.0
	character.start_ragdoll()
	character.menu_lift = 0.0
	get_window().size = WIN_SIZE
	win_pos = _desired_window_pos()
	_apply_window()


func _build_menu_ui(size_px: Vector2) -> void:
	# Kagit zemin ve logo: Kevin'in ARKASINDA (SubViewport -> kameraya bagli duzlem)
	menu_vp = SubViewport.new()
	menu_vp.size = Vector2i(size_px)
	menu_vp.transparent_bg = true
	menu_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(menu_vp)
	menu_vp.add_child(Menu.make_background(size_px))
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.albedo_texture = menu_vp.get_texture()
	bg_mat.albedo_color = Color(1, 1, 1, 0)
	menu_bg.material_override = bg_mat
	menu_bg.visible = true

	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	menu_ui = Menu.new()
	menu_layer.add_child(menu_ui)
	menu_ui.build(size_px)
	menu_ui.close_requested.connect(_close_menu)
	menu_ui.skin_chosen.connect(func(path):
		character.set_skin(path)
		body_settings.skin = path
		Settings.save_body(body_settings))
	menu_ui.saved.connect(func(needs_reload):
		body_settings = Settings.load_body()
		_apply_behaviour(body_settings)
		menu_reload = needs_reload
		_close_menu())
	menu_ui.action.connect(_menu_action)


func _menu_action(name: String) -> void:
	match name:
		"auto_rotate_on":
			menu_auto_rotate = true
		"auto_rotate_off":
			menu_auto_rotate = false
		"reset":
			menu_auto_rotate = false
			character.menu_yaw = 0.0
		"splash":
			# Menuden "Acilis ekranini oynat": menu kapaninca
			replay_splash = true
			_close_menu()
		"emote":
			character.play_emote(character._random_emote(["fun", "social", "dance"].pick_random()))
		"relang":
			# Dil degisti: menu yeni dilde yeniden kurulur, ayni sayfada kalir;
			# beyin yeni dilin sesini indirmeye baslar
			if brain:
				brain.send({"type": "lang"})
			menu_layer.queue_free()
			menu_vp.queue_free()
			_build_menu_ui(get_viewport().get_visible_rect().size)
			menu_ui.open_instant("yapay_zeka")


func _menu_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_menu()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_close_menu()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			menu_rotating = event.pressed
	elif event is InputEventMouseMotion and menu_rotating:
		character.menu_yaw += event.relative.x * 0.012
		menu_auto_rotate = false


func _update_menu(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if menu_state == MENU_FLYING:
		# Kucuk pencere Kevin'le birlikte yay cizerek menunun ortasina gider
		menu_travel_t += delta
		var t := clampf(menu_travel_t / MENU_TRAVEL_TIME, 0.0, 1.0)
		var e := smoothstep(0.0, 1.0, t)
		character.root_x = lerpf(menu_from_x, menu_target_x, e)
		character.menu_lift = menu_fly_lift * e + sin(t * PI) * 1.2
		character.menu_yaw = signf(menu_target_x - menu_from_x) * 0.8 * sin(t * PI)
		win_pos = _desired_window_pos()
		_apply_window()
		if t >= 1.0:
			character.menu_yaw = 0.0
			menu_state = MENU_RESIZING
			get_window().size = menu_screen.size
			DisplayServer.window_set_position(menu_screen.position)
			DisplayServer.window_move_to_foreground()
		return
	if menu_state == MENU_RESIZING:
		# Pencere boyutu Hyprland'de gecikmeli degisiyor; ekran boyutuna
		# ulasmadan kamera/menu kurulursa karakter yanlis boyutta gorunuyordu.
		# Bu arada kamera 1:1 ve menunun ortasinda: Kevin yerinden kipirdamaz.
		var mid := _px_to_world(Vector2(menu_screen.get_center()))
		camera.position = Vector3(mid.x, mid.y, 30)
		camera.size = vp.y / PX_PER_UNIT
		if absf(vp.x - menu_screen.size.x) < 4 and absf(vp.y - menu_screen.size.y) < 4:
			menu_state = MENU_OPEN
			_build_menu_ui(vp)
		else:
			return
	elif menu_state == MENU_OPEN:
		menu_k = minf(1.0, menu_k + delta / MENU_FLY_TIME)
		if onboard_tab != "" and menu_k >= 1.0 and menu_ui:
			menu_ui._select_tab(onboard_tab)
			onboard_tab = ""
	elif menu_state == MENU_CLOSING:
		menu_k = maxf(0.0, menu_k - delta / 0.6)
		if menu_k <= 0.0:
			_finish_close()
			return

	if menu_auto_rotate:
		character.menu_yaw += delta * 0.9

	var k := smoothstep(0.0, 1.0, menu_k)
	# Kevin menunun ortasindan sahnedeki yerine iner (kamera yaklasirken);
	# kapanirken tersi: ortaya yukselir, sonra oradan duser
	character.root_x = menu_target_x
	character.menu_lift = menu_fly_lift * (1.0 - k)

	# Kamera: 1:1'den (karakter oldugu yerde) yakin plana; Kevin menunun
	# verdigi sahne yerinde (ortasi, ayak hizasi, boyu)
	var ground := menu_ground_y
	var stage_h: float = menu_ui.stage_h if menu_ui else 0.42 * vp.y
	var feet_y: float = menu_ui.stage_feet_y if menu_ui else 0.65 * vp.y
	var zoom_final := stage_h / (2.0 * PX_PER_UNIT)
	var zoom := lerpf(1.0, zoom_final, k)
	var c0 := _px_to_world(Vector2(menu_screen.get_center()))
	var stage_x: float = menu_ui.stage_x if menu_ui else vp.x * 0.33
	var c1 := Vector3(menu_target_x + (0.5 * vp.x - stage_x) / (PX_PER_UNIT * zoom_final), ground + (feet_y - 0.5 * vp.y) / (PX_PER_UNIT * zoom_final), 0)
	var c := c0.lerp(c1, k)
	camera.position = Vector3(c.x, c.y, 30)
	camera.size = vp.y / (PX_PER_UNIT * zoom)
	(menu_bg.mesh as QuadMesh).size = Vector2(camera.size * vp.x / vp.y, camera.size)
	var mat := menu_bg.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = clampf(menu_k * 1.5, 0.0, 1.0)


# =====================================================================
# Acilis ekrani (poster): Kevin ortada kollarini kavusturmus, parcalar
# carparak gelir; beyin hazir olunca poster dagilir, Kevin masaustune duser.
# =====================================================================

enum { SPLASH_NONE, SPLASH_WAIT, SPLASH_SHOW, SPLASH_OUT }
const SPLASH_MIN := 6.0
const SPLASH_MAX := 9.0
const SPLASH_OUT_TIME := 0.55
var splash_state := SPLASH_NONE
var splash_rect := Rect2i()
var splash_t := 0.0
var splash_out_t := 0.0
var splash_lift := 0.0
var splash_layer: CanvasLayer
var splash_front: Control
var splash_back: Control
var splash_vp: SubViewport
var splash_bg: MeshInstance3D


func _start_splash() -> void:
	var scr := _screen_at_x(_world_to_px(_character_center()).x)
	var h := roundi(scr.size.y * 0.86)
	var sz := Vector2i(roundi(h * 0.8), h)
	splash_rect = Rect2i(scr.position + (scr.size - sz) / 2, sz)
	character.ground_y = (desk_rect.end.y - scr.end.y) / PX_PER_UNIT
	character.root_x = _px_to_world_x(splash_rect.get_center().x)
	character.enter_menu()
	character.menu_yaw = 0.0
	# Kevin ekranin (posterin) ortasinda havada: sonunda buradan masaustune duser
	splash_lift = _px_to_world(Vector2(splash_rect.get_center())).y - character.ground_y - 1.0
	character.menu_lift = splash_lift + 3.0
	character.play_emote("fold_arms", 999.0)
	character.hold_pose = true
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	get_window().size = splash_rect.size
	DisplayServer.window_set_position(splash_rect.position)
	splash_state = SPLASH_WAIT


func _build_splash(vp: Vector2) -> void:
	# Arka katman: SubViewport -> Kevin'in arkasinda 3B duzlem
	splash_vp = SubViewport.new()
	splash_vp.size = Vector2i(vp)
	splash_vp.transparent_bg = true
	splash_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(splash_vp)
	Splash.lang = I18n.code_of(Settings.load_brain())
	splash_back = Splash.make_back(vp)
	splash_vp.add_child(splash_back)
	splash_bg = MeshInstance3D.new()
	splash_bg.mesh = QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = splash_vp.get_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	splash_bg.material_override = mat
	splash_bg.position = Vector3(0, 0, -40)
	camera.add_child(splash_bg)

	# On katman
	splash_layer = CanvasLayer.new()
	add_child(splash_layer)
	splash_front = Splash.new()
	splash_layer.add_child(splash_front)
	splash_front.build(vp)
	Splash.animate_in(splash_back, 0.0)
	Splash.animate_in(splash_front, 0.0)


func _splash_camera(vp: Vector2, k: float) -> void:
	# Kevin posterin ortasinda, boyunun %60'i kadar
	var zoom_final := 0.6 * vp.y / (2.0 * PX_PER_UNIT)
	var zoom := lerpf(zoom_final, 1.0, k)
	var p := Vector3(character.root_x, character.ground_y + splash_lift + 1.0, 0)
	var c1 := Vector3(p.x, p.y + 0.05 * vp.y / (PX_PER_UNIT * zoom_final), 0)
	var c0 := _px_to_world(Vector2(splash_rect.get_center()))
	var c := c1.lerp(c0, k)
	camera.position = Vector3(c.x, c.y, 30)
	camera.size = vp.y / (PX_PER_UNIT * zoom)
	if splash_bg:
		# Poster dunyada sabit boyutta: kamera uzaklastikca kuculup kaybolur
		(splash_bg.mesh as QuadMesh).size = Vector2(vp.x, vp.y) / (PX_PER_UNIT * zoom_final)


func _update_splash(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if splash_state == SPLASH_WAIT:
		if absf(vp.x - splash_rect.size.x) < 4 and absf(vp.y - splash_rect.size.y) < 4:
			_build_splash(vp)
			splash_state = SPLASH_SHOW
			splash_t = 0.0
		else:
			return

	if splash_state == SPLASH_SHOW:
		splash_t += delta
		# Kevin yukaridan dusup yerine oturur (hafif sekme)
		var k := clampf((splash_t - 0.2) / 1.0, 0.0, 1.0)
		character.menu_lift = splash_lift + 3.0 * (1.0 - ease(k, 0.35)) - sin(k * PI) * 0.15 * (1.0 if k < 1.0 else 0.0)
		var ready_brain: bool = brain == null or brain.connected
		var prog := minf(splash_t / SPLASH_MIN, 0.9 if not ready_brain else 1.0)
		splash_front.set_progress(prog, Splash.tx("splash_ready") if ready_brain and splash_t >= SPLASH_MIN else Splash.tx("splash_loading"))
		if (ready_brain and splash_t >= SPLASH_MIN) or splash_t >= SPLASH_MAX:
			_end_splash()
		_splash_camera(vp, 0.0)
	elif splash_state == SPLASH_OUT:
		splash_out_t += delta
		var k := smoothstep(0.0, 1.0, splash_out_t / SPLASH_OUT_TIME)
		_splash_camera(vp, k)
		(splash_bg.material_override as StandardMaterial3D).albedo_color.a = 1.0 - k
		if splash_out_t >= SPLASH_OUT_TIME:
			_finish_splash()


func _end_splash() -> void:
	if splash_state != SPLASH_SHOW:
		return
	splash_state = SPLASH_OUT
	splash_out_t = 0.0
	Splash.animate_out(splash_front)
	Splash.animate_out(splash_back)


func _finish_splash() -> void:
	splash_state = SPLASH_NONE
	if splash_layer:
		splash_layer.queue_free()
	if splash_vp:
		splash_vp.queue_free()
	if splash_bg:
		splash_bg.queue_free()
	splash_layer = null
	splash_vp = null
	splash_bg = null
	# Kevin poster yerinde havada: oradan masaustune duser, sonra kalkar
	character.emote = null
	character.hold_pose = false
	character.start_ragdoll()
	character.menu_lift = 0.0
	get_window().size = WIN_SIZE
	camera.size = WIN_SIZE.y / PX_PER_UNIT
	win_pos = _desired_window_pos()
	_apply_window()
	# Ilk kurulum: API anahtari yoksa (ve yerel model secili degilse) Kevin
	# kalkinca menu Yapay Zeka sayfasinda acilir; herkes kendi anahtarini girer
	if brain and Menu.brain_needs_key(Settings.load_brain()):
		onboard_tab = "yapay_zeka"


func _process(delta: float) -> void:
	if splash_state != SPLASH_NONE:
		_update_splash(delta)
		_process_shots(delta)
		return
	if test_menu != "":
		test_menu_clock += delta
		if test_menu_clock > 1.0 and test_menu_clock < 2.0 and menu_state == MENU_CLOSED and character.mode == 0:
			_open_menu()
		if menu_ui and test_menu_clock > 1.5:
			menu_ui._select_tab(test_menu)
		if test_menu_clock > 5.0 and test_menu_clock < 5.1:
			_close_menu()
		if test_diag and Engine.get_process_frames() % 20 == 0:
			print("MENU t=%.2f durum=%d k=%.2f vp=%s mod=%d" % [test_menu_clock, menu_state, menu_k, str(get_viewport().get_visible_rect().size), character.mode])
	if menu_state != MENU_CLOSED:
		_update_menu(delta)
		_process_shots(delta)
		return
	if onboard_tab != "" and character.mode == 0:
		_open_menu()
	_check_screens(delta)
	_update_character_screen()
	if test_emote == "wall_sit" and character.mode == 0 and character.after_walk == "" and character.anim_state != "emote":
		character._go_wall_sit()
	elif test_emote != "" and test_emote != "wall_sit" and character.mode == 0 and character.anim_state != "emote":
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
			if test_led:
				_press_body(body, point)
			else:
				_grab_body(body, point)
	if led:
		# Sendeleme testi: yavasca saga cek, sonra yukari silkele
		var lt := test_time - 0.8
		var target := test_grab_origin + Vector3(minf(lt, 2.2) * 0.9, 0, 0)
		if lt > 2.6:
			target.y += (lt - 2.6) * 6.0
		_update_led(target)
		return
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



func _run_diag(delta: float) -> void:
	diag_clock += delta
	if diag_clock < 0.5:
		return
	diag_clock = 0.0
	var b: Dictionary = character.bodies
	var c := _character_center()
	var cpx := _world_to_px(c)
	var screen := _screen_at_x(cpx.x)
	var head_px := _world_to_px(b["head"].global_position)
	print("DIAG t=%.1f mod=%s durum=%s  govde_x=%.2f  sinir=%s  kafa_px_x=%.0f  ekran=%d..%d  pencere=%s  bosluk=%.2fpx" % [
		test_time, ["ANIMATED", "RAGDOLL", "GETTING_UP", "LED"][character.mode], character.anim_state,
		c.x, str(character.bounds), head_px.x, screen.position.x, screen.end.x, str(Vector2i(win_pos)),
		character.joint_gaps().values().max()])
	if character.mode == 1:
		var e := 0.0
		for pb in character.bodies.values():
			e += pb.linear_velocity.length_squared()
		print("   enerji=%.3f  settle=%.2f  released=%.2f" % [e, character.settle_timer, character.released_for])


func _process_shots(delta: float) -> void:
	if shot_prefix == "":
		return
	shot_clock += delta
	if shot_index < shot_times.size() and shot_clock >= shot_times[shot_index]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shot_prefix, shot_index])
		shot_index += 1
		if shot_index >= shot_times.size():
			get_tree().quit()
