// Test bout à bout du mode studio : un vrai serveur video-studio sur un projet temporaire, puis les tests Swift.
// Usage : node scripts/e2e-studio.mjs [chemin de video-studio]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

const studio = path.resolve(process.argv[2] || path.join(os.homedir(), 'dev/perso/video-studio'));
const { makeProject, makeShort } = await import(path.join(studio, 'test/helpers.mjs'));
const words = ['salut', 'je', 'vous', 'montre', 'rust'].map((text, i) => ({ t0: i, t1: i + 0.9, text }));
const root = makeProject({ id: 'np-e2e' });
const dir = makeShort(root, 'videos/s1', { versions: [{ n: 1, label: 'v1', file: '/tmp/none.mp4', rendered: new Date().toISOString(), duration: 5, fps: 30, words, pieces: [] }] });
const takes = fs.mkdtempSync(path.join(os.tmpdir(), 'np-e2e-takes-'));
const movie = path.join(takes, 'source.mov');
execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=30', '-f', 'lavfi', '-i', 'sine=frequency=440', '-t', '1', '-c:v', 'h264', '-c:a', 'aac', '-y', movie]);

const child = spawn(process.execPath, [path.join(studio, 'server.mjs'), '0'], { env: { ...process.env, VIDEO_STUDIO_PROJECTS: root, VIDEO_STUDIO_TAKES_ROOT: takes } });
const base = await new Promise((ok, ko) => {
  let out = '';
  child.stdout.on('data', (b) => { out += b; const m = /http:\/\/127\.0\.0\.1:(\d+)/.exec(out); if (m) ok(`http://127.0.0.1:${m[1]}`); });
  child.on('exit', (c) => ko(new Error(`serveur sorti : ${c}`)));
});
const host = new URL(base).host;
let code = 1;
try {
  const it = await (await fetch(`${base}/api/short/s1/items`, { method: 'POST', headers: { host, 'content-type': 'application/json' }, body: JSON.stringify({ version: 1, type: 'cam', from: 1, to: 4.9, text: '' }) })).json();
  const env = { ...process.env, TEST_RUNNER_STUDIO_E2E_URL: base, TEST_RUNNER_STUDIO_E2E_SHORT: 's1', TEST_RUNNER_STUDIO_E2E_MOVIE: movie };
  const r = spawn('xcodebuild', ['-project', 'NotchPrompter.xcodeproj', '-scheme', 'NotchPrompter', '-derivedDataPath', 'build/dd', 'test', '-only-testing:NotchPrompterTests/EndToEndTests'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let log = ''; r.stdout.on('data', (b) => { log += b; }); r.stderr.on('data', (b) => { log += b; });
  const xc = await new Promise((ok) => r.on('exit', ok));
  console.log(log.split('\n').filter((l) => /✔|✘|error:|TEST (SUCCEEDED|FAILED)|skipped/.test(l)).join('\n'));
  // Ce que le studio a gardé : la prise du prompteur, ses essais, le fichier sur disque, l'événement dans la boîte.
  const d = JSON.parse(fs.readFileSync(path.join(dir, 'review/studio.json'), 'utf8'));
  const take = d.items.find((i) => i.id === it.id).takes[0];
  const inbox = fs.readFileSync(path.join(dir, 'review/inbox.jsonl'), 'utf8');
  const ok = xc === 0 && take?.source === 'notchprompter' && take.passages?.[0]?.t1 === 0.9 && take.duration > 0.9 && fs.statSync(take.file).size === fs.statSync(movie).size && inbox.includes('"kind":"take"');
  console.log(ok ? `OK : prise ${take.n}, ${take.duration} s, essais ${JSON.stringify(take.passages)}, ${take.file}` : `ÉCHEC : ${JSON.stringify(take)}`);
  code = ok ? 0 : 1;
} finally { child.kill(); }
process.exit(code);
