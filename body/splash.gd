extends Control
## Acilis ekrani: livi'nin verdigi poster referansi (anime poster grafik
## tasarimi): adacayi gri kareli zemin, karakterin arkasinda dev egik yazi,
## krem patlama, yarim ton noktalar, baglanti cizgileri, etiketler, konusma
## patlamasi, onde ikinci dev yazi. Renkler: adacayi gri, koyu murdum, krem,
## mint, pembe-kirmizi vurgu.
##
## Iki katman: make_back() Kevin'in ARKASINDA (SubViewport -> 3B duzlem),
## bu dugum (on katman) Kevin'in ONUNDE. Parcalar ayri ayri canlandiriliyor.
const I18n := preload("res://i18n.gd")


const C_BG := Color("5f6965")
const C_GRID := Color("6d7773")
const C_PLUM := Color("2c2230")
const C_CREAM := Color("efe3c8")
const C_MINT := Color("cde9df")
const C_PINK := Color("ec4b5c")

var W := 740.0
var H := 925.0
var big: Font
var small: Font
var bar_progress := 0.0
var bar_text := ""
var bar_piece: Control
var pieces := []


## Metinlerin dili (main ayarlardan atiyor)
static var lang := "tr"


static func tx(key: String) -> String:
	return I18n.get_text(key, lang)


static func anton() -> Font:
	var f = load("res://fonts/Anton-Regular.ttf")
	if not (f is Font):
		return ThemeDB.fallback_font
	# Anton'da Arapca/Devanagari/Kiril yok: o harfler sistem fontundan
	if (f as Font).fallbacks.is_empty():
		(f as Font).fallbacks = [ui_font(800)]
	return f


static func ui_font(weight := 700) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Inter", "Noto Sans", "DejaVu Sans", "Segoe UI", "Arial"])
	f.font_weight = weight
	return f


## Ortak parca: tum postere yayilan, kendi cizim fonksiyonu olan dugum.
## pivot: canlandirma (buyume/donme) merkezi.
class Piece:
	extends Control
	var fn: Callable
	func _draw() -> void:
		fn.call(self)


static func _piece(parent: Control, size: Vector2, pivot: Vector2, fn: Callable) -> Control:
	var p := Piece.new()
	p.size = size
	p.pivot_offset = pivot
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.fn = fn
	parent.add_child(p)
	return p


# =====================================================================
# Cizim yardimcilari
# =====================================================================

static func _star(ci: CanvasItem, c: Vector2, r_out: float, r_in: float, spikes: int, col: Color, outline := Color.TRANSPARENT, width := 0.0, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var a := rot + i * PI / spikes
		var r := r_out if i % 2 == 0 else r_in
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)
	if width > 0.0:
		var o := pts.duplicate()
		o.append(pts[0])
		ci.draw_polyline(o, outline, width, true)


static func _halftone(ci: CanvasItem, rect: Rect2, step: float, col: Color, max_r: float, falloff: Vector2) -> void:
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var t := clampf(1.0 - Vector2(x, y).distance_to(falloff) / rect.size.length(), 0.0, 1.0)
			var r := max_r * t * t
			if r > 0.4:
				ci.draw_circle(Vector2(x, y), r, col)
			x += step
		y += step


## Egik (italik) ve dis cizgili buyuk yazi
static func _big_text(ci: CanvasItem, font: Font, text: String, pos: Vector2, size: int, fill: Color, outline: Color, ow: int, skew := -0.18, rot := 0.0) -> void:
	var tr := Transform2D(rot, Vector2.ONE, skew, pos)
	ci.draw_set_transform_matrix(tr)
	if ow > 0:
		ci.draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ow, outline)
	ci.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fill)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# =====================================================================
# Arka katman (Kevin'in arkasinda)
# =====================================================================

static func make_back(size: Vector2) -> Control:
	var root := Control.new()
	root.size = size
	var w := size.x
	var h := size.y
	var font := anton()
	var sf := ui_font(600)

	# Mint paralelkenar (sol orta)
	_piece(root, size, Vector2(w * 0.25, h * 0.45), func(ci: CanvasItem):
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.06, h * 0.30), Vector2(w * 0.40, h * 0.27),
			Vector2(w * 0.35, h * 0.64), Vector2(w * 0.04, h * 0.67)]), C_MINT))

	# Krem patlama (kafanin arkasi), icinde yarim ton
	var burst := _piece(root, size, Vector2(w * 0.62, h * 0.21), func(ci: CanvasItem):
		var c := Vector2(w * 0.62, h * 0.21)
		_star(ci, c, w * 0.24, w * 0.13, 13, C_CREAM, C_PLUM, 3.0, 0.2)
		_halftone(ci, Rect2(c - Vector2(w * 0.12, h * 0.08), Vector2(w * 0.24, h * 0.16)), w * 0.02, Color(C_PLUM, 0.35), w * 0.007, c))
	burst.set_meta("anim", "pop")
	burst.set_meta("order", 0.5)

	# Sag koyu blok + "SENIN" ("Selam, ben Kevin, senin arkadasin")
	var block := _piece(root, size, Vector2(w * 0.82, h * 0.4), func(ci: CanvasItem):
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.64, h * 0.31), Vector2(w * 0.97, h * 0.29),
			Vector2(w * 0.97, h * 0.49), Vector2(w * 0.67, h * 0.51)]), C_PLUM)
		# Yazi bloga sigsin
		var fsz := int(h * 0.15)
		var your := tx("splash_your")
		if your == "":
			return
		var tw := font.get_string_size(your, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		fsz = int(fsz * minf(1.0, (w * 0.27) / tw))
		_big_text(ci, font, your, Vector2(w * 0.685, h * 0.465), fsz, C_CREAM, C_PLUM, 0, -0.12))
	block.set_meta("anim", "right")
	block.set_meta("order", 3)

	# Dev "KEVIN" (kafanin arkasinda)
	var title := _piece(root, size, Vector2(w * 0.33, h * 0.25), func(ci: CanvasItem):
		_big_text(ci, font, "KEVİN" if lang == "tr" else "KEVIN", Vector2(w * 0.05, h * 0.36), int(h * 0.2), C_PLUM, C_CREAM, int(h * 0.009), -0.16, -0.06))
	title.set_meta("anim", "slam")
	title.set_meta("order", 2)

	return root


# =====================================================================
# On katman (Kevin'in onunde)
# =====================================================================

func build(sz: Vector2) -> void:
	W = sz.x
	H = sz.y
	size = sz
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	big = anton()
	small = ui_font(700)
	var w := W
	var h := H

	var hello := _piece(self, sz, Vector2(w * 0.2, h * 0.1), func(ci: CanvasItem):
		_big_text(ci, big, tx("splash_hello"), Vector2(w * 0.05, h * 0.135), int(h * 0.085), C_MINT, C_PLUM, int(h * 0.006), -0.2, -0.04))
	hello.set_meta("anim", "left")
	hello.set_meta("order", 1)

	# Pembe unlem cizgileri (kafanin yaninda)
	var bang := _piece(self, sz, Vector2(w * 0.63, h * 0.29), func(ci: CanvasItem):
		var c := Vector2(w * 0.63, h * 0.29)
		for i in 5:
			var a := -2.2 + i * 0.32
			var d := Vector2(cos(a), sin(a))
			var n := Vector2(-d.y, d.x)
			var p0 := c + d * w * 0.05
			var p1 := c + d * w * 0.13
			ci.draw_colored_polygon(PackedVector2Array([p0 - n * 2.0, p1 - n * w * 0.012, p1 + n * w * 0.012, p0 + n * 2.0]), C_PINK))
	bang.set_meta("anim", "pop")
	bang.set_meta("order", 2.5)

	# Koyu konusma patlamasi (sol alt)
	var speech := _piece(self, sz, Vector2(w * 0.19, h * 0.68), func(ci: CanvasItem):
		var c := Vector2(w * 0.19, h * 0.68)
		_star(ci, c, w * 0.2, w * 0.15, 12, C_PLUM, C_CREAM, 2.5, 0.1)
		var tr := Transform2D(-0.14, Vector2.ONE, -0.12, c + Vector2(-w * 0.11, -h * 0.03))
		ci.draw_set_transform_matrix(tr)
		var lines := tx("splash_say").split("|")
		for i in lines.size():
			ci.draw_string(big, Vector2(0, h * 0.042 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.034), C_CREAM)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY))
	speech.set_meta("anim", "pop")
	# Cumle ("Selam, ben Kevin, senin arkadasin") bittikten sonra
	speech.set_meta("order", 5.5)

	# Onde dev "ARKADASIN"
	var bottom := _piece(self, sz, Vector2(w * 0.5, h * 0.9), func(ci: CanvasItem):
		_big_text(ci, big, tx("splash_friend"), Vector2(w * 0.09, h * 0.965), int(h * 0.16), C_MINT, C_PLUM, int(h * 0.008), -0.16, -0.02))
	bottom.set_meta("anim", "up")
	bottom.set_meta("order", 4)

	# Yukleniyor cubugu (referanstaki "<<<< Dopamine detox")
	bar_piece = _piece(self, sz, Vector2(w * 0.82, h * 0.78), func(ci: CanvasItem):
		var r := Rect2(w * 0.68, h * 0.755, w * 0.29, h * 0.042)
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_PLUM
		sb.set_corner_radius_all(6)
		ci.draw_style_box(sb, r)
		var fill := Rect2(r.position, Vector2(r.size.x * bar_progress, r.size.y))
		var fb := StyleBoxFlat.new()
		fb.bg_color = Color(C_MINT, 0.35)
		fb.set_corner_radius_all(6)
		ci.draw_style_box(fb, fill)
		for i in 4:
			var x := r.position.x + w * 0.012 + i * w * 0.016
			var cy := r.get_center().y
			ci.draw_polyline(PackedVector2Array([Vector2(x + w * 0.01, cy - h * 0.011), Vector2(x, cy), Vector2(x + w * 0.01, cy + h * 0.011)]), C_CREAM, 3.0)
		ci.draw_string(small, Vector2(r.position.x + w * 0.09, r.get_center().y + h * 0.007), bar_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.017), C_CREAM))
	bar_piece.set_meta("anim", "right")
	bar_piece.set_meta("order", 4.8)

func set_progress(p: float, text: String) -> void:
	bar_progress = clampf(p, 0.0, 1.0)
	bar_text = text
	if bar_piece:
		bar_piece.queue_redraw()


# =====================================================================
# Canlandirma: carpma, pit diye buyume, yanlardan kayma
# =====================================================================

static func animate_in(root: Control, start_delay: float) -> void:
	for p in root.get_children():
		var kind: String = p.get_meta("anim", "fade")
		# Tek tek, yavas (livi: "asiri hizli geliyor"). Arka ve on katman ayni
		# zaman cizgisinde: cumle sirasiyla gelir.
		var d := start_delay + float(p.get_meta("order", 0)) * 0.4
		var tw := p.create_tween().set_parallel(true)
		p.modulate.a = 0.0
		match kind:
			"slam":
				p.scale = Vector2(1.6, 1.6)
				tw.tween_property(p, "scale", Vector2.ONE, 0.7).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"pop":
				p.scale = Vector2(0.2, 0.2)
				tw.tween_property(p, "scale", Vector2.ONE, 1.0).set_delay(d).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			"left":
				p.position.x = -p.size.x * 0.5
				tw.tween_property(p, "position:x", 0.0, 0.8).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"right":
				p.position.x = p.size.x * 0.5
				tw.tween_property(p, "position:x", 0.0, 0.8).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			"up":
				p.position.y = p.size.y * 0.3
				tw.tween_property(p, "position:y", 0.0, 0.85).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 1.0, 0.4).set_delay(d)


static func animate_out(root: Control) -> void:
	var i := 0
	for p in root.get_children():
		var tw := p.create_tween().set_parallel(true)
		var d := i * 0.025
		i += 1
		tw.tween_property(p, "scale", Vector2(1.15, 1.15), 0.3).set_delay(d).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "modulate:a", 0.0, 0.3).set_delay(d)
