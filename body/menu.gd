extends Control
## Kevin'in menusu (karaktere sag tik). Sade Japon tarzi: krem kagit, murekkep
## siyahi yazi, tek vurgu rengi hanko kirmizisi. Solda Kevin (arkasinda
## Codemisk logosu), sagda numarali kategori listesi, altinda karakterler.
## Kategoriye basinca baslik yukari kayar, sutun o kategorinin ayarlarina doner.
## Olculer 880x900'luk taslaktan (~/Pictures/kevin-menu-taslak-sade-japon.png)
## u katsayisiyla olcekleniyor.

signal close_requested
signal saved(needs_reload: bool)
signal skin_chosen(path: String)
signal action(name: String)

const Settings := preload("res://settings.gd")
const I18n := preload("res://i18n.gd")
const SysProfile := preload("res://sysprofile.gd")

const C_PAPER := Color("f4eee2")
const C_CARD := Color("faf6ee")
const C_LINE := Color("d9cdb6")
const C_INK := Color("262019")
const C_MUTED := Color("8a7d6b")
const C_RED := Color("b8261f")
const C_CREAM := Color("f6eee0")

## Golge icin pencere kenarinda birakilan bosluk (px)
const EDGE := 12.0

var body_cfg := {}
var brain_cfg := {}
var lang := "tr"
var u := 1.0
var view := Vector2.ZERO

## main kamerayi bunlara gore ayarliyor: Kevin'in ortasi (x), ayak hizasi (y)
## ve boyu (px)
var stage_x := 0.0
var stage_feet_y := 0.0
var stage_h := 0.0

var column: Control
var main_view: VBoxContainer
var detail_view: VBoxContainer
var detail_num: Label
var detail_title: Label
var detail_scroll: ScrollContainer
var foot_link: LinkButton
var footer: HBoxContainer
var stage_links: HBoxContainer
var caption: Label
var cat_buttons := {}
var pages := {}
var current_cat := ""
var skin_grid: GridContainer
var skin_cards := {}

var slim_btns := []
var scale_slider: HSlider
var scale_label: Label
var mode_btns := []
var provider_opt: OptionButton
var provider_row: Control
## Model listesi menunun icinde, sabit yukseklikte kayan liste. (Acilir
## liste ayri bir pencere olarak ekranin altina acilip kesiliyordu.)
var model_list: ItemList
## Kapali halde secili modeli gosteren satir; tiklaninca liste acilir
var model_btn: Button
var model_status: Label
var models_http: HTTPRequest
var key_timer: Timer
var ollama_link: LinkButton
var media_btns: Array = []
const MEDIA_MODES := ["duck", "pause", "none"]
var volume_slider: HSlider
var live_typing_check: Button
var key_edit: LineEdit
var key_row: Control
var name_edit: LineEdit
var nick_edit: LineEdit
var hands_check: Button
var session_slider: HSlider
var session_label: Label
var persona_edit: TextEdit
var walk_slider: HSlider
var emote_slider: HSlider
var look_check: Button
var wallsit_check: Button
var fun_check: Button
var mood_check: Button
var dance_check: Button
var night_check: Button
var sleep_slider: HSlider
var walk_speed_slider: HSlider
var speech_slider: HSlider
var camera_check: Button
var camera_greet_check: Button
var lang_opt: OptionButton
var no_key_label: Label
var rotate_link: LinkButton

var original_body := {}

const CATS := ["sohbet", "karakter", "yapay_zeka", "davranis", "hakkinda"]


## Taslak olculeri: menu ve arka plan ayni yerlesimi kullaniyor
static func layout(size_px: Vector2) -> Dictionary:
	var k := clampf(size_px.y / 900.0, 0.75, 1.5)
	var col_w := clampf(size_px.x * 0.36, 280.0 * k, 340.0 * k)
	var col_x := size_px.x - EDGE - 40.0 * k - col_w
	var feet := size_px.y * 0.765
	var h := size_px.y * 0.5
	return {
		"u": k,
		"col": Rect2(col_x, EDGE + 52.0 * k, col_w, size_px.y - 2.0 * EDGE - 52.0 * k - 34.0 * k),
		"stage_x": (EDGE + col_x) / 2.0,
		"feet": feet,
		"kevin_h": h,
		"logo_c": Vector2((EDGE + col_x) / 2.0, feet - h * 0.56),
		"logo_r": size_px.y * 0.215,
		"edge": EDGE,
	}


func build(size_px: Vector2) -> void:
	view = size_px
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lay := layout(view)
	u = lay.u
	stage_x = lay.stage_x
	stage_feet_y = lay.feet
	stage_h = lay.kevin_h
	theme = _make_theme()

	body_cfg = Settings.load_body()
	original_body = body_cfg.duplicate()
	brain_cfg = Settings.load_brain()
	lang = I18n.code_of(brain_cfg)

	caption = _text(_tx("caption"), 12, C_MUTED, false, 500, 3.8)
	caption.position = Vector2(EDGE + 26 * u, EDGE + 18 * u)
	add_child(caption)

	var r: Rect2 = lay.col
	column = Control.new()
	column.position = r.position
	column.size = r.size
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	footer = _build_footer()
	column.add_child(footer)
	var foot_h := footer.get_combined_minimum_size().y
	footer.position = Vector2(0, r.size.y - foot_h)
	footer.size = Vector2(r.size.x, foot_h)
	main_view = _build_main(r.size.x)
	column.add_child(main_view)
	detail_view = _build_detail(Vector2(r.size.x, r.size.y - foot_h - 20 * u))
	detail_view.visible = false
	column.add_child(detail_view)

	stage_links = _build_stage_links()
	add_child(stage_links)
	var sw := stage_links.get_combined_minimum_size()
	stage_links.position = Vector2(stage_x - sw.x / 2.0, view.y - EDGE - 30 * u - sw.y)

	_animate_in()


# =====================================================================
# Arka plan: Kevin'in ARKASINDA (main bunu SubViewport ile 3B duzleme basiyor).
# Kagit panel + ince doku + Kevin'in arkasinda Codemisk logosu.
# =====================================================================

class Paper:
	extends Control
	var lay := {}
	var logo: Texture2D

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("f4eee2")
		sb.border_color = Color("d9cdb6")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.shadow_color = Color(0, 0, 0, 0.22)
		var e: float = lay.edge
		sb.shadow_size = int(e * 0.8)
		sb.shadow_offset = Vector2(0, 3)
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(Vector2.ONE * e, size - Vector2.ONE * e * 2.0))
		# Kevin'in arkasinda Codemisk logosu, murekkep renginde silik
		if logo:
			var h: float = lay.logo_r * 1.9
			var w := h * logo.get_width() / logo.get_height()
			var c: Vector2 = lay.logo_c
			draw_texture_rect(logo, Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h)), false, Color(0.149, 0.125, 0.098, 0.13))


const GRAIN_SHADER := """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 px = FRAGCOORD.xy;
	float g = hash(floor(px)) * 0.6 + hash(floor(px * 0.5) + 7.0) * 0.4;
	COLOR = vec4(0.45, 0.38, 0.28, g * 0.11);
}
"""


static func make_background(size_px: Vector2) -> Control:
	var root := Control.new()
	root.size = size_px
	var paper := Paper.new()
	paper.size = size_px
	paper.lay = layout(size_px)
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://ui/codemisk_logo.png"))
	if img:
		img.generate_mipmaps()
		paper.logo = ImageTexture.create_from_image(img)
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(paper)
	var grain := ColorRect.new()
	grain.position = Vector2.ONE * (EDGE + 6.0)
	grain.size = size_px - Vector2.ONE * (EDGE + 6.0) * 2.0
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = GRAIN_SHADER
	grain.material = mat
	root.add_child(grain)
	return root


# =====================================================================
# Stil
# =====================================================================

var _fonts := {}


func _font(serif: bool, weight := 400, spacing := 0.0) -> Font:
	var key := "%s/%d/%d" % [serif, weight, roundi(spacing)]
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Noto Serif", "DejaVu Serif", "Liberation Serif"] if serif else ["Noto Sans", "DejaVu Sans", "Liberation Sans"])
	f.font_weight = weight
	var out: Font = f
	if roundi(spacing) != 0:
		var v := FontVariation.new()
		v.base_font = f
		v.spacing_glyph = roundi(spacing)
		out = v
	_fonts[key] = out
	return out


func _tx(key: String) -> String:
	return I18n.get_text(key, lang)


func px(v: float) -> int:
	return roundi(v * u)


## Taslaktaki px boyutuyla etiket; spacing de taslak px'i
func _text(t: String, size: float, color := C_INK, serif := false, weight := 400, spacing := 0.0, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	# Arapca/Devanagari harfleri bitisik: aralik acilinca kopuyor
	var sp := 0.0 if lang in ["ar", "hi", "ur"] else spacing
	l.add_theme_font_override("font", _font(serif, weight, sp * u))
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 60 * u
	return l


func _flat(bg := Color.TRANSPARENT, border := Color.TRANSPARENT, bw := 0, radius := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = radius > 0
	return sb


## Sadece alt cizgi (girdi kutulari, liste satirlari)
func _underline(color: Color, w := 1, pad_v := 6.0) -> StyleBoxFlat:
	var sb := _flat()
	sb.border_color = color
	sb.border_width_bottom = w
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = pad_v * u
	sb.content_margin_bottom = pad_v * u
	return sb


## Kenari yumusak dolu daire dokusu (kaydirici tutamaci, secili skin noktasi)
func _dot_tex(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, clampf(r - dist, 0.0, 1.0) * color.a))
	return ImageTexture.create_from_image(img)


## Asagi bakan ince ok (secim kutusu)
func _chevron_tex(w: int, color: Color) -> ImageTexture:
	var h := int(w * 0.6)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a := Vector2(1.0, 1.0)
	var m := Vector2(w / 2.0, h - 1.5)
	var b := Vector2(w - 1.0, 1.0)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(_seg_dist(p, a, m), _seg_dist(p, m, b))
			img.set_pixel(x, y, Color(color, clampf(1.4 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(false)
	t.default_font_size = px(15.5)
	t.set_color("font_color", "Label", C_INK)

	for cls in ["LineEdit"]:
		t.set_stylebox("normal", cls, _underline(C_INK))
		t.set_stylebox("focus", cls, _underline(C_RED, 2))
		t.set_stylebox("read_only", cls, _underline(C_LINE))
		t.set_color("font_color", cls, C_INK)
		t.set_color("font_placeholder_color", cls, C_MUTED)
		t.set_color("caret_color", cls, C_RED)
		t.set_color("selection_color", cls, Color(C_RED, 0.22))
	var te := _flat(Color(C_CARD, 0.6), C_LINE, 1, 2)
	te.set_content_margin_all(8 * u)
	t.set_stylebox("normal", "TextEdit", te)
	var tef := te.duplicate()
	tef.border_color = C_RED
	t.set_stylebox("focus", "TextEdit", tef)
	t.set_color("font_color", "TextEdit", C_INK)
	t.set_color("font_placeholder_color", "TextEdit", C_MUTED)
	t.set_color("caret_color", "TextEdit", C_RED)
	t.set_color("selection_color", "TextEdit", Color(C_RED, 0.22))

	# Secim kutusu: alt cizgi + ince ok
	t.set_stylebox("normal", "OptionButton", _underline(C_INK))
	t.set_stylebox("hover", "OptionButton", _underline(C_RED))
	t.set_stylebox("pressed", "OptionButton", _underline(C_RED))
	t.set_stylebox("hover_pressed", "OptionButton", _underline(C_RED))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "OptionButton", C_INK)
	t.set_icon("arrow", "OptionButton", _chevron_tex(px(11), C_MUTED))
	t.set_constant("arrow_margin", "OptionButton", 0)
	var pop := _flat(C_PAPER, C_LINE, 1, 3)
	pop.set_content_margin_all(6 * u)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("hover", "PopupMenu", _flat(Color(C_RED, 0.1), Color.TRANSPARENT, 0, 2))
	t.set_color("font_color", "PopupMenu", C_INK)
	t.set_color("font_hover_color", "PopupMenu", C_RED)
	t.set_font("font", "PopupMenu", _font(false))
	t.set_font_size("font_size", "PopupMenu", px(15))

	# Kaydirici: ince murekkep cizgi + kirmizi yuvarlak tutamac
	var track := _flat(C_INK)
	track.content_margin_top = 0.5
	track.content_margin_bottom = 0.5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track)
	t.set_stylebox("grabber_area_highlight", "HSlider", track)
	t.set_icon("grabber", "HSlider", _dot_tex(px(13), C_RED))
	t.set_icon("grabber_highlight", "HSlider", _dot_tex(px(15), C_RED))
	t.set_icon("grabber_disabled", "HSlider", _dot_tex(px(13), C_LINE))

	var sb_empty := StyleBoxEmpty.new()
	sb_empty.content_margin_left = 3 * u
	sb_empty.content_margin_right = 3 * u
	t.set_stylebox("scroll", "VScrollBar", sb_empty)
	t.set_stylebox("scroll_focus", "VScrollBar", sb_empty)
	for spec in [["grabber", C_LINE], ["grabber_highlight", C_MUTED], ["grabber_pressed", C_MUTED]]:
		var g := _flat(spec[1], Color.TRANSPARENT, 0, 2)
		g.content_margin_left = 1.5 * u
		g.content_margin_right = 1.5 * u
		t.set_stylebox(spec[0], "VScrollBar", g)

	t.set_stylebox("panel", "TooltipPanel", pop)
	t.set_color("font_color", "TooltipLabel", C_INK)
	return t


func _link(t: String, size: float, color := C_INK, serif := true) -> LinkButton:
	var l := LinkButton.new()
	l.text = t
	l.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	l.add_theme_font_override("font", _font(serif))
	l.add_theme_font_size_override("font_size", px(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_hover_color", C_RED)
	l.add_theme_color_override("font_pressed_color", C_RED)
	l.add_theme_color_override("font_hover_pressed_color", C_RED)
	l.add_theme_color_override("font_focus_color", color)
	l.focus_mode = Control.FOCUS_NONE
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return l


func _red_button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _font(true, 500, 2.0 * u))
	b.add_theme_font_size_override("font_size", px(16))
	for spec in [["normal", C_RED], ["hover", C_RED.lightened(0.08)], ["pressed", C_RED.darkened(0.15)], ["hover_pressed", C_RED.darkened(0.15)]]:
		var sb := _flat(spec[1], Color.TRANSPARENT, 0, 2)
		sb.content_margin_left = 30 * u
		sb.content_margin_right = 30 * u
		sb.content_margin_top = 9 * u
		sb.content_margin_bottom = 9 * u
		b.add_theme_stylebox_override(spec[0], sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, C_CREAM)
	return b


func _rule(top := 22.0, bottom := 6.0) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", px(top))
	m.add_theme_constant_override("margin_bottom", px(bottom))
	var line := ColorRect.new()
	line.color = Color(C_INK, 0.75)
	line.custom_minimum_size.y = 1
	m.add_child(line)
	return m


## Ac/kapa anahtari: solda yazi, sagda kirmizi hap
class Switch:
	extends Button
	var on_color := Color("b8261f")
	var off_color := Color("d9cdb6")
	var knob_color := Color("f6eee0")
	var pill := Vector2(38, 20)
	var bottom := 12.0
	var _k := 0.0

	func _ready() -> void:
		_k = 1.0 if button_pressed else 0.0
		toggled.connect(func(on: bool): create_tween().tween_method(_set_k, _k, 1.0 if on else 0.0, 0.15))

	func _set_k(v: float) -> void:
		_k = v
		queue_redraw()

	func _draw() -> void:
		var p := Vector2(size.x - pill.x, (size.y - bottom - pill.y) / 2.0)
		modulate.a = 0.45 if disabled else 1.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = off_color.lerp(on_color, _k)
		sb.set_corner_radius_all(int(pill.y / 2))
		sb.anti_aliasing = true
		draw_style_box(sb, Rect2(p, pill))
		var kr := pill.y / 2.0 - 3.0
		draw_circle(p + Vector2(lerpf(pill.y / 2.0, pill.x - pill.y / 2.0, _k), pill.y / 2.0), kr, knob_color, true, -1.0, true)


func _switch(t: String, on: bool) -> Button:
	var s := Switch.new()
	s.text = t
	s.toggle_mode = true
	s.button_pressed = on
	s.pill = Vector2(38, 20) * u
	s.bottom = 12 * u
	s.alignment = HORIZONTAL_ALIGNMENT_LEFT
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.add_theme_font_size_override("font_size", px(15.5))
	var line := _underline(C_LINE, 1, 0)
	line.content_margin_bottom = 12 * u
	line.content_margin_right = 50 * u
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		s.add_theme_stylebox_override(st, line)
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		s.add_theme_color_override(c, C_INK)
	return s


## Alt cizgili sekme secimi (ornek: "Bulut (API)  Yerel (Ollama)")
func _segment(labels: Array, selected: int, on_pick: Callable) -> Array:
	var group := ButtonGroup.new()
	var out := []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_override("font", _font(true))
		b.add_theme_font_size_override("font_size", px(16))
		var off := _underline(Color.TRANSPARENT, 2, 4)
		var on := _underline(C_RED, 2, 4)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", C_MUTED)
		b.add_theme_color_override("font_hover_color", C_INK)
		b.add_theme_color_override("font_focus_color", C_MUTED)
		b.add_theme_color_override("font_pressed_color", C_INK)
		b.add_theme_color_override("font_hover_pressed_color", C_INK)
		b.pressed.connect(on_pick.bind(i))
		out.append(b)
	return out


func _segment_box(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", px(26))
	for b in buttons:
		h.add_child(b)
	return h


func _slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size.y = 18 * u
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return s


func _slider_row(s: HSlider, value_label: Label) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", px(14))
	value_label.custom_minimum_size.x = 48 * u
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(s)
	h.add_child(value_label)
	return h


## Ayar alani: kucuk aralikli baslik, kontrol, istege bagli aciklama
func _field(title: String, control: Control, hint := "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", px(7))
	v.add_child(_text(title.to_upper(), 11.5, C_MUTED, false, 500, 2.8))
	v.add_child(control)
	if hint != "":
		v.add_child(_text(hint, 12, C_MUTED, false, 400, 0.0, true))
	return v


# =====================================================================
# Sag sutun: ana gorunum
# =====================================================================

func _build_main(w: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size = Vector2(w, 0)
	v.add_theme_constant_override("separation", 0)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", px(14))
	title.add_child(_text(str(brain_cfg.get("name", "Kevin")), 46, C_INK, true, 600))
	var seal_box := CenterContainer.new()
	var seal := _text("AI", 13, C_CREAM, true, 700)
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.custom_minimum_size = Vector2(30, 30) * u
	seal.add_theme_stylebox_override("normal", _flat(C_RED, Color.TRANSPARENT, 0, 2))
	seal.pivot_offset = Vector2(15, 15) * u
	seal.rotation = deg_to_rad(-4)
	seal_box.add_child(seal)
	title.add_child(seal_box)
	v.add_child(title)
	v.add_child(_text(_tx("sub"), 14, C_MUTED, false, 400, 0.6))
	v.add_child(_rule())

	for i in CATS.size():
		var b := _item("%02d" % (i + 1), _tx("cat_" + CATS[i]))
		b.pressed.connect(_open_category.bind(CATS[i]))
		cat_buttons[CATS[i]] = b
		v.add_child(b)

	var cap_m := MarginContainer.new()
	cap_m.add_theme_constant_override("margin_top", px(30))
	cap_m.add_theme_constant_override("margin_bottom", px(12))
	cap_m.add_child(_text(_tx("characters"), 12, C_MUTED, false, 500, 3.4))
	v.add_child(cap_m)

	skin_grid = GridContainer.new()
	var cell := 56.0 * u
	var gap := 12.0 * u
	skin_grid.columns = maxi(1, int((w + gap) / (cell + gap)))
	skin_grid.add_theme_constant_override("h_separation", int(gap))
	skin_grid.add_theme_constant_override("v_separation", int(gap * 1.4))
	for path in Settings.list_skins():
		_add_skin_card(path)
	var add := Button.new()
	add.text = "+"
	add.custom_minimum_size = Vector2(cell, cell)
	add.focus_mode = Control.FOCUS_NONE
	add.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add.tooltip_text = _tx("add_skin")
	add.add_theme_font_override("font", _font(true))
	add.add_theme_font_size_override("font_size", px(22))
	add.add_theme_color_override("font_color", C_MUTED)
	add.add_theme_color_override("font_hover_color", C_RED)
	add.add_theme_color_override("font_pressed_color", C_RED)
	add.add_theme_stylebox_override("normal", _flat(C_CARD, C_LINE, 1))
	add.add_theme_stylebox_override("hover", _flat(C_CARD, C_RED, 1))
	add.add_theme_stylebox_override("pressed", _flat(C_CARD, C_RED, 1))
	add.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add.pressed.connect(_pick_skin_file)
	skin_grid.add_child(add)
	v.add_child(skin_grid)
	_mark_selected_card()
	return v


## Liste satiri: kirmizi numara, serif ad, sagda ok; uzerine gelince kirmizi
## ve solunda ince cubuk
func _item(num: String, label: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size.y = 50 * u
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := _underline(C_LINE, 1, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, line)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 0)
	b.add_child(h)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var n := _text(num, 13, C_RED, false, 400, 0.8)
	n.custom_minimum_size.x = 42 * u
	var t := _text(label, 19, C_INK, true)
	var arr := _text("›", 16, C_MUTED, true)
	arr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l in [n, t, arr]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
	var bar := ColorRect.new()
	bar.color = C_RED
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(3, 22) * u
	bar.position = Vector2(-14 * u, (50 - 22) / 2.0 * u)
	bar.modulate.a = 0.0
	b.add_child(bar)
	b.mouse_entered.connect(func():
		t.add_theme_color_override("font_color", C_RED)
		arr.add_theme_color_override("font_color", C_RED)
		create_tween().tween_property(bar, "modulate:a", 1.0, 0.12))
	b.mouse_exited.connect(func():
		t.add_theme_color_override("font_color", C_INK)
		arr.add_theme_color_override("font_color", C_MUTED)
		create_tween().tween_property(bar, "modulate:a", 0.0, 0.18))
	b.set_meta("label", t)
	return b


func _build_footer() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_theme_constant_override("separation", px(26))
	foot_link = _link(_tx("close"), 16)
	foot_link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	foot_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot_link.pressed.connect(func():
		if current_cat == "":
			close_requested.emit()
		else:
			_back_to_main())
	h.add_child(foot_link)
	var save := _red_button(_tx("save"))
	save.pressed.connect(_on_save)
	h.add_child(save)
	return h


func _build_stage_links() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", px(8))
	rotate_link = _link(_tx("rotate"), 13, C_MUTED, false)
	rotate_link.toggle_mode = true
	rotate_link.toggled.connect(func(on):
		rotate_link.add_theme_color_override("font_color", C_INK if on else C_MUTED)
		rotate_link.add_theme_font_override("font", _font(false, 600 if on else 400))
		action.emit("auto_rotate_on" if on else "auto_rotate_off"))
	h.add_child(rotate_link)
	h.add_child(_text("·", 13, C_MUTED))
	var em := _link(_tx("emote"), 13, C_MUTED, false)
	em.pressed.connect(func(): action.emit("emote"))
	h.add_child(em)
	h.add_child(_text("·", 13, C_MUTED))
	var rs := _link(_tx("reset"), 13, C_MUTED, false)
	rs.pressed.connect(func():
		rotate_link.button_pressed = false
		action.emit("reset"))
	h.add_child(rs)
	h.add_child(_text("  —  " + _tx("drag_hint"), 13, C_MUTED, false, 400, 0.6))
	return h


func _add_skin_card(path: String) -> void:
	var cell := 56.0 * u
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(cell, cell)
	btn.tooltip_text = path.get_file().get_basename()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var tex := Settings.load_skin(path)
	var face := cell * 0.6
	for region in [Rect2(8, 8, 8, 8), Rect2(40, 8, 8, 8)]:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = region
		var tr := TextureRect.new()
		tr.texture = at
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = Vector2.ONE * (cell - face) / 2.0
		tr.size = Vector2(face, face)
		btn.add_child(tr)
	var dot := TextureRect.new()
	dot.texture = _dot_tex(px(5), C_RED)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.position = Vector2((cell - px(5)) / 2.0, cell + 5 * u)
	btn.add_child(dot)
	btn.set_meta("dot", dot)
	# Kendi eklenen skinler silinebilir: ustune gelince kosede x
	if not path.begins_with("res://"):
		var del := Button.new()
		del.text = "×"
		del.tooltip_text = _tx("delete_skin")
		del.focus_mode = Control.FOCUS_NONE
		del.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		del.add_theme_font_override("font", _font(false, 600))
		del.add_theme_font_size_override("font_size", px(13))
		for st in ["normal", "hover", "pressed"]:
			var sb := _flat(C_RED if st != "normal" else C_INK, Color.TRANSPARENT, 0, int(9 * u))
			sb.content_margin_left = 0
			sb.content_margin_right = 0
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			del.add_theme_stylebox_override(st, sb)
		del.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			del.add_theme_color_override(c, C_CREAM)
		del.size = Vector2(18, 18) * u
		del.position = Vector2(cell - 12 * u, -6 * u)
		del.visible = false
		btn.add_child(del)
		btn.mouse_entered.connect(func(): del.visible = true)
		btn.mouse_exited.connect(func():
			if not del.get_global_rect().has_point(get_global_mouse_position()):
				del.visible = false)
		del.mouse_exited.connect(func():
			if not btn.get_global_rect().has_point(get_global_mouse_position()):
				del.visible = false)
		del.pressed.connect(_delete_skin.bind(path))
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


func _delete_skin(path: String) -> void:
	if not Settings.delete_skin(path):
		return
	var card: Button = skin_cards.get(path)
	skin_cards.erase(path)
	if card:
		card.queue_free()
	# Secili olan silindiyse kalanlardan ilkine gec
	if str(body_cfg.skin) == path:
		var rest := Settings.list_skins()
		if not rest.is_empty():
			body_cfg.skin = rest[0]
			skin_chosen.emit(rest[0])
	_mark_selected_card()


func _mark_selected_card() -> void:
	for p in skin_cards:
		var sel: bool = p == str(body_cfg.skin)
		var card: Button = skin_cards[p]
		card.add_theme_stylebox_override("normal", _flat(C_CARD, C_RED if sel else C_LINE, 2 if sel else 1))
		card.add_theme_stylebox_override("hover", _flat(C_CARD, C_RED, 2 if sel else 1))
		card.add_theme_stylebox_override("pressed", _flat(C_CARD, C_RED, 2))
		(card.get_meta("dot") as Control).visible = sel


func _pick_skin_file() -> void:
	# Kevin'in penceresi Hyprland'de igneli ve "hep ustte": dosya penceresi
	# arkasinda kaliyordu. Dosya penceresi acikken asagi alinir.
	_window_lowered(true)
	DisplayServer.file_dialog_show(_tx("pick_skin"), OS.get_environment("HOME"), "", false,
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


# =====================================================================
# Sag sutun: kategori gorunumu
# =====================================================================

func _build_detail(size_px: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size = size_px
	v.add_theme_constant_override("separation", 0)
	var back := _link(_tx("back_small"), 15, C_MUTED)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_back_to_main)
	v.add_child(back)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", px(12))
	detail_num = _text("", 16, C_RED, true)
	detail_title = _text("", 34, C_INK, true, 600)
	detail_num.size_flags_vertical = Control.SIZE_SHRINK_END
	detail_num.add_theme_constant_override("line_spacing", 0)
	head.add_child(detail_num)
	head.add_child(detail_title)
	var head_m := MarginContainer.new()
	head_m.add_theme_constant_override("margin_top", px(8))
	head_m.add_child(head)
	v.add_child(head_m)
	v.add_child(_rule(18, 18))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll = scroll
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_right", px(10))
	holder.add_theme_constant_override("margin_bottom", px(6))
	scroll.add_child(holder)
	pages["sohbet"] = _page_chat()
	pages["karakter"] = _page_character()
	pages["yapay_zeka"] = _page_ai()
	pages["davranis"] = _page_behaviour()
	pages["hakkinda"] = _page_about()
	for pg in pages.values():
		pg.visible = false
		holder.add_child(pg)
	v.add_child(scroll)
	return v


func _open_category(id: String) -> void:
	if current_cat != "":
		return
	current_cat = id
	if id == "sohbet":
		_fill_chat()
	for k in pages:
		pages[k].visible = k == id
	var idx := CATS.find(id)
	detail_num.text = "%02d" % (idx + 1)
	detail_title.text = _tx("cat_" + id)
	detail_scroll.scroll_vertical = 0
	foot_link.text = _tx("back")

	# Tiklanan satirin adi yerinden baslik yerine kayip buyur, sonra sayfa
	# acilir. Baslik yerini olcmek icin sayfa gorunmez halde bir kare yerlesir.
	var src: Button = cat_buttons[id]
	var src_label: Label = src.get_meta("label")
	var ghost := _text(_tx("cat_" + id), 19, C_RED, true)
	ghost.position = src_label.global_position - column.global_position
	column.add_child(ghost)
	detail_view.visible = true
	detail_view.modulate.a = 0.0
	await get_tree().process_frame
	var target := detail_title.global_position - column.global_position
	var grow := 34.0 / 19.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(main_view, "modulate:a", 0.0, 0.2)
	tw.tween_property(ghost, "position", target, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ghost, "scale", Vector2.ONE * grow, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(c: Color): ghost.add_theme_color_override("font_color", c), C_RED, C_INK, 0.42)
	tw.chain().tween_callback(func():
		main_view.visible = false
		ghost.queue_free())
	tw.chain().tween_property(detail_view, "modulate:a", 1.0, 0.22)


func _back_to_main() -> void:
	if current_cat == "":
		return
	current_cat = ""
	foot_link.text = _tx("close")
	var tw := create_tween()
	tw.tween_property(detail_view, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		detail_view.visible = false
		main_view.visible = true
		main_view.modulate.a = 0.0)
	tw.tween_property(main_view, "modulate:a", 1.0, 0.22)


func _page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", px(22))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


var chat_list: VBoxContainer
var memory_list: VBoxContainer


func _page_chat() -> VBoxContainer:
	var v := _page()
	memory_list = VBoxContainer.new()
	memory_list.add_theme_constant_override("separation", px(8))
	memory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_field(_tx("knows"), memory_list))
	chat_list = VBoxContainer.new()
	chat_list.add_theme_constant_override("separation", px(14))
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_field(_tx("cat_sohbet"), chat_list))
	return v


## Gecmisi ve hafizayi her acilista yeniden oku (beyin bu arada yeni mesaj ya
## da bilgi yazmis olabilir)
func _fill_chat() -> void:
	_fill_memory()
	for c in chat_list.get_children():
		c.queue_free()
	var items := Settings.load_history()
	if items.is_empty():
		chat_list.add_child(_text(_tx("chat_empty"), 14, C_MUTED, false, 400, 0.0, true))
		return
	for m in items:
		var mine: bool = m.get("role", "") == "user"
		var e := VBoxContainer.new()
		e.add_theme_constant_override("separation", px(3))
		e.add_child(_text(_tx("you") if mine else str(brain_cfg.get("name", "Kevin")).to_upper(), 10.5, C_MUTED if mine else C_RED, false, 500, 2.6))
		e.add_child(_text(str(m.get("content", "")), 14.5, C_INK, false, 400, 0.0, true))
		var line := ColorRect.new()
		line.color = C_LINE
		line.custom_minimum_size.y = 1
		e.add_child(line)
		chat_list.add_child(e)
	# En yeni mesaj gorunsun
	await get_tree().process_frame
	await get_tree().process_frame
	if detail_scroll:
		detail_scroll.scroll_vertical = int(detail_scroll.get_v_scroll_bar().max_value)


## Kevin'in konusmalardan ogrendikleri (beynin memory.json'u); tek tek silinir
func _fill_memory() -> void:
	for c in memory_list.get_children():
		c.queue_free()
	var mem := Settings.load_memory()
	var facts: Array = mem.get("facts", [])
	if facts.is_empty():
		memory_list.add_child(_text(_tx("knows_empty"), 13, C_MUTED, false, 400, 0.0, true))
		return
	for f in facts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", px(10))
		var t := _text(str(f.get("text", "")), 14, C_INK, false, 400, 0.0, true)
		row.add_child(t)
		var x := _link("×", 18, C_MUTED, false)
		x.tooltip_text = _tx("forget_one")
		x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var fact_text := str(f.get("text", ""))
		x.pressed.connect(func():
			Settings.forget_fact(fact_text)
			_fill_memory())
		row.add_child(x)
		memory_list.add_child(row)
	var all := _link(_tx("forget_all"), 13, C_RED)
	all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	all.pressed.connect(func():
		Settings.save_memory({"facts": []})
		_fill_memory())
	memory_list.add_child(all)


func _page_character() -> VBoxContainer:
	var v := _page()
	slim_btns = _segment([_tx("arm_classic"), _tx("arm_slim")], 1 if body_cfg.slim else 0,
		func(i): body_cfg.slim = i == 1)
	v.add_child(_field(_tx("arm_model"), _segment_box(slim_btns)))
	scale_slider = _slider(0.6, 2.0, 0.05, float(body_cfg.scale))
	scale_label = _text("", 14)
	scale_slider.value_changed.connect(func(val):
		body_cfg.scale = val
		scale_label.text = "%%%d" % roundi(val * 100))
	scale_label.text = "%%%d" % roundi(float(body_cfg.scale) * 100)
	v.add_child(_field(_tx("size"), _slider_row(scale_slider, scale_label), _tx("size_hint")))
	walk_speed_slider = _slider(0.5, 2.0, 0.1, float(body_cfg.walk_speed))
	v.add_child(_field(_tx("walk_speed"), _slider_row(walk_speed_slider, _value_label(walk_speed_slider, "x%.1f"))))
	speech_slider = _slider(0.6, 1.6, 0.1, float(brain_cfg.get("speechRate", 1.0)))
	v.add_child(_field(_tx("speech_rate"), _slider_row(speech_slider, _value_label(speech_slider, "x%.1f"))))
	volume_slider = _slider(0, 200, 5, roundf(float(brain_cfg.get("voiceVolume", 1.0)) * 100.0))
	v.add_child(_field(_tx("voice_volume"), _slider_row(volume_slider, _value_label(volume_slider, "%%%d"))))
	v.add_child(_text(_tx("skin_hint"), 12.5, C_MUTED, false, 400, 0.0, true))
	return v


## Kaydiricinin yaninda degerini gosteren etiket (fmt: "x%.1f" gibi)
func _value_label(s: HSlider, fmt: String, zero_text := "") -> Label:
	var l := _text("", 14)
	var show := func(val: float):
		l.text = zero_text if zero_text != "" and val <= 0.0 else fmt % val
	s.value_changed.connect(show)
	show.call(s.value)
	return l


func _page_ai() -> VBoxContainer:
	var v := _page()
	var local: bool = Settings.PROVIDERS.get(str(brain_cfg.get("provider", "groq")), {}).get("local", false)

	no_key_label = _text(_tx("no_key"), 13.5, C_RED, false, 500, 0.0, true)
	v.add_child(no_key_label)

	lang_opt = OptionButton.new()
	lang_opt.focus_mode = Control.FOCUS_NONE
	lang_opt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for i in I18n.CODES.size():
		lang_opt.add_item(I18n.NAMES[i])
		if I18n.CODES[i] == lang:
			lang_opt.select(i)
	lang_opt.item_selected.connect(func(i):
		# Dil hemen gecer: ayar yazilir, menu yeni dilde yeniden kurulur
		Settings.save_brain({"language": I18n.CODES[i]})
		action.emit("relang"))
	v.add_child(_field(_tx("language"), lang_opt, _tx("language_hint")))

	mode_btns = _segment([_tx("mode_cloud"), _tx("mode_local")], 1 if local else 0, _on_mode)
	v.add_child(_field(_tx("mode"), _segment_box(mode_btns), _tx("mode_hint")))

	# Bulut: saglayici + anahtar (anahtar al baglantisi ve adimlar)
	var cloud := VBoxContainer.new()
	cloud.add_theme_constant_override("separation", px(22))
	provider_opt = OptionButton.new()
	provider_opt.focus_mode = Control.FOCUS_NONE
	provider_opt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for id in Settings.PROVIDERS:
		if not Settings.PROVIDERS[id].get("local", false):
			provider_opt.add_item(_tx(Settings.PROVIDERS[id].note))
			provider_opt.set_item_metadata(provider_opt.item_count - 1, id)
			if id == str(brain_cfg.get("provider", "")):
				provider_opt.select(provider_opt.item_count - 1)
	provider_opt.item_selected.connect(func(_i):
		# Saglayici degisince anahtar alani o saglayicinin kendi anahtarini gosterir
		key_edit.text = ""
		key_edit.placeholder_text = _tx("key_saved") if _has_key() else _tx("key_new")
		_update_key_notice()
		_fetch_models())
	cloud.add_child(_field(_tx("provider"), provider_opt))
	provider_row = cloud

	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = _tx("key_saved") if _has_key() else _tx("key_new")
	var key_box := VBoxContainer.new()
	key_box.add_theme_constant_override("separation", px(8))
	key_box.add_child(key_edit)
	var get_key := _link(_tx("get_key"), 14, C_RED)
	get_key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	get_key.pressed.connect(func(): OS.shell_open(str(Settings.PROVIDERS[_current_provider()].keys)))
	key_box.add_child(get_key)
	key_row = _field(_tx("api_key"), key_box, _tx("key_steps") + " " + _tx("key_hint"))
	cloud.add_child(key_row)
	v.add_child(cloud)

	# Model: elle yazilmiyor, saglayicidan gelen listeden secilir (anahtar
	# yapistirilinca liste kendiliginden gelir, anahtar da boylece denenmis olur)
	model_list = ItemList.new()
	model_list.custom_minimum_size.y = roundi(210 * u)
	model_list.select_mode = ItemList.SELECT_SINGLE
	model_list.focus_mode = Control.FOCUS_NONE
	model_list.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	model_list.add_theme_font_override("font", _font(false))
	model_list.add_theme_font_size_override("font_size", px(15))
	model_list.add_theme_color_override("font_color", C_INK)
	model_list.add_theme_color_override("font_hovered_color", C_RED)
	model_list.add_theme_color_override("font_selected_color", C_RED)
	model_list.add_theme_constant_override("v_separation", px(6))
	model_list.add_theme_stylebox_override("panel", _flat(Color.TRANSPARENT, Color(C_INK, 0.35), 1, 2))
	model_list.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	model_list.add_theme_stylebox_override("selected", _flat(Color(C_RED, 0.1), Color.TRANSPARENT, 0, 2))
	model_list.add_theme_stylebox_override("selected_focus", _flat(Color(C_RED, 0.1), Color.TRANSPARENT, 0, 2))
	model_list.add_theme_stylebox_override("hovered", _flat(Color(C_INK, 0.05), Color.TRANSPARENT, 0, 2))
	model_list.add_theme_stylebox_override("cursor", StyleBoxEmpty.new())
	model_list.add_theme_stylebox_override("cursor_unfocused", StyleBoxEmpty.new())
	model_status = _text("", 13, C_MUTED, false, 500, 0.0, true)
	ollama_link = _link(_tx("get_ollama"), 14, C_RED)
	ollama_link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ollama_link.visible = false
	ollama_link.pressed.connect(func(): OS.shell_open(str(Settings.PROVIDERS.ollama.keys)))
	# Liste kapali durur, sadece secili model gorunur; tiklayinca acilir,
	# secince kapanir (livi: "tiklanmadikca acilmasinlar")
	model_list.visible = false
	model_list.item_selected.connect(func(_i):
		_update_model_btn()
		model_list.visible = false)
	model_btn = Button.new()
	model_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	model_btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	model_btn.icon = _chevron_tex(px(11), C_MUTED)
	model_btn.focus_mode = Control.FOCUS_NONE
	model_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	model_btn.add_theme_font_override("font", _font(false))
	model_btn.add_theme_font_size_override("font_size", px(16))
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		model_btn.add_theme_stylebox_override(st, _underline(C_RED if st != "normal" else C_INK))
	model_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_pressed_color", "font_focus_color"]:
		model_btn.add_theme_color_override(c, C_INK)
	model_btn.add_theme_color_override("font_hover_color", C_RED)
	model_btn.pressed.connect(func():
		model_list.visible = not model_list.visible
		if model_list.visible:
			model_list.ensure_current_is_visible())
	var model_box := VBoxContainer.new()
	model_box.add_theme_constant_override("separation", px(8))
	model_box.add_child(model_btn)
	model_box.add_child(model_list)
	model_box.add_child(model_status)
	model_box.add_child(ollama_link)
	v.add_child(_field(_tx("model"), model_box, _tx("model_hint2")))

	models_http = HTTPRequest.new()
	models_http.timeout = 8.0
	add_child(models_http)
	models_http.request_completed.connect(_on_models)
	key_timer = Timer.new()
	key_timer.one_shot = true
	key_timer.wait_time = 0.8
	add_child(key_timer)
	key_timer.timeout.connect(_fetch_models)
	key_edit.text_changed.connect(func(_t):
		_update_key_notice()
		key_timer.start())

	name_edit = LineEdit.new()
	name_edit.text = str(brain_cfg.get("name", "Kevin"))
	v.add_child(_field(_tx("name"), name_edit, _tx("name_hint")))

	nick_edit = LineEdit.new()
	nick_edit.text = ", ".join(PackedStringArray(brain_cfg.get("nicknames", [])))
	nick_edit.placeholder_text = "kev, kevo"
	v.add_child(_field(_tx("nicknames"), nick_edit, _tx("nick_hint")))

	var voice := VBoxContainer.new()
	voice.add_theme_constant_override("separation", px(14))
	hands_check = _switch(_tx("hands_free"), brain_cfg.get("handsFree", true) != false)
	live_typing_check = _switch(_tx("live_typing"), brain_cfg.get("liveTyping", true) != false)
	for sw in [hands_check, live_typing_check]:
		voice.add_child(sw)
	voice.add_child(_text(_tx("live_typing_hint"), 12, C_MUTED, false, 400, 0.0, true))
	v.add_child(voice)

	# Konusurken muzik: kis (varsayilan) / duraklat / dokunma. Eski "duraklat"
	# anahtari (pauseMedia) okunmuyor: livi "konusurken sarki duruyor" dedi.
	var media_mode := str(brain_cfg.get("mediaOnTalk", "duck"))
	media_btns = _segment([_tx("media_duck"), _tx("media_pause"), _tx("media_none")],
		maxi(0, MEDIA_MODES.find(media_mode)), func(_i): pass)
	v.add_child(_field(_tx("media_talk"), _segment_box(media_btns), _tx("media_talk_hint")))

	var sess_s := float(brain_cfg.get("voiceSessionMs", 20000)) / 1000.0
	session_slider = _slider(5, 60, 1, sess_s)
	v.add_child(_field(_tx("session"), _slider_row(session_slider, _value_label(session_slider, "%d " + _tx("sec"))), _tx("session_hint")))

	var cam := VBoxContainer.new()
	cam.add_theme_constant_override("separation", px(14))
	camera_check = _switch(_tx("camera_on"), brain_cfg.get("camera", false) == true)
	camera_greet_check = _switch(_tx("camera_greet"), brain_cfg.get("cameraGreet", false) == true)
	cam.add_child(camera_check)
	cam.add_child(camera_greet_check)
	var faces_row := HBoxContainer.new()
	faces_row.add_theme_constant_override("separation", px(12))
	var names := Settings.list_faces()
	var faces_label := _text("%s: %s" % [_tx("faces"), ", ".join(PackedStringArray(names)) if not names.is_empty() else _tx("faces_none")], 13, C_INK, false, 400, 0.0, true)
	faces_row.add_child(faces_label)
	if not names.is_empty():
		var forget := _link(_tx("forget_faces"), 13, C_RED)
		forget.pressed.connect(func():
			Settings.forget_faces()
			faces_label.text = "%s: %s" % [_tx("faces"), _tx("faces_none")]
			forget.visible = false)
		faces_row.add_child(forget)
	cam.add_child(faces_row)
	camera_check.toggled.connect(func(on): camera_greet_check.disabled = not on)
	camera_greet_check.disabled = not camera_check.button_pressed
	v.add_child(_field(_tx("camera"), cam, _tx("camera_hint")))

	persona_edit = TextEdit.new()
	persona_edit.text = str(brain_cfg.get("persona", ""))
	persona_edit.placeholder_text = _tx("persona_ph")
	persona_edit.custom_minimum_size.y = 96 * u
	persona_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_field(_tx("persona"), persona_edit))

	_on_mode(1 if local else 0)
	return v


## Saglayicinin model listesini cek: anahtar dogru mu, internet var mi, Ollama
## kurulu mu; sonuc modelin altinda yaziyor
func _fetch_models() -> void:
	if models_http == null:
		return
	var prov := _current_provider()
	var p: Dictionary = Settings.PROVIDERS[prov]
	var local: bool = p.get("local", false)
	var key := key_edit.text.strip_edges()
	if key == "":
		key = Settings.key_for(brain_cfg, prov)
	ollama_link.visible = false
	models_http.cancel_request()
	if not local and key == "":
		_set_model_status(_tx("st_nokey"), C_RED)
		_fill_models([])
		return
	_set_model_status(_tx("st_checking"), C_MUTED)
	var headers := PackedStringArray() if local else PackedStringArray(["Authorization: Bearer " + key])
	if models_http.request(str(p.url) + "/models", headers) != OK:
		_set_model_status(_tx("st_net"), C_RED)


func _on_models(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var local: bool = Settings.PROVIDERS[_current_provider()].get("local", false)
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_model_status(_tx("st_ollama_none") if local else _tx("st_net"), C_RED)
		ollama_link.visible = local
		_fill_models([])
		return
	if code == 401 or code == 403 or code == 400:
		_set_model_status(_tx("st_badkey"), C_RED)
		_fill_models([])
		return
	if code != 200:
		_set_model_status("HTTP %d" % code, C_RED)
		_fill_models([])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var ids := []
	if data is Dictionary and data.get("data") is Array:
		for m in data.data:
			var id := str(m.get("id", "")).trim_prefix("models/")
			var low := id.to_lower()
			if id != "" and not Settings.NON_CHAT_MODELS.any(func(w): return low.contains(w)):
				ids.append(id)
	ids.sort()
	_set_model_status((_tx("st_ollama_ok") if local else _tx("st_ok")) % ids.size(), C_INK)
	_fill_models(ids)


func _set_model_status(t: String, color: Color) -> void:
	model_status.text = t
	model_status.add_theme_color_override("font_color", color)


## Sohbet modelleri: onerilen en ustte, sonra yeni/kararli surumler once.
## Kayitli model listede varsa secili, yoksa onerilen.
func _fill_models(ids: Array) -> void:
	var prov := _current_provider()
	var rec := str(Settings.PROVIDERS[prov].model)
	var saved := str(brain_cfg.get("model", "")) if prov == str(brain_cfg.get("provider", "")) else ""
	var list := ids.duplicate()
	list.sort_custom(func(a, b): return _model_score(a) > _model_score(b))
	if list.is_empty():
		list = [saved if saved != "" else rec]
	if rec in list:
		list.erase(rec)
		list.push_front(rec)
	model_list.clear()
	for id in list:
		var i := model_list.add_item("%s  (%s)" % [id, _tx("recommended")] if id == rec else id)
		model_list.set_item_metadata(i, id)
	var pick := list.find(saved) if saved in list else 0
	model_list.select(pick)
	model_list.ensure_current_is_visible()
	_update_model_btn()


func _update_model_btn() -> void:
	if model_btn == null:
		return
	var sel := model_list.get_selected_items()
	model_btn.text = model_list.get_item_text(sel[0]) if not sel.is_empty() else "—"


## Model ne kadar "ana akim": yeni surum, kararli ad ustte; tarihli/deneysel
## kopyalar, kucuk/ozel varyantlar altta
static func _model_score(id: String) -> float:
	var low := id.to_lower()
	var score := 0.0
	var m := RegEx.create_from_string("(\\d+(?:\\.\\d+)?)").search(low.get_file())
	if m:
		score += minf(float(m.get_string(1)), 100.0) * 0.1
	for w in ["flash", "pro", "instruct", "versatile", "qwen", "llama", "gpt-oss", "kimi", "deepseek"]:
		if low.contains(w):
			score += 1.0
	for w in ["preview", "exp", "lite", "nano", "mini", "gemma", "thinking", "base"]:
		if low.contains(w):
			score -= 1.2
	if RegEx.create_from_string("-\\d{3,4}$|-\\d{2}-\\d{2}").search(low):
		score -= 3.0
	return score


func _selected_model() -> String:
	var sel := model_list.get_selected_items()
	return str(model_list.get_item_metadata(sel[0])) if not sel.is_empty() else ""


func _has_key() -> bool:
	return Settings.key_for(brain_cfg, _current_provider()) != ""


## Bulut secili ve anahtar yoksa kirmizi uyari (herkes kendi anahtarini girer)
func _update_key_notice() -> void:
	if no_key_label == null:
		return
	var local: bool = mode_btns.size() > 1 and mode_btns[1].button_pressed
	no_key_label.visible = not local and not _has_key() and key_edit.text.strip_edges() == ""


func _page_behaviour() -> VBoxContainer:
	var v := _page()
	walk_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.walk))
	v.add_child(_field(_tx("walk_freq"), _slider_row(walk_slider, _value_label(walk_slider, "x%.1f"))))
	emote_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.emotes))
	v.add_child(_field(_tx("emote_freq"), _slider_row(emote_slider, _value_label(emote_slider, "x%.1f"))))
	var toggles := VBoxContainer.new()
	toggles.add_theme_constant_override("separation", px(14))
	look_check = _switch(_tx("look"), body_cfg.look)
	wallsit_check = _switch(_tx("wall_sit"), body_cfg.wall_sit)
	fun_check = _switch(_tx("fun"), body_cfg.fun)
	mood_check = _switch(_tx("mood"), body_cfg.mood)
	dance_check = _switch(_tx("dance"), body_cfg.dance)
	night_check = _switch(_tx("night"), brain_cfg.get("nightSleepy", true) != false)
	for s in [look_check, wallsit_check, fun_check, mood_check, dance_check]:
		toggles.add_child(s)
	toggles.add_child(_text(_tx("dance_hint"), 12, C_MUTED, false, 400, 0.0, true))
	toggles.add_child(night_check)
	v.add_child(toggles)
	sleep_slider = _slider(0, 60, 5, float(brain_cfg.get("sleepAfterMin", 10)))
	v.add_child(_field(_tx("sleep_after"), _slider_row(sleep_slider, _value_label(sleep_slider, "%d " + _tx("min"), _tx("off")))))
	return v


func _page_about() -> VBoxContainer:
	var v := _page()
	v.add_child(_text(_tx("about_text"), 15.5, C_INK, true, 400, 0.0, true))
	v.add_child(_text("Created by Liviciana", 17, C_RED, true, 600))
	v.add_child(_field(_tx("try_title"), _text(_tx("try_text"), 13.5, C_INK, false, 400, 0.0, true)))
	v.add_child(_field(_tx("animations"), _text("Fresh Animations, Emotecraft (CC0), Quaternius Universal Animation Library 2 (CC0).", 13.5, C_INK, false, 400, 0.0, true)))
	v.add_child(_field(_tx("usage"), _text(_tx("usage_text"), 13.5, C_INK, false, 400, 0.0, true)))
	# Her acilista olculen sistem ve secilen calisma duzeyi
	var sp := SysProfile.detect()
	var sys_line := "%d CPU · %s GB RAM · %s · %d %s, %d Hz\n%s · %d fps" % [sp.cores, str(sp.ram_gb), sp.gpu, sp.screens, "ekran" if lang == "tr" else "display", sp.refresh, _tx("perf_" + str(sp.tier)), Engine.max_fps]
	v.add_child(_field(_tx("system"), _text(sys_line, 13.5, C_INK, false, 400, 0.0, true), _tx("system_hint")))
	var replay := _link(_tx("replay_splash") + "  ›", 16, C_RED)
	replay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	replay.pressed.connect(func(): action.emit("splash"))
	v.add_child(replay)
	return v


func _on_mode(i: int) -> void:
	var local := i == 1
	if provider_row:
		provider_row.visible = not local
	_update_key_notice()
	_fetch_models()


func _current_provider() -> String:
	if mode_btns.size() > 1 and mode_btns[1].button_pressed:
		return "ollama"
	if provider_opt and provider_opt.selected >= 0:
		return str(provider_opt.get_item_metadata(provider_opt.selected))
	return "groq"


## Kategoriyi canlandirmasiz ac (dil degisince menu yeniden kurulurken)
func open_instant(id: String) -> void:
	current_cat = id
	for k in pages:
		pages[k].visible = k == id
	detail_num.text = "%02d" % (CATS.find(id) + 1)
	detail_title.text = _tx("cat_" + id)
	foot_link.text = _tx("back")
	main_view.visible = false
	detail_view.visible = true
	detail_view.modulate.a = 1.0


static func brain_needs_key(cfg: Dictionary) -> bool:
	var local: bool = Settings.PROVIDERS.get(str(cfg.get("provider", "")), {}).get("local", false)
	return not local and Settings.key_for(cfg, str(cfg.get("provider", ""))) == ""


## Test icin: kategoriyi ac
func _select_tab(id: String) -> void:
	if pages.has(id) and current_cat == "":
		_open_category(id)


# =====================================================================
# Kaydet
# =====================================================================

func _on_save() -> void:
	body_cfg.walk = walk_slider.value
	body_cfg.emotes = emote_slider.value
	body_cfg.look = look_check.button_pressed
	body_cfg.wall_sit = wallsit_check.button_pressed
	body_cfg.fun = fun_check.button_pressed
	body_cfg.mood = mood_check.button_pressed
	body_cfg.dance = dance_check.button_pressed
	body_cfg.walk_speed = walk_speed_slider.value
	Settings.save_body(body_cfg)

	var brain := {
		"provider": _current_provider(),
		"model": _selected_model(),
		"name": name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Kevin",
		"nicknames": Array(nick_edit.text.split(",", false)).map(func(s): return s.strip_edges()).filter(func(s): return s != ""),
		"handsFree": hands_check.button_pressed,
		"voiceSessionMs": int(session_slider.value * 1000),
		"persona": persona_edit.text,
		"speechRate": speech_slider.value,
		"camera": camera_check.button_pressed,
		"cameraGreet": camera_greet_check.button_pressed,
		"mediaOnTalk": MEDIA_MODES[maxi(0, media_btns.find_custom(func(b): return b.button_pressed))],
		"voiceVolume": volume_slider.value / 100.0,
		"liveTyping": live_typing_check.button_pressed,
		"nightSleepy": night_check.button_pressed,
		"sleepAfterMin": int(sleep_slider.value),
	}
	# Anahtarlar saglayici basina; "apiKey" her zaman secili saglayicinin
	# anahtari (beyin onu okuyor). Baska saglayicinin anahtari kullanilmaz.
	var keys: Dictionary = {}
	if brain_cfg.get("apiKeys") is Dictionary:
		keys = brain_cfg.apiKeys.duplicate()
	var old_prov := str(brain_cfg.get("provider", ""))
	if old_prov != "" and not keys.has(old_prov) and str(brain_cfg.get("apiKey", "")) != "":
		keys[old_prov] = str(brain_cfg.apiKey)
	if key_edit.text.strip_edges() != "":
		keys[brain.provider] = key_edit.text.strip_edges()
	brain["apiKeys"] = keys
	brain["apiKey"] = str(keys.get(brain.provider, ""))
	Settings.save_brain(brain)

	var needs_reload: bool = body_cfg.slim != original_body.slim or absf(float(body_cfg.scale) - float(original_body.scale)) > 0.001
	saved.emit(needs_reload)


# =====================================================================
# Giris / cikis: sakin kayma + belirme, satirlar sirayla
# =====================================================================

func _animate_in() -> void:
	var items: Array = [caption, stage_links, footer]
	items.append_array(main_view.get_children())
	var i := 0
	for node in items:
		var c: Control = node
		c.modulate.a = 0.0
		var delay := 0.12 + i * 0.045
		var tw := create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(delay)
		i += 1
	var final := column.position
	column.position = final + Vector2(24 * u, 0)
	create_tween().tween_property(column, "position", final, 0.55).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func animate_out(_view: Vector2) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(column, "position:x", column.position.x + 24 * u, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	return tw
