const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'illustrator', 'su-ai-png-export');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const html = read('client/index.html');
const css = read('client/css/style.css');
const js = read('client/js/main.js');
const jsx = read('host/main.jsx');
const manifest = read('CSXS/manifest.xml');

[
  'jsonShortcut', 'pngShortcut', 'setJsonShortcutBtn',
  'setPngShortcutBtn', 'clearJsonShortcutBtn', 'clearPngShortcutBtn'
].forEach(token => assert(!html.includes(token), 'HTML retained ' + token));
assert(!css.includes('.shortcut-'), 'shortcut CSS remains');
[
  'recordingShortcut', 'shortcutHostPath', 'syncGlobalShortcuts',
  'maintainGlobalShortcutHost', 'pollGlobalShortcutCommand',
  'suai.shortcut.', 'window.addEventListener("keydown"'
].forEach(token => assert(!js.includes(token), 'front end retained ' + token));
[
  'shortcutDataFolder', 'writeShortcutFile', 'ensureGlobalShortcutHost',
  'configureGlobalShortcuts', 'touchGlobalShortcutHeartbeat',
  'consumeGlobalShortcutCommand', 'disableGlobalShortcuts'
].forEach(token => assert(!jsx.includes(token), 'ExtendScript retained ' + token));
assert(!fs.existsSync(path.join(root, 'bin', 'SUAIShortcutHost.exe')), 'helper executable remains');
assert(html.includes('id="exportJsonBtn"') && html.includes('id="exportBtn"'), 'export buttons changed');
assert(html.includes('DTT 轮廓与图片导出 · 段土土'), 'panel title lacks DTT branding');
assert(html.includes('>打赏</button>'), 'panel lacks donation button');
assert(html.includes('src="assets/wechat_pay.png"'), 'panel lacks local donation image');
assert(fs.existsSync(path.join(root, 'client', 'assets', 'wechat_pay.png')), 'donation image is missing');
const version = jsx.match(/^var VERSION = "(\d+\.\d+\.\d+)";/);
assert(version, 'host version must use three components');
assert(manifest.includes(`ExtensionBundleVersion="${version[1]}"`), 'bundle and host versions differ');
assert(manifest.includes(`Id="com.suai.pngexport.panel" Version="${version[1]}"`), 'extension and host versions differ');
console.log('PASS AI global shortcut removal');
