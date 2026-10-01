extends RefCounted
## Her acilista bilgisayarin ozelliklerine bakilir; Kevin ona gore calisir.
## Guclu makinede ekranin yenileme hizinda akici, zayifta daha dusuk kare
## hizi ve daha az kendiliginden hareket (islemciyi yormasin).

const TIER_LOW := "low"
const TIER_MID := "mid"
const TIER_HIGH := "high"


static func detect() -> Dictionary:
	var cores := OS.get_processor_count()
	var ram_gb := 0.0
	var mem := OS.get_memory_info()
	if mem.has("physical") and int(mem.physical) > 0:
		ram_gb = float(mem.physical) / 1073741824.0
	var gpu := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var refresh := 60.0
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_refresh_rate(i)
		if r > refresh:
			refresh = r
	var g := (gpu + " " + vendor).to_lower()
	var software := g.contains("llvmpipe") or g.contains("softpipe") or g.contains("swiftshader")
	var discrete := g.contains("nvidia") or g.contains("geforce") or g.contains("radeon rx") or g.contains("arc a")
	var tier := TIER_MID
	if software or cores <= 4 or (ram_gb > 0.0 and ram_gb < 6.0):
		tier = TIER_LOW
	elif cores >= 8 and (ram_gb == 0.0 or ram_gb >= 12.0) and discrete:
		tier = TIER_HIGH
	return {
		"cores": cores,
		"ram_gb": snappedf(ram_gb, 0.1),
		"gpu": gpu,
		"screens": DisplayServer.get_screen_count(),
		"refresh": roundi(refresh),
		"tier": tier,
	}


## Kare hizi: guclu makinede ekranin yenileme hizi (en fazla 120), orta 60,
## zayif 30
static func max_fps(p: Dictionary) -> int:
	match p.tier:
		TIER_HIGH:
			return clampi(int(p.refresh), 60, 120)
		TIER_LOW:
			return 30
	return 60


## Kendiliginden hareket carpani (yurume/emote sikligi): zayif makinede seyrek
static func activity(p: Dictionary) -> float:
	return 0.6 if p.tier == TIER_LOW else 1.0
