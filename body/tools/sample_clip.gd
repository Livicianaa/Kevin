extends SceneTree
## Bir glTF animasyon klibinin eklem konumlarini (30 kare/sn) JSON'a yazar.
## Quaternius Universal Animation Library klipleri buradan Kevin'e aktarildi.
## Kullanim: godot --headless --path body --script res://tools/sample_clip.gd -- <glb> <klip> <cikti.json>
const BONES := ["pelvis", "spine_03", "neck_01", "Head", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"]


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(args[0], st) != OK:
		print("yuklenemedi")
		quit()
		return
	var scene := doc.generate_scene(st)
	root.add_child(scene)
	await process_frame
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var anim := ap.get_animation(args[1])
	ap.play(args[1])
	var out := {"length": anim.length, "fps": 30, "frames": []}
	var t := 0.0
	while t <= anim.length + 0.001:
		ap.seek(t, true)
		sk.force_update_all_bone_transforms()
		var f := {}
		for b in BONES:
			var p: Vector3 = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin
			f[b] = [p.x, p.y, p.z]
		out.frames.append(f)
		t += 1.0 / 30.0
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(out))
	print("kare=", out.frames.size(), " sure=", anim.length)
	quit()
