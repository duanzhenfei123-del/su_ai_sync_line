const assert = require('assert');
const fs = require('fs');
const path = require('path');

const panel = fs.readFileSync(
  path.join(__dirname, '..', 'illustrator', 'su-ai-png-export', 'client', 'js', 'main.js'),
  'utf8'
);

[
  'function startSelectionPolling()',
  'function stopSelectionPolling()',
  'function unlockSelectionStatus()',
  'document.addEventListener("visibilitychange"',
  'selectionStatusLocked = true',
  'stopSelectionPolling();'
].forEach(token => assert(panel.includes(token), 'missing polling control: ' + token));

assert(!panel.includes('setInterval(function ()'), 'legacy bare polling timer remains');
assert(!/setStatus\("✅ 导出完成[\s\S]{0,300}updateSelectionInfo\(\)/.test(panel), 'PNG export overwrites its result');
assert(!/setStatus\("✅ JSON 导出完成[\s\S]{0,300}updateSelectionInfo\(\)/.test(panel), 'JSON export overwrites its result');
assert(/beforeunload[\s\S]{0,300}stopSelectionPolling\(\)/.test(panel), 'panel unload does not stop polling');

console.log('PASS AI selection polling');
