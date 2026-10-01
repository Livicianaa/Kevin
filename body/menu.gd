extends Control
## Kevin'in menusu (karaktere sag tik). Gorunum livi'nin verdigi oyun karakter
## ekrani referansina gore: kalin koyu kenarli, alttan golgeli dugmeler, yazi
## dis cizgisi, egik rozet, birlesik sekmeler, ikonlu yuvarlak sol dugmeler,
## cerceveli skin kartlari, testere disli alt serit.
## Karakter 3B sahnede (main ciziyor), bu dugum sadece arayuz.

signal close_requested
signal saved(needs_reload: bool)
signal skin_chosen(path: String)
signal action(name: String)

const Settings := preload("res://settings.gd")

const C_INK := Color("15112b")
const C_PANEL := Color("2a2354")
const C_PANEL_DARK := Color("1b1638")
const C_LINE := Color("3d3474")
const C_TEXT := Color("ffffff")
const C_MUTED := Color("b8b0e0")
const C_PURPLE := Color("8a5cf6")
const C_BLUE := Color("2f86e8")
const C_GREEN := Color("7ad83b")
const C_CYAN := Color("6fe3ff")

var body_cfg := {}
var brain_cfg := {}
var fs := 20

var right_panel: Control
var left_bar: Control
var bottom_strip: Control
var tab_buttons := {}
var tab_pages := {}
var cards := {}
var card_marks := {}

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
var skin_name: Label
var auto_rotate_btn: Button

var original_body := {}


func build(view: Vector2) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fs = int(clampf(view.y / 44.0, 14.0, 24.0))
	theme = _make_theme()

	body_cfg = Settings.load_body()
	original_body = body_cfg.duplicate()
	brain_cfg = Settings.load_brain()

	var pad := view.y * 0.035
	var strip_h := view.y * 0.22
	var panel_w := clampf(view.x * 0.4, 380.0, 560.0)

	right_panel = _build_right_panel(Vector2(panel_w, view.y - strip_h - pad * 2))
	right_panel.position = Vector2(view.x - panel_w - pad, pad)
	add_child(right_panel)

	left_bar = _build_left_bar()
	left_bar.position = Vector2(pad, view.y * 0.16)
	add_child(left_bar)

	bottom_strip = _build_bottom_strip(Vector2(view.x, strip_h))
	bottom_strip.position = Vector2(0, view.y - strip_h)
	add_child(bottom_strip)

	_select_tab("karakter")
	_animate_in(view)


# =====================================================================
# Stil
# =====================================================================

func _font(weight := 800) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Segoe UI", "Arial"])
	f.font_weight = weight
	return f


## Referanstaki gibi: koyu kalin kenar + alttan "dudak" (golge kaymasi)
func _box(bg: Color, radius := 12, border := C_INK, bw := 3, lip := 0, lip_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = fs * 0.7
	sb.content_margin_right = fs * 0.7
	sb.content_margin_top = fs * 0.4
	sb.content_margin_bottom = fs * 0.4
	if lip > 0:
		sb.shadow_color = lip_color if lip_color.a > 0.0 else bg.darkened(0.45)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(0, lip)
	return sb


func _outlined(node: Control, size_mul := 1.0, weight := 800) -> void:
	node.add_theme_font_override("font", _font(weight))
	node.add_theme_font_size_override("font_size", int(fs * size_mul))
	node.add_theme_constant_override("outline_size", maxi(3, int(fs * 0.28)))
	node.add_theme_color_override("font_outline_color", C_INK)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(560)
	t.default_font_size = fs
	t.set_color("font_color", "Label", C_TEXT)
	for cls in ["Button", "OptionButton"]:
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, C_TEXT)
		t.set_color("font_pressed_color", cls, C_TEXT)
		t.set_color("font_focus_color", cls, C_TEXT)
		t.set_stylebox("normal", cls, _box(C_PANEL_DARK, 10, C_INK, 3, 4))
		t.set_stylebox("hover", cls, _box(C_PANEL_DARK.lightened(0.12), 10, C_INK, 3, 4))
		t.set_stylebox("pressed", cls, _box(C_BLUE, 10, C_INK, 3, 4))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_color("font_hover_color", "CheckButton", C_TEXT)
	t.set_color("font_pressed_color", "CheckButton", C_TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", _box(C_PANEL_DARK, 10, C_INK, 3, 4))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, _box(C_INK, 8, C_LINE, 2))
		t.set_stylebox("focus", cls, _box(C_INK, 8, C_BLUE, 2))
		t.set_color("font_color", cls, C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_MUTED.darkened(0.25))
	t.set_stylebox("slider", "HSlider", _box(C_INK, 8, C_LINE, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(C_PURPLE, 8, C_INK, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(C_PURPLE.lightened(0.15), 8, C_INK, 2))
	t.set_stylebox("panel", "PopupMenu", _box(C_PANEL_DARK, 8, C_INK, 3))
	return t


func _label(text: String, size_mul := 1.0, color := C_TEXT, wrap := false, weight := 560) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(fs * size_mul))
	l.add_theme_color_override("font_color", color)
	if weight != 560:
		l.add_theme_font_override("font", _font(weight))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = fs * 8
	return l


func _title(text: String, size_mul := 1.0) -> Label:
	var l := Label.new()
	l.text = text
	_outlined(l, size_mul)
	return l


## Referanstaki istatistik satiri: baslik, altinda kontrol, ince ayrac
func _row(title: String, control: Control, hint := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.35))
	v.add_child(_title(title, 0.95))
	v.add_child(control)
	if hint != "":
		v.add_child(_label(hint, 0.72, C_MUTED, true))
	var sep := ColorRect.new()
	sep.color = C_LINE
	sep.custom_minimum_size.y = 2
	v.add_child(sep)
	return v


## Birlesik sekme/secim dugmeleri (referanstaki mavi-koyu ikili)
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
		b.custom_minimum_size.y = fs * 2.0
		_outlined(b, 0.9)
		var first := i == 0
		var last := i == labels.size() - 1
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var on: bool = st.contains("pressed")
			var sb := _box(C_BLUE if on else C_PANEL_DARK.lightened(0.06 if st == "hover" else 0.0), 0, C_INK, 3)
			sb.corner_radius_top_left = 12 if first else 0
			sb.corner_radius_bottom_left = 12 if first else 0
			sb.corner_radius_top_right = 12 if last else 0
			sb.corner_radius_bottom_right = 12 if last else 0
			if not first:
				sb.border_width_left = 0
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", C_MUTED)
		b.add_theme_color_override("font_pressed_color", C_TEXT)
		b.add_theme_color_override("font_hover_pressed_color", C_TEXT)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
	s.custom_minimum_size.y = fs * 1.4
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = fs * 2.8
	_outlined(b, 1.3, 900)
	b.add_theme_stylebox_override("normal", _box(color, 16, C_INK, 4, 7, color.darkened(0.5)))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.12), 16, C_INK, 4, 7, color.darkened(0.5)))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), 16, C_INK, 4, 2, color.darkened(0.5)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


# =====================================================================
# Sag panel
# =====================================================================

func _build_right_panel(size_px: Vector2) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = size_px
	v.size = size_px
	v.add_theme_constant_override("separation", int(fs * 0.5))

	# Ust satir: egik rozet + kucuk yazi (referanstaki "SR  ...")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(fs * 0.6))
	var badge := PanelContainer.new()
	var bsb := _box(C_PURPLE, 6, C_INK, 3)
	bsb.skew = Vector2(0.25, 0)
	bsb.content_margin_left = fs * 0.9
	bsb.content_margin_right = fs * 0.9
	badge.add_theme_stylebox_override("panel", bsb)
	badge.add_child(_title("AI", 1.0))
	top.add_child(badge)
	top.add_child(_title("Masaüstü arkadaşı", 0.95))
	v.add_child(top)

	# Isim plakasi
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _box(C_PANEL_DARK, 12, C_INK, 3))
	var name_l := _title(str(brain_cfg.get("name", "Kevin")), 1.7)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(name_l)
	v.add_child(plate)

	# Durum cipleri: saglayici (mor) + model (kahverengi hap)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", int(fs * 0.4))
	var prov: String = str(brain_cfg.get("provider", ""))
	var c1 := PanelContainer.new()
	c1.add_theme_stylebox_override("panel", _box(C_PURPLE, 20, C_INK, 3))
	c1.add_child(_title(Settings.PROVIDERS.get(prov, {}).get("label", "Beyin yok"), 0.75))
	chips.add_child(c1)
	var c2 := PanelContainer.new()
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c2.add_theme_stylebox_override("panel", _box(Color("6b4a35"), 20, C_INK, 3))
	var model_l := _title(str(brain_cfg.get("model", "varsayılan model")), 0.75)
	model_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	model_l.clip_text = true
	c2.add_child(model_l)
	chips.add_child(c2)
	v.add_child(chips)

	# Icerik kutusu: birlesik sekmeler + sayfa
	var box := PanelContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", _box(C_PANEL, 14, C_INK, 3))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(fs * 0.6))
	box.add_child(inner)
	var ids := ["karakter", "yapay_zeka", "davranis", "hakkinda"]
	var tabs := _segment(["Karakter", "Yapay Zeka", "Davranış", "Hakkında"], 0,
		func(i): _select_tab(ids[i]))
	for i in ids.size():
		tab_buttons[ids[i]] = tabs[i]
	inner.add_child(_segment_box(tabs))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	tab_pages["karakter"] = _page_character()
	tab_pages["yapay_zeka"] = _page_ai()
	tab_pages["davranis"] = _page_behaviour()
	tab_pages["hakkinda"] = _page_about()
	for p in tab_pages.values():
		pages.add_child(p)
	v.add_child(box)

	# Alt dugmeler (referanstaki yesil / mavi)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(fs * 0.6))
	var save := _big_button("Kaydet", C_GREEN)
	save.pressed.connect(_on_save)
	foot.add_child(save)
	var close := _big_button("Kapat", C_BLUE)
	close.pressed.connect(func(): close_requested.emit())
	foot.add_child(close)
	v.add_child(foot)
	return v


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.7))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


func _page_character() -> VBoxContainer:
	var v := _page()
	var skin_box := HBoxContainer.new()
	skin_name = _label(str(body_cfg.skin).get_file(), 0.95)
	skin_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_box.add_child(skin_name)
	var pick := Button.new()
	pick.text = "Dosyadan seç"
	_outlined(pick, 0.8)
	pick.pressed.connect(_pick_skin_file)
	skin_box.add_child(pick)
	v.add_child(_row("Skin", skin_box, "Alttaki kartlardan da seçebilirsin (64x64 Minecraft skin)."))

	slim_btns = _segment(["Klasik (4 px)", "İnce (3 px)"], 1 if body_cfg.slim else 0,
		func(i): body_cfg.slim = i == 1)
	v.add_child(_row("Kol modeli", _segment_box(slim_btns)))

	var scale_box := HBoxContainer.new()
	scale_slider = _slider(0.6, 2.0, 0.05, float(body_cfg.scale))
	scale_label = _title("", 0.9)
	scale_label.custom_minimum_size.x = fs * 3.6
	scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_slider.value_changed.connect(func(val):
		body_cfg.scale = val
		scale_label.text = "%%%d" % roundi(val * 100))
	scale_label.text = "%%%d" % roundi(float(body_cfg.scale) * 100)
	scale_box.add_child(scale_slider)
	scale_box.add_child(scale_label)
	v.add_child(_row("Boyut", scale_box, "Kol modeli ve boyut Kaydet'e basınca uygulanır."))
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
	session_label = _title("%d sn" % int(sess_s), 0.9)
	session_label.custom_minimum_size.x = fs * 3.6
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

	v.add_child(_label("Not: beyin (ses, sohbet, araçlar) henüz bu gövdeye bağlı değil; ayarlar kaydediliyor, bağlantı sıradaki adım.", 0.72, C_MUTED, true))
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
	v.add_child(_label("Masaüstünde yaşayan, konuşan ve bilgisayarını kullanabilen yapay zeka arkadaşı.", 0.9, C_TEXT, true))
	v.add_child(_title("Created by Liviciana", 0.95))
	v.add_child(_label("Animasyonlar: Fresh Animations (kullanıcının paketi), Emotecraft emote'ları (CC0), Quaternius Universal Animation Library 2 (CC0).", 0.78, C_MUTED, true))
	v.add_child(_label("Menü: karaktere sağ tık. Karakteri sürükle: döndür. Esc: kapat.", 0.78, C_MUTED, true))
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


func _select_tab(id: String) -> void:
	for k in tab_pages:
		tab_pages[k].visible = k == id
	if tab_buttons.has(id):
		tab_buttons[id].button_pressed = true


# =====================================================================
# Sol yuvarlak dugmeler: daire + cizilmis ikon + altina tasan etiket
# =====================================================================

class RoundIcon:
	extends Control
	var kind := ""
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.22
		var ink := Color("15112b")
		var white := Color.WHITE
		match kind:
			"rotate":
				draw_arc(c, r, 0.4, TAU - 0.6, 24, ink, r * 0.55)
				draw_arc(c, r, 0.4, TAU - 0.6, 24, white, r * 0.3)
				var tip := c + Vector2(cos(-0.6), sin(-0.6)) * r
				var head := PackedVector2Array([tip + Vector2(-r * 0.45, -r * 0.35), tip + Vector2(r * 0.45, -r * 0.1), tip + Vector2(-r * 0.05, r * 0.45)])
				draw_colored_polygon(head, white)
				var outline := head.duplicate()
				outline.append(head[0])
				draw_polyline(outline, ink, 2.0)
			"emote":
				var pts := PackedVector2Array()
				for i in 10:
					var a := -PI / 2 + i * TAU / 10.0
					var rr := r * (1.2 if i % 2 == 0 else 0.5)
					pts.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, white)
				var outline := pts.duplicate()
				outline.append(pts[0])
				draw_polyline(outline, ink, 3.0)
			"reset":
				draw_circle(c, r * 1.05, ink)
				draw_circle(c, r * 0.8, white)
				draw_line(c, c + Vector2(0, -r * 0.6), ink, 3.0)
				draw_line(c, c + Vector2(r * 0.45, 0), ink, 3.0)


func _round_button(text: String, icon: String) -> Control:
	var size_px := fs * 3.8
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size_px, size_px + fs * 0.6)
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.size = Vector2(size_px, size_px)
	var r := int(size_px / 2)
	b.add_theme_stylebox_override("normal", _box(C_PANEL_DARK, r, C_INK, 4, 5, Color("0c0920")))
	b.add_theme_stylebox_override("hover", _box(C_PANEL_DARK.lightened(0.15), r, C_INK, 4, 5, Color("0c0920")))
	b.add_theme_stylebox_override("pressed", _box(C_PURPLE, r, C_INK, 4, 2, Color("0c0920")))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	holder.add_child(b)
	var ic := RoundIcon.new()
	ic.kind = icon
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size = Vector2(size_px, size_px * 0.8)
	holder.add_child(ic)
	var l := _title(text, 0.8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(size_px, fs * 1.4)
	l.position = Vector2(0, size_px - fs * 0.9)
	holder.add_child(l)
	holder.set_meta("button", b)
	return holder


func _build_left_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.9))
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
# Alt serit: testere disli koyu bant + cerceveli skin kartlari
# =====================================================================

class StripBg:
	extends Control
	func _draw() -> void:
		var tooth := 18.0
		draw_rect(Rect2(Vector2.ZERO, size), Color("1b1638f2"))
		draw_line(Vector2(0, 1), Vector2(size.x, 1), Color("15112b"), 4.0)
		draw_line(Vector2(0, 5), Vector2(size.x, 5), Color("3d3474"), 2.0)
		var pts := PackedVector2Array([Vector2(0, size.y)])
		var x := 0.0
		while x <= size.x + tooth:
			pts.append(Vector2(x, size.y - tooth * 0.55))
			pts.append(Vector2(x + tooth / 2.0, size.y))
			x += tooth
		pts.append(Vector2(size.x, size.y))
		draw_colored_polygon(pts, Color("15112b"))


func _build_bottom_strip(size_px: Vector2) -> Control:
	var bg := StripBg.new()
	bg.custom_minimum_size = size_px
	bg.size = size_px
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(fs, fs * 0.8)
	scroll.size = Vector2(size_px.x - fs * 2, size_px.y - fs * 1.6)
	bg.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(fs * 0.9))
	scroll.add_child(row)
	var card_h := scroll.size.y - fs * 0.4
	for path in Settings.list_skins():
		row.add_child(_skin_card(path, card_h))
	var add := Button.new()
	add.text = "+ Skin ekle"
	_outlined(add, 0.85)
	add.custom_minimum_size = Vector2(card_h * 0.72, card_h * 0.72)
	add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add.add_theme_stylebox_override("normal", _box(C_PANEL, 12, C_INK, 3, 5))
	add.add_theme_stylebox_override("hover", _box(C_PANEL.lightened(0.1), 12, C_INK, 3, 5))
	add.pressed.connect(_pick_skin_file)
	row.add_child(add)
	_mark_selected_card()
	return bg


func _skin_card(path: String, card_h: float) -> Control:
	var w := card_h * 0.72
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.25))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(w, card_h * 0.72)
	btn.tooltip_text = path.get_file()
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
		tr.position = Vector2(w * 0.2, card_h * 0.08)
		tr.size = Vector2(w * 0.6, w * 0.6)
		btn.add_child(tr)
	var name := _title(path.get_file().get_basename(), 0.72)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.position = Vector2(0, card_h * 0.72 - fs * 1.5)
	name.size = Vector2(w, fs * 1.3)
	btn.add_child(name)
	btn.pressed.connect(func():
		body_cfg.skin = path
		skin_name.text = path.get_file()
		_mark_selected_card()
		skin_chosen.emit(path))
	v.add_child(btn)
	var mark := Button.new()
	mark.text = "Seçili"
	mark.disabled = true
	_outlined(mark, 0.72)
	mark.custom_minimum_size = Vector2(w, fs * 1.5)
	mark.add_theme_stylebox_override("disabled", _box(C_GREEN, 8, C_INK, 3, 3, C_GREEN.darkened(0.5)))
	mark.add_theme_color_override("font_disabled_color", C_TEXT)
	v.add_child(mark)
	cards[path] = btn
	card_marks[path] = mark
	return v


func _mark_selected_card() -> void:
	for p in cards:
		var sel: bool = p == str(body_cfg.skin)
		var frame := C_PURPLE if not sel else C_CYAN
		var sb := _box(C_PANEL_DARK, 12, frame, 4, 5, C_INK)
		if sel:
			sb.shadow_color = Color(C_CYAN, 0.55)
			sb.shadow_size = 8
			sb.shadow_offset = Vector2.ZERO
		for st in ["normal", "hover", "pressed"]:
			cards[p].add_theme_stylebox_override(st, sb)
		card_marks[p].modulate.a = 1.0 if sel else 0.0


func _pick_skin_file() -> void:
	DisplayServer.file_dialog_show("Skin seç", OS.get_environment("HOME"), "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png ; Minecraft skin"]),
		func(ok: bool, paths: PackedStringArray, _f: int):
			if not ok or paths.is_empty():
				return
			var target := Settings.import_skin(paths[0])
			body_cfg.skin = target
			skin_name.text = target.get_file()
			skin_chosen.emit(target))


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
# Giris / cikis: ustten ve yanlardan
# =====================================================================

func _animate_in(view: Vector2) -> void:
	var items := [
		[right_panel, Vector2(view.x * 0.5, 0), 0.12],
		[left_bar, Vector2(-view.x * 0.25, 0), 0.2],
		[bottom_strip, Vector2(0, view.y * 0.3), 0.05],
	]
	for it in items:
		var node: Control = it[0]
		var final := node.position
		node.position = final + it[1]
		node.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position", final, 0.55).set_delay(it[2]).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "modulate:a", 1.0, 0.3).set_delay(it[2])


func animate_out(view: Vector2) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(right_panel, "position:x", right_panel.position.x + view.x * 0.5, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(left_bar, "position:x", -view.x * 0.25, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(bottom_strip, "position:y", bottom_strip.position.y + view.y * 0.3, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	return tw
