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
assert(html.includes('>v3.7.2<'), 'panel version is not v3.7.2');
assert(/ExtensionBundleVersion="3\.7\.2"/.test(manifest), 'bundle version is not 3.7.2');
assert(/Version="3\.7\.2"/.test(manifest), 'extension version is not 3.7.2');
console.log('PASS AI global shortcut removal');
