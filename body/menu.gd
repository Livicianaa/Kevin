extends Control
## Kevin'in menusu (karaktere sag tik). Sade Japon tarzi: krem kagit, murekkep
## siyahi yazi, tek vurgu rengi hanko kirmizisi. Solda Kevin (arkasinda firca
## darbesi ensō), sagda numarali kategori listesi, altinda karakterler.
## Kategoriye basinca baslik yukari kayar, sutun o kategorinin ayarlarina doner.
## Olculer 880x900'luk taslaktan (~/Pictures/kevin-menu-taslak-sade-japon.png)
## u katsayisiyla olcekleniyor.

signal close_requested
signal saved(needs_reload: bool)
signal skin_chosen(path: String)
signal action(name: String)

const Settings := preload("res://settings.gd")

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
var model_edit: LineEdit
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
var rotate_link: LinkButton

var original_body := {}

const CATS := [["sohbet", "Sohbet"], ["karakter", "Karakter"], ["yapay_zeka", "Yapay Zeka"], ["davranis", "Davranış"], ["hakkinda", "Hakkında"]]


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
		"enso_c": Vector2((EDGE + col_x) / 2.0, feet - h * 0.56),
		"enso_r": size_px.y * 0.215,
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

	caption = _text("KEVİN · AYARLAR", 12, C_MUTED, false, 500, 3.8)
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
# Kagit panel + ince doku + Kevin'in arkasinda firca darbesi ensō.
# =====================================================================

class Paper:
	extends Control
	var lay := {}

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
		_enso(lay.enso_c, lay.enso_r)

	## Acik kalan firca halkasi: kalinligi degisen, uclari incelen, kenari
	## hafif titrek tek darbe; icinde kuru firca izleri
	func _enso(c: Vector2, r: float) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var start := -0.55
		var span := TAU * 0.93
		var n := 160
		var w0 := r * 0.058
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var center := PackedVector2Array()
		var wob := []
		for i in 6:
			wob.append([rng.randf_range(1.0, 4.0), rng.randf_range(0.0, TAU), rng.randf_range(0.004, 0.012)])
		for i in n:
			var t := float(i) / (n - 1)
			var a := start - span * t
			var rr := r * (1.0 + 0.05 * sin(t * PI * 1.3 + 0.4) - 0.03 * t)
			for wb in wob:
				rr += r * wb[2] * sin(t * TAU * wb[0] + wb[1])
			var p := c + Vector2(cos(a), sin(a)) * rr
			var taper := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.7, 1.0, t) * 0.85)
			var half := w0 * (0.55 + 0.45 * sin(t * PI)) * taper + 0.6
			var nrm := Vector2(cos(a), sin(a))
			outer.append(p + nrm * half)
			inner.append(p - nrm * half)
			center.append(p)
		var poly := outer.duplicate()
		inner.reverse()
		poly.append_array(inner)
		var ink := Color(0.149, 0.125, 0.098, 0.22)
		draw_colored_polygon(poly, ink)
		# Uyumluluk render'inda 2B MSAA yok: kenarlari yumusak cizgiyle ort
		# (fircanin kenarinda biriken murekkep gibi hafif koyu durur)
		inner.reverse()
		draw_polyline(outer, Color(ink, ink.a * 0.7), 1.2, true)
		draw_polyline(inner, Color(ink, ink.a * 0.7), 1.2, true)
		for k in 4:
			var streak := PackedVector2Array()
			var off := rng.randf_range(-0.6, 0.6) * w0
			var from := int(rng.randf_range(0.05, 0.4) * n)
			var to := int(rng.randf_range(0.65, 0.95) * n)
			for i in range(from, to):
				var a := start - span * float(i) / (n - 1)
				streak.append(center[i] + Vector2(cos(a), sin(a)) * off)
			draw_polyline(streak, Color(ink, 0.12), 1.0, true)


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


func px(v: float) -> int:
	return roundi(v * u)


## Taslaktaki px boyutuyla etiket; spacing de taslak px'i
func _text(t: String, size: float, color := C_INK, serif := false, weight := 400, spacing := 0.0, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", _font(serif, weight, spacing * u))
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
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
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
	v.add_child(_text("masaüstü arkadaşın", 14, C_MUTED, false, 400, 0.6))
	v.add_child(_rule())

	for i in CATS.size():
		var b := _item("%02d" % (i + 1), CATS[i][1])
		b.pressed.connect(_open_category.bind(CATS[i][0]))
		cat_buttons[CATS[i][0]] = b
		v.add_child(b)

	var cap_m := MarginContainer.new()
	cap_m.add_theme_constant_override("margin_top", px(30))
	cap_m.add_theme_constant_override("margin_bottom", px(12))
	cap_m.add_child(_text("KARAKTERLER", 12, C_MUTED, false, 500, 3.4))
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
	add.tooltip_text = "Skin ekle (png)"
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
	foot_link = _link("Kapat", 16)
	foot_link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	foot_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot_link.pressed.connect(func():
		if current_cat == "":
			close_requested.emit()
		else:
			_back_to_main())
	h.add_child(foot_link)
	var save := _red_button("Kaydet")
	save.pressed.connect(_on_save)
	h.add_child(save)
	return h


func _build_stage_links() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", px(8))
	rotate_link = _link("Döndür", 13, C_MUTED, false)
	rotate_link.toggle_mode = true
	rotate_link.toggled.connect(func(on):
		rotate_link.add_theme_color_override("font_color", C_INK if on else C_MUTED)
		rotate_link.add_theme_font_override("font", _font(false, 600 if on else 400))
		action.emit("auto_rotate_on" if on else "auto_rotate_off"))
	h.add_child(rotate_link)
	h.add_child(_text("·", 13, C_MUTED))
	var em := _link("Emote", 13, C_MUTED, false)
	em.pressed.connect(func(): action.emit("emote"))
	h.add_child(em)
	h.add_child(_text("·", 13, C_MUTED))
	var rs := _link("Sıfırla", 13, C_MUTED, false)
	rs.pressed.connect(func():
		rotate_link.button_pressed = false
		action.emit("reset"))
	h.add_child(rs)
	h.add_child(_text("  —  karakteri sürükleyerek çevir", 13, C_MUTED, false, 400, 0.6))
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
		var card: Button = skin_cards[p]
		card.add_theme_stylebox_override("normal", _flat(C_CARD, C_RED if sel else C_LINE, 2 if sel else 1))
		card.add_theme_stylebox_override("hover", _flat(C_CARD, C_RED, 2 if sel else 1))
		card.add_theme_stylebox_override("pressed", _flat(C_CARD, C_RED, 2))
		(card.get_meta("dot") as Control).visible = sel


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


# =====================================================================
# Sag sutun: kategori gorunumu
# =====================================================================

func _build_detail(size_px: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size = size_px
	v.add_theme_constant_override("separation", 0)
	var back := _link("‹ geri", 15, C_MUTED)
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
	var idx := 0
	for i in CATS.size():
		if CATS[i][0] == id:
			idx = i
	detail_num.text = "%02d" % (idx + 1)
	detail_title.text = CATS[idx][1]
	detail_scroll.scroll_vertical = 0
	foot_link.text = "Geri"

	# Tiklanan satirin adi yerinden baslik yerine kayip buyur, sonra sayfa
	# acilir. Baslik yerini olcmek icin sayfa gorunmez halde bir kare yerlesir.
	var src: Button = cat_buttons[id]
	var src_label: Label = src.get_meta("label")
	var ghost := _text(CATS[idx][1], 19, C_RED, true)
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
	foot_link.text = "Kapat"
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


func _page_chat() -> VBoxContainer:
	var v := _page()
	chat_list = VBoxContainer.new()
	chat_list.add_theme_constant_override("separation", px(14))
	chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(chat_list)
	return v


## Gecmisi her acilista yeniden oku (beyin bu arada yeni mesaj yazmis olabilir)
func _fill_chat() -> void:
	for c in chat_list.get_children():
		c.queue_free()
	var items := Settings.load_history()
	if items.is_empty():
		chat_list.add_child(_text("Henüz konuşma yok. \"Kevin\" diye seslen ya da Kevin'e orta tıkla.", 14, C_MUTED, false, 400, 0.0, true))
		return
	for m in items:
		var mine: bool = m.get("role", "") == "user"
		var e := VBoxContainer.new()
		e.add_theme_constant_override("separation", px(3))
		e.add_child(_text("SEN" if mine else "KEVİN", 10.5, C_MUTED if mine else C_RED, false, 500, 2.6))
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


func _page_character() -> VBoxContainer:
	var v := _page()
	slim_btns = _segment(["Klasik (4 px)", "İnce (3 px)"], 1 if body_cfg.slim else 0,
		func(i): body_cfg.slim = i == 1)
	v.add_child(_field("Kol modeli", _segment_box(slim_btns)))
	scale_slider = _slider(0.6, 2.0, 0.05, float(body_cfg.scale))
	scale_label = _text("", 14)
	scale_slider.value_changed.connect(func(val):
		body_cfg.scale = val
		scale_label.text = "%%%d" % roundi(val * 100))
	scale_label.text = "%%%d" % roundi(float(body_cfg.scale) * 100)
	v.add_child(_field("Boyut", _slider_row(scale_slider, scale_label), "Kol modeli ve boyut Kaydet'e basınca uygulanır."))
	v.add_child(_text("Skin: ana menüdeki Karakterler'den seç, + ile kendi png'ni ekle (64x64 Minecraft skin).", 12.5, C_MUTED, false, 400, 0.0, true))
	return v


func _page_ai() -> VBoxContainer:
	var v := _page()
	var local: bool = Settings.PROVIDERS.get(str(brain_cfg.get("provider", "groq")), {}).get("local", false)
	mode_btns = _segment(["Bulut (API)", "Yerel (Ollama)"], 1 if local else 0, _on_mode)
	v.add_child(_field("Çalışma şekli", _segment_box(mode_btns), "Bulut: hızlı, internet ve anahtar ister. Yerel: bilgisayarında çalışır, Ollama kurulu olmalı."))

	provider_opt = OptionButton.new()
	provider_opt.focus_mode = Control.FOCUS_NONE
	provider_opt.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for id in Settings.PROVIDERS:
		if not Settings.PROVIDERS[id].get("local", false):
			provider_opt.add_item(Settings.PROVIDERS[id].label)
			provider_opt.set_item_metadata(provider_opt.item_count - 1, id)
			if id == str(brain_cfg.get("provider", "")):
				provider_opt.select(provider_opt.item_count - 1)
	provider_opt.item_selected.connect(func(_i): _update_model_placeholder())
	provider_row = _field("Sağlayıcı", provider_opt)
	v.add_child(provider_row)

	model_edit = LineEdit.new()
	model_edit.text = str(brain_cfg.get("model", ""))
	v.add_child(_field("Model", model_edit, "Boş bırakırsan sağlayıcının varsayılanı."))

	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "•••••••• kayıtlı (değiştirmek için yaz)" if str(brain_cfg.get("apiKey", "")) != "" else "API anahtarını yapıştır"
	key_row = _field("API anahtarı", key_edit, "Sadece bu bilgisayarda saklanır.")
	v.add_child(key_row)

	name_edit = LineEdit.new()
	name_edit.text = str(brain_cfg.get("name", "Kevin"))
	v.add_child(_field("İsim", name_edit, "Bu isimle seslenince uyanır."))

	nick_edit = LineEdit.new()
	nick_edit.text = ", ".join(PackedStringArray(brain_cfg.get("nicknames", [])))
	nick_edit.placeholder_text = "kev, kevo"
	v.add_child(_field("Lakaplar", nick_edit, "Virgülle ayır."))

	hands_check = _switch("Eller serbest dinleme", brain_cfg.get("handsFree", true) != false)
	v.add_child(hands_check)

	var sess_s := float(brain_cfg.get("voiceSessionMs", 20000)) / 1000.0
	session_slider = _slider(5, 60, 1, sess_s)
	session_label = _text("%d sn" % int(sess_s), 14)
	session_slider.value_changed.connect(func(val): session_label.text = "%d sn" % int(val))
	v.add_child(_field("Sohbet süresi", _slider_row(session_slider, session_label), "Adını söyledikten sonra ne kadar dinlesin."))

	persona_edit = TextEdit.new()
	persona_edit.text = str(brain_cfg.get("persona", ""))
	persona_edit.placeholder_text = "Boş: varsayılan kişilik (esprili, samimi, Türkçe)."
	persona_edit.custom_minimum_size.y = 96 * u
	persona_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_field("Kişilik", persona_edit))

	_on_mode(1 if local else 0)
	return v


func _page_behaviour() -> VBoxContainer:
	var v := _page()
	walk_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.walk))
	var walk_label := _text("", 14)
	walk_slider.value_changed.connect(func(val): walk_label.text = "x%.1f" % val)
	walk_label.text = "x%.1f" % walk_slider.value
	v.add_child(_field("Yürüme sıklığı", _slider_row(walk_slider, walk_label)))
	emote_slider = _slider(0.0, 2.0, 0.1, float(body_cfg.emotes))
	var emote_label := _text("", 14)
	emote_slider.value_changed.connect(func(val): emote_label.text = "x%.1f" % val)
	emote_label.text = "x%.1f" % emote_slider.value
	v.add_child(_field("Emote sıklığı", _slider_row(emote_slider, emote_label)))
	var toggles := VBoxContainer.new()
	toggles.add_theme_constant_override("separation", px(14))
	look_check = _switch("Fareyi arada merak edip baksın", body_cfg.look)
	wallsit_check = _switch("Kenara yaslanıp otursun", body_cfg.wall_sit)
	fun_check = _switch("Eğlenceli emote'lar (dans vb.)", body_cfg.fun)
	for s in [look_check, wallsit_check, fun_check]:
		toggles.add_child(s)
	v.add_child(toggles)
	return v


func _page_about() -> VBoxContainer:
	var v := _page()
	v.add_child(_text("Masaüstünde yaşayan, konuşan ve bilgisayarını kullanabilen yapay zeka arkadaşı.", 15.5, C_INK, true, 400, 0.0, true))
	v.add_child(_text("Created by Liviciana", 17, C_RED, true, 600))
	v.add_child(_field("Animasyonlar", _text("Fresh Animations (kullanıcının paketi), Emotecraft emote'ları (CC0), Quaternius Universal Animation Library 2 (CC0).", 13.5, C_INK, false, 400, 0.0, true)))
	v.add_child(_field("Kullanım", _text("Menü: karaktere sağ tık. Karakteri sürükle: döndür. Esc: kapat. Orta tık: Kevin'i uyandır.", 13.5, C_INK, false, 400, 0.0, true)))
	var replay := _link("Açılış ekranını oynat  ›", 16, C_RED)
	replay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
