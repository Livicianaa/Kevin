import json
import os
import sys
import time
import traceback

out = sys.stdout
sys.stdout = sys.stderr


def reply(obj):
    out.write(json.dumps(obj) + "\n")
    out.flush()


def main():
    applio = os.path.abspath(sys.argv[1])
    os.chdir(applio)
    sys.path.insert(0, applio)
    from rvc.infer.infer import VoiceConverter

    vc = VoiceConverter()
    reply({"ready": True})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        job = {}
        try:
            job = json.loads(line)
            started = time.time()
            pitch = job.get("pitch")
            vc.convert_audio(
                audio_input_path=job["input"],
                audio_output_path=job["output"],
                model_path=job["model"],
                index_path=job.get("index") or "",
                pitch=int(pitch or 0),
                proposed_pitch=pitch is None,
                proposed_pitch_threshold=float(job.get("target_hz") or 155.0),
                index_rate=float(job.get("index_rate", 0.6)),
                protect=0.4,
                f0_method="rmvpe",
                export_format="WAV",
            )
            if not os.path.exists(job["output"]):
                raise RuntimeError("cikti olusmadi")
            reply({"id": job.get("id"), "ok": True, "sec": round(time.time() - started, 2)})
        except Exception as err:
            traceback.print_exc()
            reply({"id": job.get("id"), "ok": False, "error": str(err)[:300]})


if __name__ == "__main__":
    main()
