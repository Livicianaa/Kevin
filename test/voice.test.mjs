import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createVoices } from '../voice.js';

describe('Voice manager tests', () => {
  let tmpUserDir;
  let tmpStaging;
  let voices;

  before(() => {
    tmpUserDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kevin-user-'));
    tmpStaging = fs.mkdtempSync(path.join(os.tmpdir(), 'kevin-staging-'));
    voices = createVoices({ userDir: tmpUserDir, searchHome: tmpUserDir });
  });

  after(() => {
    try { fs.rmSync(tmpUserDir, { recursive: true, force: true }); } catch {}
    try { fs.rmSync(tmpStaging, { recursive: true, force: true }); } catch {}
  });

  test('install fake 11 MB .pth and .index, list and meta are correct', () => {
    const fakePth = path.join(tmpStaging, 'singer_voice.pth');
    const pthBuf = Buffer.alloc(11 * 1024 * 1024, 0x41);
    fs.writeFileSync(fakePth, pthBuf);

    const fakeIndex = path.join(tmpStaging, 'singer_voice.index');
    fs.writeFileSync(fakeIndex, Buffer.from('index data'));

    const res = voices.install([fakePth, fakeIndex]);
    assert.equal(res.ok, true);
    assert.ok(res.voice);
    assert.equal(res.voice.type, 'rvc');
    assert.equal(res.voice.name, 'singer voice');
    assert.equal(res.voice.pitch, null);
    assert.equal(res.voice.target_hz, 155);
    assert.ok(fs.existsSync(res.voice.model));
    assert.ok(fs.existsSync(res.voice.index));

    const list = voices.list();
    assert.equal(list.length, 1);
    assert.equal(list[0].id, res.voice.id);
    assert.equal(list[0].name, 'singer voice');
    assert.equal(list[0].type, 'rvc');
    assert.equal(list[0].pitch, null);
    assert.equal(list[0].target_hz, 155);

    const meta = voices.get(res.voice.id);
    assert.ok(meta);
    assert.equal(meta.id, res.voice.id);
    assert.equal(meta.name, 'singer voice');
    assert.equal(meta.model, res.voice.model);
    assert.equal(meta.index, res.voice.index);
  });

  test('name cleaning: yaseminsannino_e40_s1000.pth -> yaseminsannino', () => {
    const pth = path.join(tmpStaging, 'yaseminsannino_e40_s1000.pth');
    fs.writeFileSync(pth, Buffer.alloc(11 * 1024 * 1024, 0x42));

    const res = voices.install([pth]);
    assert.equal(res.ok, true);
    assert.equal(res.voice.name, 'yaseminsannino');
  });

  test('name cleaning: gercek_100e_14900s.pth -> gercek', () => {
    const pth = path.join(tmpStaging, 'gercek_100e_14900s.pth');
    fs.writeFileSync(pth, Buffer.alloc(11 * 1024 * 1024, 0x43));

    const res = voices.install([pth]);
    assert.equal(res.ok, true);
    assert.equal(res.voice.name, 'gercek');
  });

  test('reject training files: G_2333333.pth', () => {
    const pth = path.join(tmpStaging, 'G_2333333.pth');
    fs.writeFileSync(pth, Buffer.alloc(11 * 1024 * 1024, 0x44));

    const res = voices.install([pth]);
    assert.equal(res.ok, false);
    assert.match(res.error, /Bu eğitim dosyası, ses modeli değil/);
  });

  test('reject suspicious size .pth: < 10 MB or > 1 GB', () => {
    const smallPth = path.join(tmpStaging, 'small_model.pth');
    fs.writeFileSync(smallPth, Buffer.alloc(5 * 1024 * 1024, 0x45));

    const res = voices.install([smallPth]);
    assert.equal(res.ok, false);
    assert.match(res.error, /boyutu geçersiz/);
  });

  test('.onnx missing json error', () => {
    const onnxFolder = path.join(tmpStaging, 'onnx-solo');
    fs.mkdirSync(onnxFolder, { recursive: true });
    const onnxPath = path.join(onnxFolder, 'piper_voice.onnx');
    fs.writeFileSync(onnxPath, Buffer.from('fake onnx binary'));

    const res = voices.install([onnxPath]);
    assert.equal(res.ok, false);
    assert.equal(res.error, 'onnx.json eksik');
  });

  test('.onnx with json installs piper voice', () => {
    const onnxFolder = path.join(tmpStaging, 'onnx-pair');
    fs.mkdirSync(onnxFolder, { recursive: true });
    const onnxPath = path.join(onnxFolder, 'piper_test.onnx');
    const jsonPath = path.join(onnxFolder, 'piper_test.onnx.json');
    fs.writeFileSync(onnxPath, Buffer.from('fake onnx binary'));
    fs.writeFileSync(jsonPath, JSON.stringify({ piper: true }));

    const res = voices.install([onnxPath, jsonPath]);
    assert.equal(res.ok, true);
    assert.equal(res.voice.type, 'piper');
    assert.equal(res.voice.name, 'piper test');
    assert.ok(fs.existsSync(res.voice.model));
    assert.ok(fs.existsSync(res.voice.config));
  });

  test('same file installed twice -> single voice returned', () => {
    const pth = path.join(tmpStaging, 'singer_voice.pth');
    const index = path.join(tmpStaging, 'singer_voice.index');

    const beforeCount = voices.list().length;
    const res = voices.install([pth, index]);
    assert.equal(res.ok, true);

    const afterCount = voices.list().length;
    assert.equal(afterCount, beforeCount);
  });

  test('setPitch updates pitch and target_hz', () => {
    const list = voices.list();
    const first = list[0];
    assert.ok(first);

    const updateRes = voices.setPitch(first.id, 4, 180);
    assert.equal(updateRes.ok, true);
    assert.equal(updateRes.voice.pitch, 4);
    assert.equal(updateRes.voice.target_hz, 180);

    const meta = voices.get(first.id);
    assert.equal(meta.pitch, 4);
    assert.equal(meta.target_hz, 180);

    voices.setPitch(first.id, null);
    const meta2 = voices.get(first.id);
    assert.equal(meta2.pitch, null);
  });

  test('remove voice removes files and meta', () => {
    const list = voices.list();
    const target = list[0];
    assert.ok(target);

    const remRes = voices.remove(target.id);
    assert.equal(remRes.ok, true);
    assert.equal(voices.get(target.id), null);

    const updatedList = voices.list();
    assert.equal(updatedList.some(v => v.id === target.id), false);
  });

  test('rvcRuntime: found with fake Applio directory, null if files missing', () => {
    const fakeApplio = path.join(tmpStaging, 'fake-applio');
    const isWin = process.platform === 'win32';
    const pyRel = isWin ? '.venv/Scripts/python.exe' : '.venv/bin/python';
    const pyPath = path.join(fakeApplio, pyRel);
    fs.mkdirSync(path.dirname(pyPath), { recursive: true });
    fs.writeFileSync(pyPath, '');

    const inferPy = path.join(fakeApplio, 'rvc/infer/infer.py');
    fs.mkdirSync(path.dirname(inferPy), { recursive: true });
    fs.writeFileSync(inferPy, '');

    const rmvpePt = path.join(fakeApplio, 'rvc/models/predictors/rmvpe.pt');
    fs.mkdirSync(path.dirname(rmvpePt), { recursive: true });
    fs.writeFileSync(rmvpePt, '');

    const contentvecBin = path.join(fakeApplio, 'rvc/models/embedders/contentvec/pytorch_model.bin');
    fs.mkdirSync(path.dirname(contentvecBin), { recursive: true });
    fs.writeFileSync(contentvecBin, '');

    const rt = voices.rvcRuntime({ rvcApplio: fakeApplio });
    assert.ok(rt);
    assert.equal(rt.applio, fakeApplio);
    assert.equal(rt.python, pyPath);

    fs.unlinkSync(rmvpePt);
    const rtMissing = voices.rvcRuntime({ rvcApplio: fakeApplio });
    assert.equal(rtMissing, null);
  });

  test('rvcStatus reports correct status shape', () => {
    const st = voices.rvcStatus({});
    assert.equal(typeof st.ready, 'boolean');
    assert.equal(typeof st.installing, 'boolean');
    assert.equal(typeof st.progress, 'number');
    assert.equal(typeof st.text, 'string');
  });
});
