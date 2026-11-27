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
	var gpu := clean_gpu(RenderingServer.get_video_adapter_name())
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
		"cpu": clean_cpu(OS.get_processor_name()),
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


## Windows'ta GL Compatibility cogu AMD/Intel kartta ANGLE uzerinden calisiyor;
## ad "ANGLE (AMD, AMD Radeon(TM) Graphics Direct3D11 vs_5_0 ps_5_0, D3D11)"
## gibi geliyor. Kullaniciya sadece kartin adi gosterilir.
static func clean_gpu(raw: String) -> String:
	var g := raw.strip_edges()
	if g.begins_with("ANGLE (") and g.ends_with(")"):
		var parts := g.substr(7, g.length() - 8).split(", ")
		g = parts[1] if parts.size() > 1 else parts[0]
		var cut := g.find(" Direct3D")
		if cut > 0:
			g = g.substr(0, cut)
	for junk in ["(TM)", "(R)", "(tm)", "(r)", "/PCIe/SSE2"]:
		g = g.replace(junk, "")
	return g.strip_edges() if g.strip_edges() != "" else "?"


static func clean_cpu(raw: String) -> String:
	var c := raw.strip_edges()
	for junk in ["(TM)", "(R)", "(tm)", "(r)", " CPU", " Processor"]:
		c = c.replace(junk, "")
	var at := c.find(" @ ")
	if at > 0:
		c = c.substr(0, at)
	while c.contains("  "):
		c = c.replace("  ", " ")
	return c.strip_edges() if c.strip_edges() != "" else "?"
