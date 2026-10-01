extends Control
## Kevin'in menusu (karaktere sag tik). Arka plan YOK: Kevin ve arayuz
## parcalari masaustunun ustunde duruyor (livi: "arka plan olmasin").
## Sagda alt alta kategori dugmeleri, altinda skin kartlari, en altta
## Kaydet/Kapat; bir kategoriye basinca ayarlari dugmelerin solunda acilir.
## Renk: krem tonlari, koyu kahve kenar (referans: oyun karakter ekrani).

signal close_requested
signal saved(needs_reload: bool)
signal skin_chosen(path: String)
signal action(name: String)

const Settings := preload("res://settings.gd")

const C_INK := Color("3b2a1f")
const C_CREAM := Color("f6ecd6")
const C_CREAM_2 := Color("eadbb9")
const C_CREAM_3 := Color("dcc799")
const C_TEXT := Color("3b2a1f")
const C_MUTED := Color("7a6450")
const C_CARAMEL := Color("d99a4e")
const C_GREEN := Color("8cc152")
const C_BROWN := Color("b57a50")
const C_SELECT := Color("f0b44c")

var body_cfg := {}
var brain_cfg := {}
var fs := 15

var column: Control
var left_bar: Control
var card: PanelContainer
var card_title: Label
var cat_buttons := {}
var pages := {}
var current_cat := ""
var skin_grid: GridContainer
var skin_cards := {}
var skin_cell := 64.0

var slim_btns := []
var scale_slider: HSlider
var scale_label: Label
var mode_btns := []
var provider_opt: OptionButton
var provider_row: Control
var model_edit: LineEdit
var key_edit: LineEdit
var key_row: Control
var name_edit: LineEdit
var nick_edit: LineEdit
var hands_check: CheckButton
var session_slider: HSlider
var session_label: Label
var persona_edit: TextEdit
var walk_slider: HSlider
var emote_slider: HSlider
var look_check: CheckButton
var wallsit_check: CheckButton
var fun_check: CheckButton
var auto_rotate_btn: Button

var original_body := {}
var view := Vector2.ZERO


func build(size_px: Vector2) -> void:
	view = size_px
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fs = int(clampf(view.y / 60.0, 12.0, 18.0))
	theme = _make_theme()

	body_cfg = Settings.load_body()
	original_body = body_cfg.duplicate()
	brain_cfg = Settings.load_brain()

	var pad := view.y * 0.03
	var col_w := clampf(view.x * 0.22, 220.0, 300.0)
	column = _build_column(Vector2(col_w, view.y - pad * 2))
	column.position = Vector2(view.x - col_w - pad, pad)
	add_child(column)

	card = _build_card(Vector2(clampf(view.x * 0.33, 340.0, 480.0), view.y - pad * 2))
	card.position = Vector2(column.position.x - card.size.x - pad * 0.6, pad)
	card.visible = false
	add_child(card)

	left_bar = _build_left_bar()
	left_bar.position = Vector2(pad, view.y * 0.2)
	add_child(left_bar)

	_animate_in()


# =====================================================================
# Stil
# =====================================================================

func _font(weight := 800) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Segoe UI", "Arial"])
	f.font_weight = weight
	return f


## Koyu kahve kalin kenar + alttan "dudak"
func _box(bg: Color, radius := 10, border := C_INK, bw := 3, lip := 0, lip_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = fs * 0.7
	sb.content_margin_right = fs * 0.7
	sb.content_margin_top = fs * 0.35
	sb.content_margin_bottom = fs * 0.35
	if lip > 0:
		sb.shadow_color = lip_color if lip_color.a > 0.0 else bg.darkened(0.35)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(0, lip)
	return sb


func _outlined(node: Control, size_mul := 1.0, weight := 800) -> void:
	node.add_theme_font_override("font", _font(weight))
	node.add_theme_font_size_override("font_size", int(fs * size_mul))
	node.add_theme_constant_override("outline_size", maxi(3, int(fs * 0.3)))
	node.add_theme_color_override("font_outline_color", C_INK)
	node.add_theme_color_override("font_color", Color.WHITE)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(600)
	t.default_font_size = fs
	t.set_color("font_color", "Label", C_TEXT)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, C_TEXT)
		t.set_color("font_pressed_color", cls, C_TEXT)
		t.set_color("font_focus_color", cls, C_TEXT)
		t.set_color("font_hover_pressed_color", cls, C_TEXT)
		t.set_stylebox("normal", cls, _box(C_CREAM_2, 8, C_INK, 2, 3))
		t.set_stylebox("hover", cls, _box(C_CREAM, 8, C_INK, 2, 3))
		t.set_stylebox("pressed", cls, _box(C_CREAM_3, 8, C_INK, 2, 1))
		t.set_stylebox("hover_pressed", cls, _box(C_CREAM_3, 8, C_INK, 2, 1))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, _box(Color("fffaf0"), 6, C_CREAM_3, 2))
		t.set_stylebox("focus", cls, _box(Color("fffaf0"), 6, C_CARAMEL, 2))
		t.set_color("font_color", cls, C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	t.set_color("font_placeholder_color", "TextEdit", C_MUTED)
	t.set_stylebox("slider", "HSlider", _box(C_CREAM_3, 6, C_INK, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(C_CARAMEL, 6, C_INK, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(C_CARAMEL.lightened(0.1), 6, C_INK, 2))
	t.set_stylebox("panel", "PopupMenu", _box(C_CREAM, 6, C_INK, 2))
	t.set_color("font_color", "PopupMenu", C_TEXT)
	return t


func _label(text: String, size_mul := 1.0, color := C_TEXT, wrap := false, weight := 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(fs * size_mul))
	l.add_theme_color_override("font_color", color)
	if weight != 600:
		l.add_theme_font_override("font", _font(weight))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = fs * 8
	return l


func _row(title: String, control: Control, hint := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.3))
	v.add_child(_label(title, 0.95, C_TEXT, false, 800))
	v.add_child(control)
	if hint != "":
		v.add_child(_label(hint, 0.78, C_MUTED, true))
	var sep := ColorRect.new()
	sep.color = C_CREAM_3
	sep.custom_minimum_size.y = 2
	v.add_child(sep)
	return v


## Birlesik secim dugmeleri
func _segment(labels: Array, selected: int, on_pick: Callable) -> Array:
	var group := ButtonGroup.new()
	var out := []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var first := i == 0
		var last := i == labels.size() - 1
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var on: bool = st.contains("pressed")
			var sb := _box(C_SELECT if on else (C_CREAM if st == "hover" else C_CREAM_2), 0, C_INK, 2)
			sb.corner_radius_top_left = 8 if first else 0
			sb.corner_radius_bottom_left = 8 if first else 0
			sb.corner_radius_top_right = 8 if last else 0
			sb.corner_radius_bottom_right = 8 if last else 0
			if not first:
				sb.border_width_left = 0
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_font_override("font", _font(800))
		b.pressed.connect(on_pick.bind(i))
		out.append(b)
	return out


func _segment_box(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	for b in buttons:
		h.add_child(b)
	return h


func _slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size.y = fs * 1.3
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _game_button(text: String, color: Color, height_mul := 2.2) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = fs * height_mul
	_outlined(b, 1.05, 900)
	b.add_theme_stylebox_override("normal", _box(color, 10, C_INK, 3, 5, color.darkened(0.45)))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.1), 10, C_INK, 3, 5, color.darkened(0.45)))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.1), 10, C_INK, 3, 1, color.darkened(0.45)))
	b.add_theme_stylebox_override("hover_pressed", _box(color.darkened(0.1), 10, C_INK, 3, 1, color.darkened(0.45)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	return b


# =====================================================================
# Sag sutun: isim, kategoriler, skin kartlari, Kaydet/Kapat
# =====================================================================

func _build_column(size_px: Vector2) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = size_px
	v.size = size_px
	v.add_theme_constant_override("separation", int(fs * 0.55))

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _box(C_CREAM, 10, C_INK, 3, 4))
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", int(fs * 0.5))
	var badge := PanelContainer.new()
	var bsb := _box(C_CARAMEL, 5, C_INK, 2)
	bsb.skew = Vector2(0.25, 0)
	badge.add_theme_stylebox_override("panel", bsb)
	var bl := _label("AI", 0.85)
	_outlined(bl, 0.85)
	badge.add_child(bl)
	ph.add_child(badge)
	var nm := _label(str(brain_cfg.get("name", "Kevin")), 1.35, C_TEXT, false, 900)
	ph.add_child(nm)
	plate.add_child(ph)
	v.add_child(plate)

	var cats := [["karakter", "Karakter"], ["yapay_zeka", "Yapay Zeka"], ["davranis", "Davranış"], ["hakkinda", "Hakkında"]]
	for c in cats:
		var b := _game_button(c[1], C_CARAMEL, 2.1)
		b.toggle_mode = true
		b.add_theme_stylebox_override("pressed", _box(C_SELECT, 10, C_INK, 3, 1, C_CARAMEL.darkened(0.45)))
		b.add_theme_stylebox_override("hover_pressed", _box(C_SELECT, 10, C_INK, 3, 1, C_CARAMEL.darkened(0.45)))
		b.pressed.connect(_toggle_category.bind(c[0], c[1]))
		cat_buttons[c[0]] = b
		v.add_child(b)

	# Karakterler (skin kartlari)
	var skins_box := PanelContainer.new()
	skins_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skins_box.add_theme_stylebox_override("panel", _box(C_CREAM, 10, C_INK, 3, 4))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", int(fs * 0.4))
	sv.add_child(_label("Karakterler", 0.95, C_TEXT, false, 800))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	skin_grid = GridContainer.new()
	skin_grid.columns = 3
	skin_grid.add_theme_constant_override("h_separation", int(fs * 0.4))
	skin_grid.add_theme_constant_override("v_separation", int(fs * 0.4))
	scroll.add_child(skin_grid)
	skin_cell = (size_px.x - fs * 3.0) / 3.0
	for path in Settings.list_skins():
		_add_skin_card(path)
	var add := Button.new()
	add.text = "+"
	add.custom_minimum_size = Vector2(skin_cell, skin_cell)
	add.add_theme_font_size_override("font_size", int(fs * 1.8))
	add.add_theme_font_override("font", _font(900))
	add.tooltip_text = "Skin ekle (png)"
	add.pressed.connect(_pick_skin_file)
	skin_grid.add_child(add)
	skins_box.add_child(sv)
	v.add_child(skins_box)
	_mark_selected_card()

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(fs * 0.5))
	var save := _game_button("Kaydet", C_GREEN, 2.3)
	save.pressed.connect(_on_save)
	foot.add_child(save)
	var close := _game_button("Kapat", C_BROWN, 2.3)
	close.pressed.connect(func(): close_requested.emit())
	foot.add_child(close)
	v.add_child(foot)
	return v


func _add_skin_card(path: String) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(skin_cell, skin_cell)
	btn.tooltip_text = path.get_file().get_basename()
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tex := Settings.load_skin(path)
	for region in [Rect2(8, 8, 8, 8), Rect2(40, 8, 8, 8)]:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = region
		var tr := TextureRect.new()
		tr.texture = at
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = Vector2(skin_cell * 0.17, skin_cell * 0.17)
		tr.size = Vector2(skin_cell * 0.66, skin_cell * 0.66)
		btn.add_child(tr)
	btn.pressed.connect(func():
		body_cfg.skin = path
		_mark_selected_card()
		skin_chosen.emit(path))
	skin_grid.add_child(btn)
	# "+" kartinin onune
	var plus := skin_grid.get_children().filter(func(c): return c is Button and c.text == "+")
	if not plus.is_empty():
		skin_grid.move_child(btn, plus[0].get_index())
	skin_cards[path] = btn


func _mark_selected_card() -> void:
	for p in skin_cards:
		var sel: bool = p == str(body_cfg.skin)
		var sb := _box(C_SELECT if sel else C_CREAM_2, 8, C_INK, 3 if sel else 2, 3)
		for st in ["normal", "hover", "pressed"]:
			skin_cards[p].add_theme_stylebox_override(st, sb)


func _pick_skin_file() -> void:
	# Kevin'in penceresi "hep ustte"; dosya penceresi arkasinda kaliyordu
	get_window().always_on_top = false
	DisplayServer.file_dialog_show("Skin seç", OS.get_environment("HOME"), "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png ; Minecraft skin"]),
		func(ok: bool, paths: PackedStringArray, _f: int):
			get_window().always_on_top = true
			if not ok or paths.is_empty():
				return
			var target := Settings.import_skin(paths[0])
			if not skin_cards.has(target):
				_add_skin_card(target)
			body_cfg.skin = target
			_mark_selected_card()
			skin_chosen.emit(target))


# =====================================================================
# Ayar karti (kategoriye basinca dugmelerin solunda)
# =====================================================================

func _build_card(size_px: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size_px
	p.size = size_px
	p.add_theme_stylebox_override("panel", _box(C_CREAM, 12, C_INK, 3, 5))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.6))
	p.add_child(v)
	var head := HBoxContainer.new()
	card_title = _label("", 1.2, C_TEXT, false, 900)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(card_title)
	var x := Button.new()
	x.text = "X"
	x.add_theme_font_override("font", _font(900))
	x.pressed.connect(func(): _toggle_category(current_cat, ""))
	head.add_child(x)
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	pages["karakter"] = _page_character()
	pages["yapay_zeka"] = _page_ai()
	pages["davranis"] = _page_behaviour()
	pages["hakkinda"] = _page_about()
	for pg in pages.values():
		pg.visible = false
		holder.add_child(pg)
	return p


func _toggle_category(id: String, title: String) -> void:
	if id == current_cat or title == "":
		# Ayni kategoriye tekrar basinca kapanir
		current_cat = ""
		for b in cat_buttons.values():
			b.button_pressed = false
		var tw := create_tween()
		tw.tween_property(card, "modulate:a", 0.0, 0.15)
		tw.tween_callback(func(): card.visible = false)
		return
	current_cat = id
	for k in cat_buttons:
		cat_buttons[k].button_pressed = k == id
	for k in pages:
		pages[k].visible = k == id
	card_title.text = title
	if not card.visible:
		card.visible = true
		var final_x := column.position.x - card.size.x - view.y * 0.018
		card.position.x = final_x + fs * 4
		card.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, "position:x", final_x, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "modulate:a", 1.0, 0.2)


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.65))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _page_character() -> VBoxContainer:
	var v := _page()
	slim_btns = _segment(["Klasik (4 px)", "İnce (3 px)"], 1 if body_cfg.slim else 0,
		func(i): body_cfg.slim = i == 1)
	v.add_child(_row("Kol modeli", _segment_box(slim_btns)))
	var scale_box := HBoxContainer.new()
	scale_slider = _slider(0.6, 2.0, 0.05, float(body_cfg.scale))
	scale_label = _label("", 0.95, C_TEXT, false, 800)
	scale_label.custom_minimum_size.x = fs * 3.4
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_slider.value_changed.connect(func(val):
		body_cfg.scale = val
		scale_label.text = "%%%d" % roundi(val * 100))
	scale_label.text = "%%%d" % roundi(float(body_cfg.scale) * 100)
	scale_box.add_child(scale_slider)
	scale_box.add_child(scale_label)
	v.add_child(_row("Boyut", scale_box, "Kol modeli ve boyut Kaydet'e basınca uygulanır."))
	v.add_child(_label("Skin: sağdaki Karakterler'den seç, + ile kendi png'ni ekle (64x64 Minecraft skin).", 0.8, C_MUTED, true))
	return v


func _page_ai() -> VBoxContainer:
	var v := _page()
	var local: bool = Settings.PROVIDERS.get(str(brain_cfg.get("provider", "groq")), {}).get("local", false)
	mode_btns = _segment(["Bulut (API)", "Yerel (Ollama)"], 1 if local else 0, _on_mode)
	v.add_child(_row("Çalışma şekli", _segment_box(mode_btns), "Bulut: hızlı, internet ve anahtar ister. Yerel: bilgisayarında çalışır, Ollama kurulu olmalı."))

	provider_opt = OptionButton.new()
	for id in Settings.PROVIDERS:
		if not Settings.PROVIDERS[id].get("local", false):
			provider_opt.add_item(Settings.PROVIDERS[id].label)
			provider_opt.set_item_metadata(provider_opt.item_count - 1, id)
			if id == str(brain_cfg.get("provider", "")):
				provider_opt.select(provider_opt.item_count - 1)
	provider_opt.item_selected.connect(func(_i): _update_model_placeholder())
	provider_row = _row("Sağlayıcı", provider_opt)
	v.add_child(provider_row)

	model_edit = LineEdit.new()
	model_edit.text = str(brain_cfg.get("model", ""))
	v.add_child(_row("Model", model_edit, "Boş bırakırsan sağlayıcının varsayılanı."))

	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "Kayıtlı anahtar var (değiştirmek için yaz)" if str(brain_cfg.get("apiKey", "")) != "" else "API anahtarını yapıştır"
	key_row = _row("API anahtarı", key_edit, "Sadece bu bilgisayarda, ayar dosyasında durur.")
	v.add_child(key_row)

	name_edit = LineEdit.new()
	name_edit.text = str(brain_cfg.get("name", "Kevin"))
	v.add_child(_row("İsim", name_edit, "Bu isimle seslenince uyanır."))

	nick_edit = LineEdit.new()
	nick_edit.text = ", ".join(PackedStringArray(brain_cfg.get("nicknames", [])))
	nick_edit.placeholder_text = "kev, kevo"
	v.add_child(_row("Lakaplar", nick_edit, "Virgülle ayır."))

	hands_check = CheckButton.new()
	hands_check.text = "Eller serbest dinleme"
	hands_check.button_pressed = brain_cfg.get("handsFree", true) != false
	v.add_child(hands_check)

	var sess_box := HBoxContainer.new()
	var sess_s := float(brain_cfg.get("voiceSessionMs", 20000)) / 1000.0
	session_slider = _slider(5, 60, 1, sess_s)
	session_label = _label("%d sn" % int(sess_s), 0.95, C_TEXT, false, 800)
	session_label.custom_minimum_size.x = fs * 3.4
	session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	session_slider.value_changed.connect(func(val): session_label.text = "%d sn" % int(val))
	sess_box.add_child(session_slider)
	sess_box.add_child(session_label)
	v.add_child(_row("Sohbet süresi", sess_box, "Adını söyledikten sonra ne kadar dinlesin."))

	persona_edit = TextEdit.new()
	persona_edit.text = str(brain_cfg.get("persona", ""))
	persona_edit.placeholder_text = "Boş: varsayılan kişilik (esprili, samimi, Türkçe)."
	persona_edit.custom_minimum_size.y = fs * 6
	persona_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_row("Kişilik", persona_edit))

	v.add_child(_label("Not: beyin (ses, sohbet, araçlar) henüz bu gövdeye bağlı değil; ayarlar kaydediliyor, bağlantı sıradaki adım.", 0.78, C_MUTED, true))
	_on_mode(1 if local else 0)
	return v


func _page_behaviour() -> VBoxContainer:
	var v := _page()
	walk_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.walk))
	v.add_child(_row("Yürüme sıklığı", walk_slider))
	emote_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.emotes))
	v.add_child(_row("Emote sıklığı", emote_slider))
	look_check = CheckButton.new()
	look_check.text = "Fareyi arada merak edip baksın"
	look_check.button_pressed = body_cfg.look
	v.add_child(look_check)
	wallsit_check = CheckButton.new()
	wallsit_check.text = "Kenara yaslanıp otursun"
	wallsit_check.button_pressed = body_cfg.wall_sit
	v.add_child(wallsit_check)
	fun_check = CheckButton.new()
	fun_check.text = "Eğlenceli emote'lar (dans vb.)"
	fun_check.button_pressed = body_cfg.fun
	v.add_child(fun_check)
	return v


func _page_about() -> VBoxContainer:
	var v := _page()
	v.add_child(_label("Masaüstünde yaşayan, konuşan ve bilgisayarını kullanabilen yapay zeka arkadaşı.", 0.95, C_TEXT, true))
	v.add_child(_label("Created by Liviciana", 1.0, C_CARAMEL.darkened(0.2), false, 900))
	v.add_child(_label("Animasyonlar: Fresh Animations (kullanıcının paketi), Emotecraft emote'ları (CC0), Quaternius Universal Animation Library 2 (CC0).", 0.82, C_MUTED, true))
	v.add_child(_label("Menü: karaktere sağ tık. Karakteri sürükle: döndür. Esc: kapat.", 0.82, C_MUTED, true))
	return v


func _on_mode(i: int) -> void:
	var local := i == 1
	if provider_row:
		provider_row.visible = not local
	if key_row:
		key_row.visible = not local
	_update_model_placeholder()


func _update_model_placeholder() -> void:
	if model_edit:
		model_edit.placeholder_text = Settings.PROVIDERS.get(_current_provider(), {}).get("model", "")


func _current_provider() -> String:
	if mode_btns.size() > 1 and mode_btns[1].button_pressed:
		return "ollama"
	if provider_opt and provider_opt.selected >= 0:
		return str(provider_opt.get_item_metadata(provider_opt.selected))
	return "groq"


## Test icin: kategoriyi ac
func _select_tab(id: String) -> void:
	var titles := {"karakter": "Karakter", "yapay_zeka": "Yapay Zeka", "davranis": "Davranış", "hakkinda": "Hakkında"}
	if id != current_cat and titles.has(id):
		_toggle_category(id, titles[id])


# =====================================================================
# Sol yuvarlak dugmeler: daire + cizilmis ikon + altina tasan etiket
# =====================================================================

class RoundIcon:
	extends Control
	var kind := ""
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.22
		var ink := Color("3b2a1f")
		var fill := Color("fffaf0")
		match kind:
			"rotate":
				draw_arc(c, r, 0.4, TAU - 0.6, 24, ink, r * 0.55)
				draw_arc(c, r, 0.4, TAU - 0.6, 24, fill, r * 0.3)
				var tip := c + Vector2(cos(-0.6), sin(-0.6)) * r
				var head := PackedVector2Array([tip + Vector2(-r * 0.45, -r * 0.35), tip + Vector2(r * 0.45, -r * 0.1), tip + Vector2(-r * 0.05, r * 0.45)])
				draw_colored_polygon(head, fill)
				var outline := head.duplicate()
				outline.append(head[0])
				draw_polyline(outline, ink, 2.0)
			"emote":
				var pts := PackedVector2Array()
				for i in 10:
					var a := -PI / 2 + i * TAU / 10.0
					var rr := r * (1.2 if i % 2 == 0 else 0.5)
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, fill)
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, ink, 2.5)
			"reset":
				draw_circle(c, r * 1.05, ink)
				draw_circle(c, r * 0.8, fill)
				draw_line(c, c + Vector2(0, -r * 0.6), ink, 2.5)
				draw_line(c, c + Vector2(r * 0.45, 0), ink, 2.5)


func _round_button(text: String, icon: String) -> Control:
	var size_px := fs * 3.2
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px + fs * 0.6)
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.size = Vector2(size_px, size_px)
	var r := int(size_px / 2)
	b.add_theme_stylebox_override("normal", _box(C_CARAMEL, r, C_INK, 3, 4))
	b.add_theme_stylebox_override("hover", _box(C_CARAMEL.lightened(0.12), r, C_INK, 3, 4))
	b.add_theme_stylebox_override("pressed", _box(C_SELECT, r, C_INK, 3, 1))
	b.add_theme_stylebox_override("hover_pressed", _box(C_SELECT, r, C_INK, 3, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	holder.add_child(b)
	var ic := RoundIcon.new()
	ic.kind = icon
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size = Vector2(size_px, size_px * 0.8)
	holder.add_child(ic)
	var l := _label(text, 0.78)
	_outlined(l, 0.78)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(size_px, fs * 1.4)
	l.position = Vector2(0, size_px - fs * 0.9)
	holder.add_child(l)
	holder.set_meta("button", b)
	return holder


func _build_left_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.8))
	var rot := _round_button("Döndür", "rotate")
	auto_rotate_btn = rot.get_meta("button")
	auto_rotate_btn.toggle_mode = true
	auto_rotate_btn.toggled.connect(func(on): action.emit("auto_rotate_on" if on else "auto_rotate_off"))
	v.add_child(rot)
	var em := _round_button("Emote", "emote")
	(em.get_meta("button") as Button).pressed.connect(func(): action.emit("emote"))
	v.add_child(em)
	var reset := _round_button("Sıfırla", "reset")
	(reset.get_meta("button") as Button).pressed.connect(func():
		auto_rotate_btn.button_pressed = false
		action.emit("reset"))
	v.add_child(reset)
	return v


# =====================================================================
# Kaydet
# =====================================================================

func _on_save() -> void:
	body_cfg.walk = walk_slider.value
	body_cfg.emotes = emote_slider.value
	body_cfg.look = look_check.button_pressed
	body_cfg.wall_sit = wallsit_check.button_pressed
	body_cfg.fun = fun_check.button_pressed
	Settings.save_body(body_cfg)

	var brain := {
		"provider": _current_provider(),
		"model": model_edit.text.strip_edges(),
		"name": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Kevin",
		"nicknames": Array(nick_edit.text.split(",", false)).map(func(s): return s.strip_edges()).filter(func(s): return s != ""),
		"handsFree": hands_check.button_pressed,
		"voiceSessionMs": int(session_slider.value * 1000),
		"persona": persona_edit.text,
	}
	if key_edit.text.strip_edges() != "":
		brain["apiKey"] = key_edit.text.strip_edges()
	Settings.save_brain(brain)

	var needs_reload: bool = body_cfg.slim != original_body.slim or absf(float(body_cfg.scale) - float(original_body.scale)) > 0.001
	saved.emit(needs_reload)


# =====================================================================
# Giris / cikis: yanlardan
# =====================================================================

func _animate_in() -> void:
	var items := [
		[column, Vector2(view.x * 0.35, 0), 0.1],
		[left_bar, Vector2(-view.x * 0.25, 0), 0.18],
	]
	for it in items:
		var node: Control = it[0]
		var final := node.position
		node.position = final + it[1]
		node.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position", final, 0.5).set_delay(it[2]).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "modulate:a", 1.0, 0.25).set_delay(it[2])


func animate_out(_view: Vector2) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(column, "position:x", column.position.x + view.x * 0.35, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(left_bar, "position:x", -view.x * 0.25, 0.3).set_ease(Tween.EASE_IN)
	if card.visible:
		tw.tween_property(card, "position:x", card.position.x + view.x * 0.35, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	return tw
