extends RefCounted
## Ayar dosyalari.
##  body.json   - govdenin ayarlari (skin, model, boyut, davranis)
##  config.json - BEYNIN ayarlari (Electron tarafi okuyor: saglayici, model,
##                API anahtari, isim, kisilik...). Menu sadece bildigi alanlari
##                gunceller, digerlerine dokunmaz.

const BODY_DEFAULTS := {
	"skin": "res://skins/totem.png",
	"slim": false,
	"scale": 1.0,
	"walk": 1.0,
	"emotes": 1.0,
	"look": true,
	"wall_sit": true,
	"fun": true,
}

## Beynin sagladigi saglayicilar (main.js PROVIDERS ile ayni)
const PROVIDERS := {
	"groq": {"label": "Groq", "model": "qwen/qwen3.8-27b"},
	"gemini": {"label": "Gemini", "model": "gemini-2.5-flash"},
	"nvidia": {"label": "NVIDIA", "model": "meta/llama-3.3-70b-instruct"},
	"ollama": {"label": "Ollama (yerel)", "model": "qwen3:8b", "local": true},
}


## Electron'un userData klasoruyle ayni yer
static func config_dir() -> String:
	var base := ""
	if OS.get_name() == "Windows":
		base = OS.get_environment("APPDATA")
	else:
		base = OS.get_environment("XDG_CONFIG_HOME")
		if base == "":
			base = OS.get_environment("HOME").path_join(".config")
	return base.path_join("kevin-pc-version")


static func skins_dir() -> String:
	return config_dir().path_join("skins")


static func _read(file_name: String) -> Dictionary:
	var path := config_dir().path_join(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _write(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(config_dir())
	var f := FileAccess.open(config_dir().path_join(file_name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func load_body() -> Dictionary:
	var out := BODY_DEFAULTS.duplicate()
	out.merge(_read("body.json"), true)
	return out


static func save_body(data: Dictionary) -> void:
	_write("body.json", data)


static func load_brain() -> Dictionary:
	return _read("config.json")


## Sadece verilen alanlari degistir; dosyadaki diger alanlar korunur
static func save_brain(changes: Dictionary) -> void:
	var cfg := _read("config.json")
	cfg.merge(changes, true)
	_write("config.json", cfg)


## Paketteki ve kullanicinin skin'leri (png yollari)
static func list_skins() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://skins"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if f.ends_with(".png") and not out.has("res://skins/" + f):
			out.append("res://skins/" + f)
	if DirAccess.dir_exists_absolute(skins_dir()):
		for f in DirAccess.get_files_at(skins_dir()):
			if f.to_lower().ends_with(".png"):
				out.append(skins_dir().path_join(f))
	return out


static func load_skin(path: String) -> Texture2D:
	if path.begins_with("res://"):
		var t = load(path)
		if t is Texture2D:
			return t
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and img.get_width() == 64 and img.get_height() >= 32:
			if img.get_height() == 32:
				# Eski (64x32) skin: alt yariyi bos ekle, sol kol/bacak sagdan kopya
				var full := Image.create(64, 64, false, Image.FORMAT_RGBA8)
				full.blit_rect(img, Rect2i(0, 0, 64, 32), Vector2i.ZERO)
				full.blit_rect(img, Rect2i(0, 16, 16, 16), Vector2i(16, 48))
				full.blit_rect(img, Rect2i(40, 16, 16, 16), Vector2i(32, 48))
				img = full
			return ImageTexture.create_from_image(img)
	return load(BODY_DEFAULTS.skin)


## Skin'i kullanicinin skin klasorune kopyala, yeni yolu dondur
static func import_skin(source: String) -> String:
	DirAccess.make_dir_recursive_absolute(skins_dir())
	var target := skins_dir().path_join(source.get_file())
	DirAccess.copy_absolute(source, target)
	return target
