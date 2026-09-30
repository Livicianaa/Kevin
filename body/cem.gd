extends RefCounted
## OptiFine CEM (.jem) animasyon paketlerini (Fresh Animations / Fresh Moves)
## calistirir. Ifadeler her karede yorumlanmiyor: acilista GERCEK GDScript
## koduna derlenip calisma aninda yukleniyor (yorumlayici ~10 kat yavasti).
##
## Paket dosyasi repoda DEGIL (lisans): kullanici kendi paketini
## bin/cem/player.jem'e koyuyor.

var warnings: PackedStringArray = []
var _runner: RefCounted = null

const FUNCS := {
	"sin": "sin", "cos": "cos", "tan": "tan", "asin": "asin", "acos": "acos",
	"atan": "atan", "atan2": "atan2", "abs": "absf", "floor": "floorf",
	"ceil": "ceilf", "exp": "exp", "log": "log", "pow": "pow", "sqrt": "sqrt",
	"signum": "signf", "fmod": "fmod", "torad": "deg_to_rad", "todeg": "rad_to_deg",
	"clamp": "clampf", "frac": "_frac", "wraprad": "_wraprad", "wrapdeg": "_wrapdeg",
	"between": "_between", "equals": "_equals", "lerp": "_lerp", "random": "_rand",
	"print": "",
}


static func load_pack(path: String) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var cem := new()
	if not cem._compile(FileAccess.get_file_as_string(path)):
		return null
	return cem


## pose: duz sozluk ("head_rx", "left_leg_ty" ...), yerinde guncellenir.
func apply(pose: Dictionary, context: Dictionary) -> void:
	_runner.run(pose, context)


# =====================================================================
# Derleme
# =====================================================================

var _parts := {}
var _context := {}
var _vars := {}


func _compile(text: String) -> bool:
	var re := RegEx.create_from_string("(?m)//[^\\n\"]*$")
	var data = JSON.parse_string(re.sub(text, "", true))
	if data == null:
		warnings.append("jem JSON olarak okunamadi")
		return false

	var assignments := []
	_collect(data, assignments)

	var lines := PackedStringArray()
	for a in assignments:
		var target: String = a[0]
		var code := ""
		var err := ""
		var parsed = _parse(str(a[1]))
		if parsed is String:
			err = parsed
		else:
			code = _emit(parsed)
		if err != "":
			warnings.append("%s: %s" % [target, err])
			continue
		var name := _target_name(target)
		if name == "":
			continue
		lines.append("\t%s = _f(%s, %s)" % [name, code, name])

	var src := PackedStringArray([
		"extends RefCounted",
		"var vars := {}",
		"func _t(x: float) -> bool:\n\treturn x != 0.0",
		"func _f(x: float, old: float) -> float:\n\treturn x if is_finite(x) else old",
		"func _frac(x: float) -> float:\n\treturn x - floorf(x)",
		"func _wraprad(x: float) -> float:\n\treturn wrapf(x, -PI, PI)",
		"func _wrapdeg(x: float) -> float:\n\treturn wrapf(x, -180.0, 180.0)",
		"func _between(x: float, lo: float, hi: float) -> float:\n\treturn 1.0 if x >= lo and x <= hi else 0.0",
		"func _equals(a: float, b: float, eps: float = 0.0001) -> float:\n\treturn 1.0 if absf(a - b) <= eps else 0.0",
		"func _lerp(t: float, a: float, b: float) -> float:\n\treturn a + (b - a) * t",
		"func _rand(s: float = NAN) -> float:\n\tif is_nan(s):\n\t\treturn randf()\n\tvar x := sin(s * 12.9898) * 43758.5453\n\treturn x - floorf(x)",
		"func run(pose: Dictionary, ctx: Dictionary) -> void:",
	])
	for n in _parts:
		src.append("\tvar %s: float = pose.get(\"%s\", 0.0)" % [n, n.substr(2)])
	for n in _context:
		src.append("\tvar %s: float = float(ctx.get(\"%s\", 0.0))" % [n, _context[n]])
	for n in _vars:
		src.append("\tvar %s: float = vars.get(\"%s\", 0.0)" % [n, n])
	src.append_array(lines)
	for n in _parts:
		src.append("\tpose[\"%s\"] = %s" % [n.substr(2), n])
	for n in _vars:
		src.append("\tvars[\"%s\"] = %s" % [n, n])

	var script := GDScript.new()
	script.source_code = "\n".join(src)
	if script.reload() != OK:
		warnings.append("derlenen kod yuklenemedi")
		return false
	_runner = script.new()
	return true


func _collect(node, out: Array) -> void:
	if node is Array:
		for n in node:
			_collect(n, out)
	elif node is Dictionary:
		for key in node:
			if key == "animations" and node[key] is Array:
				for frame in node[key]:
					if frame is Dictionary:
						for target in frame:
							out.append([target, frame[target]])
			else:
				_collect(node[key], out)


## "head.rx" -> p_head_rx, "var.walk" -> v_walk, "varb.x" -> vb_x
func _target_name(target: String) -> String:
	var dot := target.find(".")
	if dot < 0:
		return ""
	var head := target.substr(0, dot)
	var field := target.substr(dot + 1)
	if head == "var":
		return _var_name("v_" + field)
	if head == "varb":
		return _var_name("vb_" + field)
	if field in ["rx", "ry", "rz", "tx", "ty", "tz", "sx", "sy", "sz"]:
		return _part_name(head + "_" + field)
	return ""


func _var_name(n: String) -> String:
	_vars[n] = true
	return n


func _part_name(n: String) -> String:
	var name := "p_" + n
	_parts[name] = true
	return name


func _ident(token: String) -> String:
	match token:
		"pi":
			return "PI"
		"true":
			return "1.0"
		"false":
			return "0.0"
	if token.contains("."):
		var t := _target_name(token)
		return t if t != "" else "0.0"
	var name := "c_" + token
	_context[name] = token
	return name


# --- Ayristirici: belirtecler -> agac --------------------------------

var _tokens: PackedStringArray
var _pos := 0


func _tokenize(src: String):
	var out := PackedStringArray()
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if (c >= "0" and c <= "9") or (c == "." and i + 1 < n and src[i + 1] >= "0" and src[i + 1] <= "9"):
			var j := i
			while j < n and ((src[j] >= "0" and src[j] <= "9") or src[j] == "."):
				j += 1
			out.append(src.substr(i, j - i))
			i = j
			continue
		if c == "_" or (c.to_lower() != c.to_upper()):
			var j := i
			while j < n and (src[j] == "_" or src[j] == "." or (src[j] >= "0" and src[j] <= "9") or src[j].to_lower() != src[j].to_upper()):
				j += 1
			out.append(src.substr(i, j - i))
			i = j
			continue
		var two := src.substr(i, 2)
		if two in ["&&", "||", "<=", ">=", "==", "!="]:
			out.append(two)
			i += 2
			continue
		if c in ["-", "+", "*", "/", "%", "(", ")", ",", "<", ">", "!"]:
			out.append(c)
			i += 1
			continue
		return "cozumlenemeyen karakter: " + c
	return out


func _parse(src: String):
	var toks = _tokenize(src)
	if toks is String:
		return toks
	_tokens = toks
	_pos = 0
	var node = _p_or()
	if node is String:
		return node
	if _pos != _tokens.size():
		return "fazladan belirtec: " + _tokens[_pos]
	return node


func _peek() -> String:
	return _tokens[_pos] if _pos < _tokens.size() else ""


func _next() -> String:
	_pos += 1
	return _tokens[_pos - 1] if _pos - 1 < _tokens.size() else ""


func _p_or():
	var left = _p_and()
	while not (left is String) and _peek() == "||":
		_next()
		var right = _p_and()
		if right is String:
			return right
		left = ["||", left, right]
	return left


func _p_and():
	var left = _p_cmp()
	while not (left is String) and _peek() == "&&":
		_next()
		var right = _p_cmp()
		if right is String:
			return right
		left = ["&&", left, right]
	return left


func _p_cmp():
	var left = _p_add()
	if left is String:
		return left
	var op := _peek()
	if op in ["<", ">", "<=", ">=", "==", "!="]:
		_next()
		var right = _p_add()
		if right is String:
			return right
		return ["cmp", op, left, right]
	return left


func _p_add():
	var left = _p_mul()
	while not (left is String) and (_peek() == "+" or _peek() == "-"):
		var op := _next()
		var right = _p_mul()
		if right is String:
			return right
		left = [op, left, right]
	return left


func _p_mul():
	var left = _p_unary()
	while not (left is String) and (_peek() == "*" or _peek() == "/" or _peek() == "%"):
		var op := _next()
		var right = _p_unary()
		if right is String:
			return right
		left = [op, left, right]
	return left


func _p_unary():
	match _peek():
		"-":
			_next()
			var v = _p_unary()
			return v if v is String else ["neg", v]
		"!":
			_next()
			var v = _p_unary()
			return v if v is String else ["not", v]
		"+":
			_next()
			return _p_unary()
	return _p_primary()


func _p_primary():
	var tok := _next()
	if tok == "":
		return "ifade beklenmedik sekilde bitti"
	if tok == "(":
		var inner = _p_or()
		if inner is String:
			return inner
		if _next() != ")":
			return ") bekleniyordu"
		return inner
	if tok[0] == "." or (tok[0] >= "0" and tok[0] <= "9"):
		return ["num", tok]
	if _peek() == "(":
		_next()
		var args := []
		if _peek() != ")":
			while true:
				var a = _p_or()
				if a is String:
					return a
				args.append(a)
				if _peek() == ",":
					_next()
					continue
				break
		if _next() != ")":
			return ") bekleniyordu"
		if tok != "if" and not FUNCS.has(tok) and tok != "min" and tok != "max":
			return "bilinmeyen fonksiyon: " + tok
		return ["call", tok, args]
	return ["id", tok]


# --- Kod uretimi: agac -> GDScript -----------------------------------

func _emit(n) -> String:
	match n[0]:
		"num":
			var s: String = n[1]
			if s.begins_with("."):
				s = "0" + s
			return s if s.contains(".") else s + ".0"
		"id":
			return _ident(n[1])
		"+", "-", "*", "/":
			return "(%s %s %s)" % [_emit(n[1]), n[0], _emit(n[2])]
		"%":
			return "fmod(%s, %s)" % [_emit(n[1]), _emit(n[2])]
		"cmp":
			return "(1.0 if %s %s %s else 0.0)" % [_emit(n[2]), n[1], _emit(n[3])]
		"&&":
			return "(1.0 if _t(%s) and _t(%s) else 0.0)" % [_emit(n[1]), _emit(n[2])]
		"||":
			return "(1.0 if _t(%s) or _t(%s) else 0.0)" % [_emit(n[1]), _emit(n[2])]
		"neg":
			return "(-%s)" % _emit(n[1])
		"not":
			return "(0.0 if _t(%s) else 1.0)" % _emit(n[1])
		"call":
			return _emit_call(n[1], n[2])
	return "0.0"


func _emit_call(fn: String, args: Array) -> String:
	var a := PackedStringArray()
	for x in args:
		a.append(_emit(x))

	# if(kosul, deger, [kosul2, deger2, ...] varsayilan) - tembel else-if zinciri
	if fn == "if":
		var tail := a[a.size() - 1] if a.size() % 2 == 1 else "0.0"
		var pairs := a.size() - (a.size() % 2)
		var i := pairs - 2
		while i >= 0:
			tail = "(%s if _t(%s) else %s)" % [a[i + 1], a[i], tail]
			i -= 2
		return tail

	if fn == "min" or fn == "max":
		var f := "minf" if fn == "min" else "maxf"
		var acc := a[0]
		for i in range(1, a.size()):
			acc = "%s(%s, %s)" % [f, acc, a[i]]
		return acc

	var mapped: String = FUNCS[fn]
	if mapped == "":
		return a[0] if a.size() > 0 else "0.0"
	return "%s(%s)" % [mapped, ", ".join(a)]
