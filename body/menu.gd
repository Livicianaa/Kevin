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

## Japon tarzi: washi kagidi, altin-kahve cizgi, vermilyon (hanko kirmizisi),
## murekkep siyahi
const C_INK := Color("2b2118")
const C_CREAM := Color("f6eedc")
const C_CREAM_2 := Color("ece0c4")
const C_CREAM_3 := Color("d9c59a")
const C_TEXT := Color("2b2118")
const C_MUTED := Color("7d6a55")
const C_GOLD := Color("96764a")
const C_RED := Color("c4161c")
const C_CARAMEL := C_RED
const C_GREEN := C_RED
const C_BROWN := C_GOLD
const C_SELECT := C_RED

## Kullanicinin verdigi susler (bin/ui, repoda degil): koseler, ust ayrac,
## dugme plakalari. Yoksa sade cizim.
const UI_DIR := "../bin/ui"
## Kategori -> plaka (sabit); koseler ve ust ayrac her acilista rastgele
const CAT_PLAQUE := {"sohbet": 0, "karakter": 1, "yapay_zeka": 2, "davranis": 3, "hakkinda": 4}

var body_cfg := {}
var brain_cfg := {}
var fs := 15

var column: Control
var left_bar: Control
var main_view: VBoxContainer
var detail_scroll: ScrollContainer
var detail_view: VBoxContainer
var detail_head: Button
var detail_head_holder: Control
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
## Kevin'in duracagi yatay nokta (px): main kamerayi buna gore ayarliyor
var stage_x := 0.0
var col_w := 260.0


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
	var top := _build_decor(pad)
	col_w = clampf(view.x * 0.34, 240.0, 320.0)
	column = _build_column(Vector2(col_w, view.y - top - pad - view.y * 0.08))
	column.position = Vector2(view.x - col_w - pad * 1.4, top)
	add_child(column)

	left_bar = _build_left_bar()
	left_bar.position = Vector2(pad * 1.4, view.y * 0.24)
	add_child(left_bar)
	# Kevin sol dugmelerle sag sutun arasinin ortasinda
	stage_x = (pad + fs * 3.2 + column.position.x) / 2.0

	_animate_in()


# =====================================================================
# Susler: her acilista rastgele kose (sol ust + sag alt) ve ust ayrac
# =====================================================================

var _ui_cache := {}


func _ui_textures(kind: String) -> Array:
	if _ui_cache.has(kind):
		return _ui_cache[kind]
	var dir := ProjectSettings.globalize_path("res://").path_join(UI_DIR).simplify_path().path_join(kind)
	var out := []
	if DirAccess.dir_exists_absolute(dir):
		var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".png"))
		files.sort()
		for f in files:
			var img := Image.load_from_file(dir.path_join(f))
			if img:
				out.append(ImageTexture.create_from_image(img))
	_ui_cache[kind] = out
	return out


## Susleri yerlestir; sutunun baslayacagi y'yi dondurur
func _build_decor(pad: float) -> float:
	var corners := _ui_textures("corners")
	if not corners.is_empty():
		var tex: Texture2D = corners.pick_random()
		var ch := view.y * 0.13
		var cw := ch * tex.get_width() / tex.get_height()
		# Kaynak kose sol altta dik acili: sol ust icin dikey, sag alt icin yatay cevrilir
		for spec in [[Vector2(pad * 0.3, pad * 0.3), false, true], [Vector2(view.x - cw - pad * 0.3, view.y - ch - pad * 0.3), true, false]]:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.size = Vector2(cw, ch)
			tr.position = spec[0]
			tr.flip_h = spec[1]
			tr.flip_v = spec[2]
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(tr)
	var top := pad
	var dividers := _ui_textures("dividers")
	if not dividers.is_empty():
		var tex: Texture2D = dividers.pick_random()
		var dw := minf(view.x * 0.5, tex.get_width() * 1.2)
		var dh := dw * tex.get_height() / tex.get_width()
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(dw, dh)
		tr.position = Vector2((view.x - dw) / 2.0, pad * 0.35)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		top = maxf(top, pad * 0.35 + dh + pad * 0.5)
	return top


## Plaka dugmesi: kullanicinin verdigi suslu cerceve, ici washi kremi
func _plaque_button(text: String, plaque: int, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = height
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_font_override("font", _font(700))
	b.add_theme_font_size_override("font_size", int(fs * 1.05))
	b.add_theme_color_override("font_color", C_INK)
	b.add_theme_color_override("font_hover_color", C_RED)
	b.add_theme_color_override("font_pressed_color", C_RED)
	b.add_theme_color_override("font_hover_pressed_color", C_RED)
	var plaques := _ui_textures("plaques")
	var fill := Panel.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(C_CREAM, 0.96)
	fsb.set_corner_radius_all(3)
	if plaques.is_empty():
		fsb.border_color = C_GOLD
		fsb.set_border_width_all(2)
	fill.add_theme_stylebox_override("panel", fsb)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.show_behind_parent = true
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not plaques.is_empty():
		fill.offset_left = height * 0.22
		fill.offset_right = -height * 0.22
		fill.offset_top = height * 0.14
		fill.offset_bottom = -height * 0.14
	b.add_child(fill)
	if not plaques.is_empty():
		var tr := TextureRect.new()
		tr.texture = plaques[plaque % plaques.size()]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.show_behind_parent = true
		b.add_child(tr)
		b.mouse_entered.connect(func(): tr.modulate = Color(1.45, 0.55, 0.5))
		b.mouse_exited.connect(func(): tr.modulate = Color.WHITE)
	return b


func _plaque_height() -> float:
	return col_w / 4.7


# =====================================================================
# Stil
# =====================================================================

func _font(weight := 800) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Noto Serif", "Liberation Serif", "DejaVu Serif", "Georgia", "Times New Roman"])
	f.font_weight = weight
	return f


## Koyu kahve kalin kenar + alttan "dudak"
func _box(bg: Color, radius := 10, border := C_INK, bw := 3, lip := 0, lip_color := Color.TRANSPARENT) -> StyleBoxFlat:
	radius = mini(radius, 4)
	lip = mini(lip, 2)
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
	node.add_theme_constant_override("outline_size", 0)
	node.add_theme_color_override("font_color", C_CREAM)


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
		t.set_stylebox("normal", cls, _box(C_CREAM, 3, C_GOLD, 1, 0))
		t.set_stylebox("hover", cls, _box(Color("fffaf0"), 3, C_RED, 1, 0))
		t.set_stylebox("pressed", cls, _box(C_CREAM_2, 3, C_GOLD, 1, 0))
		t.set_stylebox("hover_pressed", cls, _box(C_CREAM_2, 3, C_RED, 1, 0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, _box(Color("fffaf0"), 2, C_CREAM_3, 1))
		t.set_stylebox("focus", cls, _box(Color("fffaf0"), 2, C_RED, 1))
		t.set_color("font_color", cls, C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	t.set_color("font_placeholder_color", "TextEdit", C_MUTED)
	var track := _box(C_CREAM_3, 2, C_GOLD, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _box(C_RED, 2, C_RED, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(C_RED.lightened(0.1), 2, C_RED, 0))
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
	v.add_child(_divider_line())
	return v


## Ince altin cizgi, ortasinda kucuk kirmizi baklava
class DividerLine:
	extends Control
	func _draw() -> void:
		var y := size.y / 2.0
		var c := Vector2(size.x / 2.0, y)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("c8ad7a"), 1.0)
		var d := 4.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color("c4161c"))


func _divider_line() -> Control:
	var d := DividerLine.new()
	d.custom_minimum_size.y = 10
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return d


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
			var sb := _box(C_RED if on else (Color("fffaf0") if st == "hover" else C_CREAM), 0, C_GOLD, 1)
			sb.corner_radius_top_left = 8 if first else 0
			sb.corner_radius_bottom_left = 8 if first else 0
			sb.corner_radius_top_right = 8 if last else 0
			sb.corner_radius_bottom_right = 8 if last else 0
			if not first:
				sb.border_width_left = 0
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_font_override("font", _font(700))
		b.add_theme_color_override("font_pressed_color", C_CREAM)
		b.add_theme_color_override("font_hover_pressed_color", C_CREAM)
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
# Sag sutun: ana menu (isim, kategoriler, karakterler, Kaydet/Kapat) ve
# kategori gorunumu. Kategoriye basinca dugme yavasca yukari kayip baslik
# olur, sutun o kategorinin ayarlarina doner; "Geri" ana menuye dondurur.
# =====================================================================

func _build_column(size_px: Vector2) -> Control:
	var col := Control.new()
	col.custom_minimum_size = size_px
	col.size = size_px
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	main_view = VBoxContainer.new()
	main_view.size = Vector2(size_px.x, 0)
	main_view.add_theme_constant_override("separation", int(fs * 0.25))
	col.add_child(main_view)

	# Isim: plaka + kirmizi muhur (hanko)
	var plate := _plaque_button(str(brain_cfg.get("name", "Kevin")), 5, _plaque_height() * 1.15)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_font_size_override("font_size", int(fs * 1.45))
	plate.add_theme_font_override("font", _font(800))
	var seal := Label.new()
	seal.text = "AI"
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_theme_font_override("font", _font(800))
	seal.add_theme_font_size_override("font_size", int(fs * 0.75))
	seal.add_theme_color_override("font_color", C_CREAM)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = C_RED
	ssb.set_corner_radius_all(3)
	seal.add_theme_stylebox_override("normal", ssb)
	seal.size = Vector2(fs * 1.9, fs * 1.9)
	seal.position = Vector2(col_w - fs * 3.6, _plaque_height() * 1.15 / 2.0 - fs * 0.95)
	seal.rotation = 0.08
	plate.add_child(seal)
	main_view.add_child(plate)

	var cats := [["sohbet", "Sohbet"], ["karakter", "Karakter"], ["yapay_zeka", "Yapay Zeka"], ["davranis", "Davranış"], ["hakkinda", "Hakkında"]]
	for c in cats:
		var b := _plaque_button(c[1], CAT_PLAQUE[c[0]], _plaque_height())
		b.pressed.connect(_open_category.bind(c[0]))
		cat_buttons[c[0]] = b
		main_view.add_child(b)

	# Karakterler: sadece kartlar kadar yer kaplar (alti bos kalmasin)
	var skins_box := PanelContainer.new()
	skins_box.add_theme_stylebox_override("panel", _box(Color(C_CREAM, 0.96), 3, C_GOLD, 2, 0))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", int(fs * 0.4))
	sv.add_child(_label("Karakterler", 0.95, C_TEXT, false, 800))
	sv.add_child(_divider_line())
	skin_grid = GridContainer.new()
	skin_grid.columns = 4
	skin_grid.add_theme_constant_override("h_separation", int(fs * 0.4))
	skin_grid.add_theme_constant_override("v_separation", int(fs * 0.4))
	sv.add_child(skin_grid)
	skin_cell = (size_px.x - fs * 3.2) / 4.0
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
	main_view.add_child(skins_box)
	_mark_selected_card()

	main_view.add_child(_footer(false))

	detail_view = _build_detail(size_px)
	detail_view.visible = false
	col.add_child(detail_view)
	return col


func _footer(with_back: bool) -> HBoxContainer:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(fs * 0.5))
	if with_back:
		var back := _game_button("Geri", C_BROWN, 2.3)
		back.pressed.connect(_back_to_main)
		foot.add_child(back)
	var save := _game_button("Kaydet", C_GREEN, 2.3)
	save.pressed.connect(_on_save)
	foot.add_child(save)
	if not with_back:
		var close := _game_button("Kapat", C_BROWN, 2.3)
		close.pressed.connect(func(): close_requested.emit())
		foot.add_child(close)
	return foot


func _build_detail(size_px: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size = size_px
	v.add_theme_constant_override("separation", int(fs * 0.55))
	detail_head_holder = Control.new()
	detail_head_holder.custom_minimum_size.y = _plaque_height()
	v.add_child(detail_head_holder)
	var box := PanelContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var outer := _box(Color(C_CREAM, 0.97), 3, C_GOLD, 2, 0)
	outer.content_margin_left = 4
	outer.content_margin_right = 4
	outer.content_margin_top = 4
	outer.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", outer)
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), 2, C_CREAM_3, 1, 0))
	box.add_child(inner)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	detail_scroll = scroll
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	pages["sohbet"] = _page_chat()
	pages["karakter"] = _page_character()
	pages["yapay_zeka"] = _page_ai()
	pages["davranis"] = _page_behaviour()
	pages["hakkinda"] = _page_about()
	for pg in pages.values():
		pg.visible = false
		holder.add_child(pg)
	v.add_child(box)
	v.add_child(_footer(true))
	return v


func _open_category(id: String) -> void:
	if current_cat != "":
		return
	current_cat = id
	if id == "sohbet":
		_fill_chat()
	var src: Button = cat_buttons[id]
	for k in pages:
		pages[k].visible = k == id
	# Baslik: tiklanan kategorinin plakasi
	for c in detail_head_holder.get_children():
		c.queue_free()
	detail_head = _plaque_button(src.text, CAT_PLAQUE[id], _plaque_height())
	detail_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_head.add_theme_color_override("font_color", C_RED)
	detail_head.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_head_holder.add_child(detail_head)

	# Basilan dugmenin bir kopyasi yerinden en uste kayar, sonra kategori
	# gorunumu acilir
	var ghost := _plaque_button(src.text, CAT_PLAQUE[id], _plaque_height())
	ghost.add_theme_color_override("font_color", C_RED)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = src.size
	ghost.position = src.global_position - column.global_position
	column.add_child(ghost)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(main_view, "modulate:a", 0.0, 0.2)
	tw.tween_property(ghost, "position:y", 0.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func():
		main_view.visible = false
		detail_view.visible = true
		detail_view.modulate.a = 0.0
		ghost.queue_free())
	tw.chain().tween_property(detail_view, "modulate:a", 1.0, 0.2)


func _back_to_main() -> void:
	if current_cat == "":
		return
	current_cat = ""
	var tw := create_tween()
	tw.tween_property(detail_view, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		detail_view.visible = false
		main_view.visible = true
		main_view.modulate.a = 0.0)
	tw.tween_property(main_view, "modulate:a", 1.0, 0.2)


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
	# Kevin'in penceresi Hyprland'de igneli ve "hep ustte": dosya penceresi
	# arkasinda kaliyordu. Dosya penceresi acikken asagi alinir.
	_window_lowered(true)
	DisplayServer.file_dialog_show("Skin seç", OS.get_environment("HOME"), "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png ; Minecraft skin"]),
		func(ok: bool, paths: PackedStringArray, _f: int):
			_window_lowered(false)
			if not ok or paths.is_empty():
				return
			var target := Settings.import_skin(paths[0])
			if not skin_cards.has(target):
				_add_skin_card(target)
			body_cfg.skin = target
			_mark_selected_card()
			skin_chosen.emit(target))


func _window_lowered(lowered: bool) -> void:
	get_window().always_on_top = not lowered
	if OS.get_environment("HYPRLAND_INSTANCE_SIGNATURE") == "":
		return
	var pid := "pid:%d" % OS.get_process_id()
	var out := []
	OS.execute("hyprctl", ["clients", "-j"], out)
	var pinned := false
	var data = JSON.parse_string(out[0] if not out.is_empty() else "[]")
	if data is Array:
		for c in data:
			if int(c.get("pid", 0)) == OS.get_process_id():
				pinned = c.get("pinned", false)
	# "pin" komutu ac/kapa yapiyor: sadece gerekiyorsa cagir
	if pinned == lowered:
		OS.execute("hyprctl", ["dispatch", "pin", pid])
	OS.execute("hyprctl", ["dispatch", "alterzorder", ("bottom," if lowered else "top,") + pid])


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.65))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


var chat_list: VBoxContainer
var chat_scroll: ScrollContainer


func _page_chat() -> VBoxContainer:
	var v := _page()
	chat_list = VBoxContainer.new()
	chat_list.add_theme_constant_override("separation", int(fs * 0.45))
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(chat_list)
	return v


## Gecmisi her acilista yeniden oku (beyin bu arada yeni mesaj yazmis olabilir)
func _fill_chat() -> void:
	for c in chat_list.get_children():
		c.queue_free()
	var items := Settings.load_history()
	if items.is_empty():
		chat_list.add_child(_label("Henüz konuşma yok. \"Kevin\" diye seslen ya da Kevin'e orta tıkla.", 0.85, C_MUTED, true))
		return
	for m in items:
		var mine: bool = m.get("role", "") == "user"
		var bubble := PanelContainer.new()
		bubble.add_theme_stylebox_override("panel", _box(Color("fffaf0") if mine else C_CREAM_2, 10, C_INK, 2, 2))
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 0)
		bv.add_child(_label("Sen" if mine else "Kevin", 0.72, C_CARAMEL.darkened(0.25) if not mine else C_MUTED, false, 800))
		bv.add_child(_label(str(m.get("content", "")), 0.88, C_TEXT, true))
		bubble.add_child(bv)
		chat_list.add_child(bubble)
	# En yeni mesaj gorunsun
	await get_tree().process_frame
	await get_tree().process_frame
	if detail_scroll:
		detail_scroll.scroll_vertical = int(detail_scroll.get_v_scroll_bar().max_value)


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
	var replay := _game_button("Açılış ekranını oynat", C_CARAMEL, 2.0)
	replay.pressed.connect(func(): action.emit("splash"))
	v.add_child(replay)
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
	if pages.has(id) and current_cat == "":
		_open_category(id)


# =====================================================================
# Sol yuvarlak dugmeler: daire + cizilmis ikon + altina tasan etiket
# =====================================================================

class RoundIcon:
	extends Control
	var kind := ""
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.22
		var ink := Color("c4161c")
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
	var size_px := fs * 2.9
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px + fs * 1.3)
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.size = Vector2(size_px, size_px)
	var r := int(size_px / 2)
	for spec in [["normal", C_CREAM, C_GOLD], ["hover", Color("fffaf0"), C_RED], ["pressed", C_CREAM_2, C_RED], ["hover_pressed", C_CREAM_2, C_RED]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = spec[1]
		sb.border_color = spec[2]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(r)
		b.add_theme_stylebox_override(spec[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	holder.add_child(b)
	var ic := RoundIcon.new()
	ic.kind = icon
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size = Vector2(size_px, size_px)
	holder.add_child(ic)
	# Etiket: masaustu ustunde okunsun diye kucuk krem serit uzerinde
	var l := _label(text, 0.72, C_INK, false, 700)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(C_CREAM, 0.95)
	lsb.border_color = C_CREAM_3
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(2)
	l.add_theme_stylebox_override("normal", lsb)
	l.size = Vector2(size_px + fs, fs * 1.2)
	l.position = Vector2(-fs * 0.5, size_px + fs * 0.1)
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
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	return tw
