extends Control
## Kevin'in menusu (karaktere sag tik). Solda karakter (3B sahnede, main
## ciziyor), sagda sekmeli ayar paneli, altta skin kartlari, solda yuvarlak
## islem dugmeleri. Parcalar ustten ve yanlardan kayarak geliyor.

signal close_requested
signal saved(needs_reload: bool)
signal skin_chosen(path: String)
signal action(name: String)

const Settings := preload("res://settings.gd")

const C_PANEL := Color("211a42ee")
const C_PANEL_2 := Color("2b2356")
const C_BORDER := Color("5a4bb3")
const C_TEXT := Color("f1edff")
const C_MUTED := Color("a99fd6")
const C_ACCENT := Color("8b6cff")
const C_BLUE := Color("3d8bff")
const C_GREEN := Color("62d148")

var body_cfg := {}
var brain_cfg := {}
var fs := 20

var right_panel: Control
var left_bar: Control
var bottom_strip: Control
var tab_buttons := {}
var tab_pages := {}
var cards := {}

# Alanlar
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


func build(screen_size: Vector2) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fs = int(clampf(screen_size.y / 52.0, 14.0, 26.0))
	theme = _make_theme()

	body_cfg = Settings.load_body()
	original_body = body_cfg.duplicate()
	brain_cfg = Settings.load_brain()

	var w := screen_size.x
	var h := screen_size.y
	var strip_h := h * 0.2
	var panel_w := clampf(w * 0.34, 420.0, 620.0)

	right_panel = _build_right_panel(Vector2(panel_w, h - strip_h - h * 0.08))
	right_panel.position = Vector2(w - panel_w - w * 0.03, h * 0.04)
	add_child(right_panel)

	left_bar = _build_left_bar()
	left_bar.position = Vector2(w * 0.03, h * 0.28)
	add_child(left_bar)

	bottom_strip = _build_bottom_strip(Vector2(w, strip_h))
	bottom_strip.position = Vector2(0, h - strip_h)
	add_child(bottom_strip)

	_select_tab("karakter")
	_animate_in(screen_size)


# =====================================================================
# Tema
# =====================================================================

func _font(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Inter", "Noto Sans", "Cantarell", "DejaVu Sans", "Segoe UI", "Arial"])
	f.font_weight = 750 if bold else 450
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


func _box(bg: Color, border := Color.TRANSPARENT, radius := 12, bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = fs * 0.6
	sb.content_margin_right = fs * 0.6
	sb.content_margin_top = fs * 0.35
	sb.content_margin_bottom = fs * 0.35
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(false)
	t.default_font_size = fs
	t.set_color("font_color", "Label", C_TEXT)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_stylebox("normal", cls, _box(C_PANEL_2, C_BORDER, 10, 2))
		t.set_stylebox("hover", cls, _box(C_PANEL_2.lightened(0.12), C_ACCENT, 10, 2))
		t.set_stylebox("pressed", cls, _box(C_ACCENT.darkened(0.25), C_ACCENT, 10, 2))
		t.set_stylebox("focus", cls, _box(Color.TRANSPARENT, C_ACCENT, 10, 2))
	# Onay kutusu: secili olmasi anahtardan belli, zemin degismesin
	for st in ["pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", _box(C_PANEL_2, C_ACCENT, 10, 2))
	t.set_stylebox("normal", "LineEdit", _box(Color("16112e"), C_BORDER, 8, 2))
	t.set_stylebox("focus", "LineEdit", _box(Color("16112e"), C_BLUE, 8, 2))
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_MUTED.darkened(0.2))
	t.set_stylebox("normal", "TextEdit", _box(Color("16112e"), C_BORDER, 8, 2))
	t.set_stylebox("focus", "TextEdit", _box(Color("16112e"), C_BLUE, 8, 2))
	t.set_color("font_color", "TextEdit", C_TEXT)
	t.set_stylebox("slider", "HSlider", _box(Color("16112e"), Color.TRANSPARENT, 6))
	t.set_stylebox("grabber_area", "HSlider", _box(C_ACCENT, Color.TRANSPARENT, 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(C_ACCENT.lightened(0.2), Color.TRANSPARENT, 6))
	t.set_stylebox("panel", "PopupMenu", _box(C_PANEL_2, C_BORDER, 8, 2))
	return t


## wrap: uzun aciklamalar icin. Dar kutuda (baslik gibi) kaydirma her harfi
## ayri satira kiriyordu.
func _label(text: String, size_mul := 1.0, bold := false, color := C_TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(fs * size_mul))
	if bold:
		l.add_theme_font_override("font", _font(true))
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = fs * 8
	return l


func _row(title: String, control: Control, hint := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.3))
	v.add_child(_label(title, 0.9, true, C_MUTED))
	v.add_child(control)
	if hint != "":
		v.add_child(_label(hint, 0.75, false, C_MUTED.darkened(0.15), true))
	return v


func _toggle_group(labels: Array, selected: int, on_pick: Callable) -> Array:
	var group := ButtonGroup.new()
	var out := []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", _box(C_BLUE, C_BLUE.lightened(0.2), 10, 2))
		b.pressed.connect(on_pick.bind(i))
		out.append(b)
	return out


func _slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size.y = fs * 1.4
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# =====================================================================
# Sag panel
# =====================================================================

func _build_right_panel(size_px: Vector2) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size_px
	panel.size = size_px
	panel.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 18, 2))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.6))
	panel.add_child(v)

	# Baslik: rozet + isim + alt yazi
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(fs * 0.5))
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _box(C_ACCENT, C_ACCENT.lightened(0.3), 8, 2))
	badge.add_child(_label("AI", 0.95, true))
	head.add_child(badge)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(_label(str(brain_cfg.get("name", "Kevin")), 1.7, true))
	name_box.add_child(_label("Masaüstü arkadaşın", 0.8, false, C_MUTED))
	head.add_child(name_box)
	v.add_child(head)

	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", _box(Color("16112e"), C_BORDER, 10, 1))
	var prov: String = str(brain_cfg.get("provider", ""))
	var prov_label: String = Settings.PROVIDERS.get(prov, {}).get("label", "seçilmedi")
	status.add_child(_label("Beyin: %s  ·  model: %s" % [prov_label, str(brain_cfg.get("model", "varsayılan"))], 0.8, false, C_MUTED))
	v.add_child(status)

	# Sekmeler
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(fs * 0.3))
	var group := ButtonGroup.new()
	for id in ["karakter", "yapay_zeka", "davranis", "hakkinda"]:
		var b := Button.new()
		b.text = {"karakter": "Karakter", "yapay_zeka": "Yapay Zeka", "davranis": "Davranış", "hakkinda": "Hakkında"}[id]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", _box(C_BLUE, C_BLUE.lightened(0.25), 10, 2))
		b.add_theme_font_override("font", _font(true))
		b.pressed.connect(_select_tab.bind(id))
		tabs.add_child(b)
		tab_buttons[id] = b
	v.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	tab_pages["karakter"] = _page_character()
	tab_pages["yapay_zeka"] = _page_ai()
	tab_pages["davranis"] = _page_behaviour()
	tab_pages["hakkinda"] = _page_about()
	for p in tab_pages.values():
		pages.add_child(p)

	# Alt dugmeler (referanstaki yesil/mavi)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(fs * 0.5))
	var save := Button.new()
	save.text = "Kaydet"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.custom_minimum_size.y = fs * 2.6
	save.add_theme_font_override("font", _font(true))
	save.add_theme_font_size_override("font_size", int(fs * 1.2))
	save.add_theme_stylebox_override("normal", _box(C_GREEN, C_GREEN.lightened(0.3), 14, 3))
	save.add_theme_stylebox_override("hover", _box(C_GREEN.lightened(0.1), Color.WHITE, 14, 3))
	save.add_theme_stylebox_override("pressed", _box(C_GREEN.darkened(0.2), Color.WHITE, 14, 3))
	save.pressed.connect(_on_save)
	foot.add_child(save)
	var close := Button.new()
	close.text = "Kapat"
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size.y = fs * 2.6
	close.add_theme_font_override("font", _font(true))
	close.add_theme_font_size_override("font_size", int(fs * 1.2))
	close.add_theme_stylebox_override("normal", _box(C_BLUE, C_BLUE.lightened(0.3), 14, 3))
	close.add_theme_stylebox_override("hover", _box(C_BLUE.lightened(0.1), Color.WHITE, 14, 3))
	close.add_theme_stylebox_override("pressed", _box(C_BLUE.darkened(0.2), Color.WHITE, 14, 3))
	close.pressed.connect(func(): close_requested.emit())
	foot.add_child(close)
	v.add_child(foot)
	return panel


func _page(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.9))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_label(title, 1.05, true))
	return v


func _page_character() -> VBoxContainer:
	var v := _page("Görünüm")
	skin_name = _label(str(body_cfg.skin).get_file(), 0.95)
	var skin_box := HBoxContainer.new()
	skin_box.add_child(skin_name)
	skin_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pick := Button.new()
	pick.text = "Dosyadan seç"
	pick.pressed.connect(_pick_skin_file)
	skin_box.add_child(pick)
	v.add_child(_row("Skin", skin_box, "Aşağıdaki kartlardan da seçebilirsin. 64x64 Minecraft skin (png)."))

	var model_box := HBoxContainer.new()
	slim_btns = _toggle_group(["Klasik (4 px kol)", "İnce (3 px kol)"], 1 if body_cfg.slim else 0,
		func(i): body_cfg.slim = i == 1)
	for b in slim_btns:
		model_box.add_child(b)
	v.add_child(_row("Model", model_box))

	var scale_box := HBoxContainer.new()
	scale_slider = _slider(0.6, 2.0, 0.05, float(body_cfg.scale))
	scale_label = _label("", 0.95)
	scale_label.custom_minimum_size.x = fs * 3.5
	scale_slider.value_changed.connect(func(val):
		body_cfg.scale = val
		scale_label.text = "%%%d" % roundi(val * 100))
	scale_label.text = "%%%d" % roundi(float(body_cfg.scale) * 100)
	scale_box.add_child(scale_slider)
	scale_box.add_child(scale_label)
	v.add_child(_row("Boyut", scale_box, "Model ve boyut Kaydet'e basınca uygulanır."))
	return v


func _page_ai() -> VBoxContainer:
	var v := _page("Beyin")
	var local: bool = Settings.PROVIDERS.get(str(brain_cfg.get("provider", "groq")), {}).get("local", false)
	var mode_box := HBoxContainer.new()
	mode_btns = _toggle_group(["Bulut (API)", "Yerel (Ollama)"], 1 if local else 0, _on_mode)
	for b in mode_btns:
		mode_box.add_child(b)
	v.add_child(_row("Çalışma şekli", mode_box, "Bulut: hızlı, internet ve anahtar ister. Yerel: bilgisayarında çalışır, Ollama kurulu olmalı."))

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
	v.add_child(_row("Model", model_edit, "Boş bırakırsan sağlayıcının varsayılanı kullanılır."))

	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "Kayıtlı anahtar var (değiştirmek için yaz)" if str(brain_cfg.get("apiKey", "")) != "" else "API anahtarını yapıştır"
	key_row = _row("API anahtarı", key_edit, "Anahtar sadece bu bilgisayarda, ayar dosyasında durur.")
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
	session_label = _label("%d sn" % int(sess_s), 0.95)
	session_label.custom_minimum_size.x = fs * 3.5
	session_slider.value_changed.connect(func(val): session_label.text = "%d sn" % int(val))
	sess_box.add_child(session_slider)
	sess_box.add_child(session_label)
	v.add_child(_row("Sohbet süresi", sess_box, "Adını söyledikten sonra ne kadar süre seni dinlesin."))

	persona_edit = TextEdit.new()
	persona_edit.text = str(brain_cfg.get("persona", ""))
	persona_edit.placeholder_text = "Boş bırakırsan varsayılan kişilik (esprili, samimi, Türkçe)."
	persona_edit.custom_minimum_size.y = fs * 7
	persona_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_row("Kişilik", persona_edit))

	v.add_child(_label("Not: beyin (ses, sohbet, araçlar) henüz bu gövdeye bağlı değil; ayarlar kaydediliyor, bağlantı sıradaki adım.", 0.75, false, C_MUTED, true))
	_on_mode(1 if local else 0)
	return v


func _page_behaviour() -> VBoxContainer:
	var v := _page("Davranış")
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
	var v := _page("Kevin")
	v.add_child(_label("Masaüstünde yaşayan, konuşan ve bilgisayarını kullanabilen yapay zeka arkadaşı.", 0.9, false, C_TEXT, true))
	v.add_child(_label("Created by Liviciana", 0.9, true, C_ACCENT.lightened(0.3)))
	v.add_child(_label("Animasyonlar: Fresh Animations (kullanıcının paketi), Emotecraft emote'ları (CC0), Quaternius Universal Animation Library 2 (CC0).", 0.8, false, C_MUTED, true))
	v.add_child(_label("Menü: karaktere sağ tık. Sürükle: döndür. Esc: kapat.", 0.8, false, C_MUTED, true))
	return v


func _on_mode(i: int) -> void:
	var local := i == 1
	if provider_row:
		provider_row.visible = not local
	if key_row:
		key_row.visible = not local
	_update_model_placeholder()


func _update_model_placeholder() -> void:
	if not model_edit:
		return
	var id := _current_provider()
	model_edit.placeholder_text = Settings.PROVIDERS.get(id, {}).get("model", "")


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
# Sol dugmeler ve alt skin seridi
# =====================================================================

func _round_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(fs * 4.6, fs * 4.6)
	b.add_theme_font_size_override("font_size", int(fs * 0.8))
	b.add_theme_font_override("font", _font(true))
	var r := int(fs * 2.3)
	b.add_theme_stylebox_override("normal", _box(C_PANEL, C_BORDER, r, 3))
	b.add_theme_stylebox_override("hover", _box(C_PANEL_2, C_ACCENT, r, 3))
	b.add_theme_stylebox_override("pressed", _box(C_ACCENT.darkened(0.2), C_ACCENT, r, 3))
	return b


func _build_left_bar() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(fs * 0.8))
	auto_rotate_btn = _round_button("Döndür")
	auto_rotate_btn.toggle_mode = true
	auto_rotate_btn.toggled.connect(func(on): action.emit("auto_rotate_on" if on else "auto_rotate_off"))
	v.add_child(auto_rotate_btn)
	var em := _round_button("Emote")
	em.pressed.connect(func(): action.emit("emote"))
	v.add_child(em)
	var reset := _round_button("Sıfırla")
	reset.pressed.connect(func():
		auto_rotate_btn.button_pressed = false
		action.emit("reset"))
	v.add_child(reset)
	return v


func _build_bottom_strip(size_px: Vector2) -> Control:
	var bg := PanelContainer.new()
	bg.custom_minimum_size = size_px
	bg.size = size_px
	var sb := _box(Color("150f2cf2"), C_BORDER, 0, 0)
	sb.border_width_top = 3
	bg.add_theme_stylebox_override("panel", sb)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(fs * 0.9))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	var card_h := size_px.y * 0.78
	for path in Settings.list_skins():
		row.add_child(_skin_card(path, card_h))
	var add := Button.new()
	add.text = "+ Skin ekle"
	add.custom_minimum_size = Vector2(card_h * 0.8, card_h)
	add.pressed.connect(_pick_skin_file)
	row.add_child(add)
	_mark_selected_card()
	return bg


func _skin_card(path: String, card_h: float) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(card_h * 0.8, card_h)
	btn.tooltip_text = path.get_file()
	var tex := Settings.load_skin(path)
	var face := AtlasTexture.new()
	face.atlas = tex
	face.region = Rect2(8, 8, 8, 8)
	var hat := AtlasTexture.new()
	hat.atlas = tex
	hat.region = Rect2(40, 8, 8, 8)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(card_h * 0.5, card_h * 0.5)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in [face, hat]:
		var tr := TextureRect.new()
		tr.texture = t
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	v.add_child(holder)
	var name := _label(path.get_file().get_basename(), 0.75, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	btn.add_child(v)
	btn.pressed.connect(func():
		body_cfg.skin = path
		skin_name.text = path.get_file()
		_mark_selected_card()
		skin_chosen.emit(path))
	cards[path] = btn
	return btn


func _mark_selected_card() -> void:
	for p in cards:
		var sel: bool = p == str(body_cfg.skin)
		cards[p].add_theme_stylebox_override("normal", _box(C_PANEL_2 if not sel else C_BLUE.darkened(0.35), C_BLUE if sel else C_BORDER, 12, 3 if sel else 2))


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
# Giris / cikis animasyonu: ustten ve yanlardan
# =====================================================================

func _animate_in(screen_size: Vector2) -> void:
	var items := [
		[right_panel, Vector2(screen_size.x * 0.45, 0), 0.12],
		[left_bar, Vector2(-screen_size.x * 0.2, 0), 0.2],
		[bottom_strip, Vector2(0, screen_size.y * 0.3), 0.05],
	]
	for it in items:
		var node: Control = it[0]
		var final := node.position
		node.position = final + it[1]
		node.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position", final, 0.55).set_delay(it[2]).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "modulate:a", 1.0, 0.3).set_delay(it[2])


func animate_out(screen_size: Vector2) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(right_panel, "position:x", right_panel.position.x + screen_size.x * 0.45, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(left_bar, "position:x", -screen_size.x * 0.2, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(bottom_strip, "position:y", bottom_strip.position.y + screen_size.y * 0.3, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	return tw
