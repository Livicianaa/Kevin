extends Node
## Beyinle (Electron, --brain) baglanti. Beyin sesi dinliyor, Groq ile
## konusuyor, Piper ile seslendiriyor; ne yaptigini (dinliyor, dusunuyor,
## konusuyor...) yerel bir TCP baglantisiyla buraya bildiriyor, govde de
## Kevin'i ona gore oynatiyor.
##
## Kevin acilinca beyin calismiyorsa onu gorunmez olarak baslatir, Kevin
## kapaninca kapatir. Beyin de govde baglantisi koparsa birkac saniyede kapanir.

signal state_changed(state: String)
signal played(name: String)
signal said(text: String)
signal heard(text: String)
signal mood(name: String)
signal beat(bpm: float, energy: float, age: float)

const PORT := 47630
## Once calisan bir beyin var mi diye bu kadar bekle, yoksa baslat
const SPAWN_AFTER := 1.5

var peer := StreamPeerTCP.new()
var buffer := ""
var connected := false
var retry := 0.0
var waited := 0.0
var spawned := false
var brain_pid := -1
var enabled := true


func _ready() -> void:
	_connect()


func _connect() -> void:
	peer = StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)


## Paketlenmis surumde (AppImage / Windows) govde baska bir klasore kopyalaniyor;
## uygulamanin yeri ve Electron'un yolu ortam degiskeniyle geliyor
static func project_root() -> String:
	var env := OS.get_environment("KEVIN_ROOT")
	if env != "":
		return env
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


func _spawn() -> void:
	spawned = true
	var root := project_root()
	var electron := OS.get_environment("KEVIN_ELECTRON")
	var args := ["--brain"]
	if electron == "":
		electron = root.path_join("node_modules/.bin/electron")
		if OS.get_name() == "Windows":
			electron = root.path_join("node_modules/electron/dist/electron.exe")
		args = [root, "--brain"]
	elif OS.get_name() == "Linux":
		# AppImage'da Chromium sandbox'i kurulamiyor (SUID yok, bazi dagitimlar
		# kullanici ad alanini kisitliyor)
		args.append("--no-sandbox")
	if not FileAccess.file_exists(electron):
		push_warning("[kevin] beyin bulunamadi: %s (npm install gerekli)" % electron)
		return
	brain_pid = OS.create_process(electron, args)
	print("[kevin] beyin baslatildi (pid %d)" % brain_pid)


func stop() -> void:
	if brain_pid > 0:
		OS.kill(brain_pid)
		brain_pid = -1


func send(event: Dictionary) -> void:
	if connected:
		peer.put_data((JSON.stringify(event) + "\n").to_utf8_buffer())


func _process(delta: float) -> void:
	if not enabled:
		return
	peer.poll()
	var st := peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			print("[kevin] beyne baglandi")
		var n := peer.get_available_bytes()
		if n > 0:
			var res: Array = peer.get_data(n)
			if res[0] == OK:
				buffer += (res[1] as PackedByteArray).get_string_from_utf8()
				_drain()
		return

	if connected:
		connected = false
		print("[kevin] beyin baglantisi koptu")
		state_changed.emit("idle")
	waited += delta
	if not spawned and waited >= SPAWN_AFTER:
		_spawn()
	if st != StreamPeerTCP.STATUS_CONNECTING:
		retry -= delta
		if retry <= 0.0:
			retry = 1.0
			_connect()


func _drain() -> void:
	while buffer.contains("\n"):
		var i := buffer.find("\n")
		var line := buffer.substr(0, i).strip_edges()
		buffer = buffer.substr(i + 1)
		if line == "":
			continue
		var msg = JSON.parse_string(line)
		if not (msg is Dictionary):
			continue
		match str(msg.get("type", "")):
			"state":
				state_changed.emit(str(msg.get("state", "idle")))
			"play":
				played.emit(str(msg.get("name", "")))
			"say":
				said.emit(str(msg.get("text", "")))
			"heard":
				heard.emit(str(msg.get("text", "")))
			"mood":
				mood.emit(str(msg.get("mood", "")))
			"beat":
				beat.emit(float(msg.get("bpm", 0.0)), float(msg.get("energy", 0.5)), float(msg.get("age", 0.0)))
