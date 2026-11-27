extends Node3D

const PX := 1.0 / 16.0

const PALETTES := [
	Color("5a1e1e"),
	Color("1f2a44"),
	Color("23402e"),
	Color("4a2e1c"),
]

var left_cover_node: Node3D
var right_cover_node: Node3D
var left_inner_node: Node3D
var right_inner_node: Node3D
var spine_node: Node3D
var turn_node: Node3D

var cover_front_mat: StandardMaterial3D
var cover_edge_mat: StandardMaterial3D
var page_left_mat: StandardMaterial3D
var page_right_mat: StandardMaterial3D
var page_edge_mat: StandardMaterial3D
var page_cream_mat: StandardMaterial3D
var spine_mat: StandardMaterial3D

var turning := false
var turn_t := 0.0
var turn_dur := 0.35
var open_ratio := 0.0


func _ready() -> void:
	_build_materials("Default")
	_build_meshes()
	set_open_amount(0.0)


func set_title(title: String) -> void:
	var h: int = abs(title.hash())
	var base_col: Color = PALETTES[h % PALETTES.size()]
	_update_textures(base_col, h)


func _build_materials(title: String) -> void:
	cover_front_mat = StandardMaterial3D.new()
	cover_front_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cover_front_mat.roughness = 0.85

	cover_edge_mat = StandardMaterial3D.new()
	cover_edge_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cover_edge_mat.roughness = 0.85

	page_left_mat = StandardMaterial3D.new()
	page_left_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_left_mat.roughness = 0.85

	page_right_mat = StandardMaterial3D.new()
	page_right_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_right_mat.roughness = 0.85

	page_edge_mat = StandardMaterial3D.new()
	page_edge_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_edge_mat.roughness = 0.85

	page_cream_mat = StandardMaterial3D.new()
	page_cream_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	page_cream_mat.roughness = 0.85

	spine_mat = StandardMaterial3D.new()
	spine_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spine_mat.roughness = 0.85

	set_title(title)


func _update_textures(base_col: Color, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var gold_col := Color("d4a94a")

	var img_cover := Image.create(18, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 18:
			var noise := rng.randf_range(-0.06, 0.06)
			var c := Color(
				clampf(base_col.r * (1.0 + noise), 0.0, 1.0),
				clampf(base_col.g * (1.0 + noise), 0.0, 1.0),
				clampf(base_col.b * (1.0 + noise), 0.0, 1.0)
			)
			if x == 0 or x == 17 or y == 0 or y == 23:
				c = c * 0.75
			elif (y == 2 or y == 21) and (x >= 2 and x <= 15):
				c = gold_col
			img_cover.set_pixel(x, y, c)
	cover_front_mat.albedo_texture = ImageTexture.create_from_image(img_cover)

	var img_cover_edge := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img_cover_edge.fill(base_col * 0.8)
	cover_edge_mat.albedo_texture = ImageTexture.create_from_image(img_cover_edge)

	var cream := Color("f2ead6")
	var text_col := Color("8a8173")
	var shadow_col := cream.lerp(text_col, 0.22)

	var img_page_cream := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img_page_cream.fill(cream)
	page_cream_mat.albedo_texture = ImageTexture.create_from_image(img_page_cream)

	var img_page_edge := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		var row_col := text_col if (y % 2 == 1) else cream
		for x in 16:
			img_page_edge.set_pixel(x, y, row_col)
	page_edge_mat.albedo_texture = ImageTexture.create_from_image(img_page_edge)

	var img_spine := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img_spine.fill(base_col * 0.75)
	for y in 24:
		if y == 2 or y == 21:
			for x in 16:
				img_spine.set_pixel(x, y, gold_col)
	spine_mat.albedo_texture = ImageTexture.create_from_image(img_spine)

	var img_left := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img_left.fill(cream)
	for y in 24:
		img_left.set_pixel(14, y, shadow_col)
		img_left.set_pixel(15, y, shadow_col)
		if y >= 3 and y <= 21 and y % 2 == 1:
			var line_len := rng.randi_range(6, 12)
			for x in range(2, 2 + line_len):
				if x < 14:
					img_left.set_pixel(x, y, text_col)
	page_left_mat.albedo_texture = ImageTexture.create_from_image(img_left)

	var img_right := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	img_right.fill(cream)
	for y in 24:
		img_right.set_pixel(0, y, shadow_col)
		img_right.set_pixel(1, y, shadow_col)
		if y >= 3 and y <= 21 and y % 2 == 1:
			var line_len := rng.randi_range(6, 12)
			for x in range(2, 2 + line_len):
				if x < 14:
					img_right.set_pixel(x, y, text_col)
	page_right_mat.albedo_texture = ImageTexture.create_from_image(img_right)


func _make_box(size: Vector3, mats: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var faces := [
		{
			"normal": Vector3(1, 0, 0),
			"verts": [Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)]
		},
		{
			"normal": Vector3(-1, 0, 0),
			"verts": [Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz)]
		},
		{
			"normal": Vector3(0, 1, 0),
			"verts": [Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]
		},
		{
			"normal": Vector3(0, -1, 0),
			"verts": [Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz)]
		},
		{
			"normal": Vector3(0, 0, 1),
			"verts": [Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)]
		},
		{
			"normal": Vector3(0, 0, -1),
			"verts": [Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz)]
		}
	]

	var uvs := PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

	for i in 6:
		var face: Dictionary = faces[i]
		var norm: Vector3 = face["normal"]
		var v: Array = face["verts"]
		var verts := PackedVector3Array([v[0], v[1], v[2], v[3]])
		var norms := PackedVector3Array([norm, norm, norm, norm])

		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices

		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		if i < mats.size() and mats[i] != null:
			mesh.surface_set_material(i, mats[i])

	return mesh


func _build_meshes() -> void:
	left_cover_node = Node3D.new()
	add_child(left_cover_node)

	var l_cover := MeshInstance3D.new()
	l_cover.mesh = _make_box(
		Vector3(9.0, 12.0, 0.8) * PX,
		[cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_front_mat]
	)
	l_cover.position = Vector3(-4.5 * PX, 0, -0.4 * PX)
	left_cover_node.add_child(l_cover)

	var l_page_flat := MeshInstance3D.new()
	l_page_flat.mesh = _make_box(
		Vector3(6.4, 11.2, 1.8) * PX,
		[page_cream_mat, page_edge_mat, page_edge_mat, page_edge_mat, page_left_mat, page_cream_mat]
	)
	l_page_flat.position = Vector3(-5.4 * PX, 0, 0.9 * PX)
	left_cover_node.add_child(l_page_flat)

	left_inner_node = Node3D.new()
	left_inner_node.position = Vector3(-2.2 * PX, 0, 0.9 * PX)
	left_inner_node.rotation.y = deg_to_rad(18.0)
	left_cover_node.add_child(left_inner_node)

	var l_page_inner := MeshInstance3D.new()
	l_page_inner.mesh = _make_box(
		Vector3(2.1, 11.2, 1.8) * PX,
		[page_edge_mat, page_cream_mat, page_edge_mat, page_edge_mat, page_left_mat, page_cream_mat]
	)
	l_page_inner.position = Vector3(1.0 * PX, 0, 0)
	left_inner_node.add_child(l_page_inner)

	right_cover_node = Node3D.new()
	add_child(right_cover_node)

	var r_cover := MeshInstance3D.new()
	r_cover.mesh = _make_box(
		Vector3(9.0, 12.0, 0.8) * PX,
		[cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_edge_mat, cover_front_mat]
	)
	r_cover.position = Vector3(4.5 * PX, 0, -0.4 * PX)
	right_cover_node.add_child(r_cover)

	var r_page_flat := MeshInstance3D.new()
	r_page_flat.mesh = _make_box(
		Vector3(6.4, 11.2, 1.8) * PX,
		[page_edge_mat, page_cream_mat, page_edge_mat, page_edge_mat, page_right_mat, page_cream_mat]
	)
	r_page_flat.position = Vector3(5.4 * PX, 0, 0.9 * PX)
	right_cover_node.add_child(r_page_flat)

	right_inner_node = Node3D.new()
	right_inner_node.position = Vector3(2.2 * PX, 0, 0.9 * PX)
	right_inner_node.rotation.y = deg_to_rad(-18.0)
	right_cover_node.add_child(right_inner_node)

	var r_page_inner := MeshInstance3D.new()
	r_page_inner.mesh = _make_box(
		Vector3(2.1, 11.2, 1.8) * PX,
		[page_cream_mat, page_edge_mat, page_edge_mat, page_edge_mat, page_right_mat, page_cream_mat]
	)
	r_page_inner.position = Vector3(-1.0 * PX, 0, 0)
	right_inner_node.add_child(r_page_inner)

	spine_node = Node3D.new()
	add_child(spine_node)

	var sp_mid := MeshInstance3D.new()
	sp_mid.mesh = _make_box(
		Vector3(0.8, 12.0, 2.6) * PX,
		[spine_mat, spine_mat, spine_mat, spine_mat, spine_mat, spine_mat]
	)
	sp_mid.position = Vector3(0, 0, -1.3 * PX)
	spine_node.add_child(sp_mid)

	var sp_left := MeshInstance3D.new()
	sp_left.mesh = _make_box(
		Vector3(0.4, 11.6, 2.2) * PX,
		[spine_mat, spine_mat, spine_mat, spine_mat, spine_mat, spine_mat]
	)
	sp_left.position = Vector3(-0.6 * PX, 0, -1.2 * PX)
	spine_node.add_child(sp_left)

	var sp_right := MeshInstance3D.new()
	sp_right.mesh = _make_box(
		Vector3(0.4, 11.6, 2.2) * PX,
		[spine_mat, spine_mat, spine_mat, spine_mat, spine_mat, spine_mat]
	)
	sp_right.position = Vector3(0.6 * PX, 0, -1.2 * PX)
	spine_node.add_child(sp_right)

	turn_node = Node3D.new()
	add_child(turn_node)

	var turn_mesh := MeshInstance3D.new()
	turn_mesh.mesh = _make_box(
		Vector3(8.4, 11.2, 0.12) * PX,
		[page_edge_mat, page_edge_mat, page_edge_mat, page_edge_mat, page_right_mat, page_left_mat]
	)
	turn_mesh.position = Vector3(4.4 * PX, 0, 0)
	turn_node.add_child(turn_mesh)
	turn_node.position.z = 1.82 * PX
	turn_node.visible = false


func set_open_amount(k: float) -> void:
	open_ratio = clampf(k, 0.0, 1.0)
	var angle := lerpf(deg_to_rad(88.0), deg_to_rad(10.0), open_ratio)
	left_cover_node.rotation.y = angle
	right_cover_node.rotation.y = -angle
	var off_x := lerpf(1.61 * PX, 0.0, open_ratio)
	left_cover_node.position.x = -off_x
	right_cover_node.position.x = off_x


func turn_page(duration := 0.35) -> void:
	turning = true
	turn_t = 0.0
	turn_dur = duration
	turn_node.visible = true
	turn_node.rotation.y = right_cover_node.rotation.y
	turn_node.position.x = right_cover_node.position.x


func _process(delta: float) -> void:
	if turning:
		turn_t += delta
		var p := clampf(turn_t / turn_dur, 0.0, 1.0)
		var e := ease(p, -2.0)
		turn_node.rotation.y = lerpf(right_cover_node.rotation.y, left_cover_node.rotation.y, e)
		turn_node.position.x = lerpf(right_cover_node.position.x, left_cover_node.position.x, e)
		if p >= 1.0:
			turning = false
			turn_node.visible = false
