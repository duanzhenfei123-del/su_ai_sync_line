const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const memoryFiles = new Map();
const renameFailures = new Set();

function normalize(filePath) {
  return String(filePath).replace(/\\/g, '/').replace(/\/$/, '');
}

function Folder(folderPath) {
  this.fsName = normalize(folderPath);
  this.exists = true;
}
Folder.desktop = { fsName: 'C:/Desktop' };
Folder.userData = { fsName: 'C:/UserData' };
Folder.selectDialog = function () { return null; };
Folder.prototype.create = function () { this.exists = true; return true; };
Folder.prototype.getFiles = function () {
  const prefix = this.fsName + '/';
  return Array.from(memoryFiles.keys())
    .filter(function (filePath) {
      return filePath.indexOf(prefix) === 0 && filePath.slice(prefix.length).indexOf('/') === -1;
    })
    .map(function (filePath) { return new File(filePath); });
};

function File(filePath) {
  this.fsName = normalize(filePath);
  this.name = this.fsName.split('/').pop();
  this.exists = memoryFiles.has(this.fsName);
  this.buffer = '';
}
File.prototype.open = function (mode) {
  this.buffer = mode === 'a' ? (memoryFiles.get(this.fsName) || '') : '';
  return true;
};
File.prototype.write = function (value) { this.buffer += String(value); };
File.prototype.writeln = function (value) { this.buffer += String(value) + '\n'; };
File.prototype.read = function () { return memoryFiles.get(this.fsName) || ''; };
File.prototype.close = function () {
  memoryFiles.set(this.fsName, this.buffer);
  this.exists = true;
};
File.prototype.remove = function () {
  const removed = memoryFiles.delete(this.fsName);
  this.exists = false;
  return removed;
};
File.prototype.rename = function (name) {
  const slash = this.fsName.lastIndexOf('/');
  const target = this.fsName.slice(0, slash + 1) + name;
  if (renameFailures.has(this.fsName + '->' + target)) return false;
  const content = memoryFiles.has(this.fsName) ? memoryFiles.get(this.fsName) : this.buffer;
  memoryFiles.delete(this.fsName);
  memoryFiles.set(target, content);
  this.fsName = target;
  this.name = name;
  this.exists = true;
  return true;
};

const context = {
  console,
  Date,
  File,
  Folder,
  Math,
  Number,
  String,
  Window: function () {},
  app: {},
  $: { global: {} }
};
vm.createContext(context);

const jsxPath = path.join(__dirname, '..', 'illustrator', 'su-ai-png-export', 'host', 'main.jsx');
vm.runInContext(fs.readFileSync(jsxPath, 'utf8'), context, { filename: jsxPath });

assert.strictEqual(context.VERSION, '3.7.2');
[
  'shortcutDataFolder', 'configureGlobalShortcuts',
  'ensureGlobalShortcutHost', 'touchGlobalShortcutHeartbeat',
  'consumeGlobalShortcutCommand', 'disableGlobalShortcuts'
].forEach(function (name) {
  assert.strictEqual(typeof context[name], 'undefined', name + ' should be removed');
});

function point(x, y) {
  return {
    anchor: [x, y],
    leftDirection: [x, y],
    rightDirection: [x, y]
  };
}

function square(zOrderPosition, stroked) {
  return {
    typename: 'PathItem',
    name: 'square',
    pathPoints: [point(0, 0), point(10, 0), point(10, 10), point(0, 10)],
    closed: true,
    filled: true,
    fillColor: { typename: 'RGBColor', red: 255, green: 0, blue: 0 },
    stroked: Boolean(stroked),
    strokeWidth: 2,
    strokeColor: { typename: 'RGBColor', red: 0, green: 0, blue: 0 },
    geometricBounds: [0, 10, 10, 0],
    visibleBounds: [-1, 11, 11, -1],
    zOrderPosition
  };
}

function fakeGroupWithPath(zOrderPosition) {
  return {
    typename: 'GroupItem',
    name: 'group',
    clipped: false,
    pageItems: [square(2, false)],
    zOrderPosition
  };
}

function fakeTextWithCompoundOutline() {
  const outline = {
    typename: 'GroupItem',
    pageItems: [{
      typename: 'CompoundPathItem',
      name: 'outlined glyph',
      pathItems: [square(1, false), square(1, false)]
    }],
    remove: function () {}
  };
  return {
    zOrderPosition: 9,
    duplicate: function () {
      return { createOutline: function () { return outline; } };
    }
  };
}

assert.strictEqual(context.itemZIndex({ zOrderPosition: 7 }, 3), 7);
assert.strictEqual(context.itemZIndex({}, 3), 3);
const lowerItem = { zOrderPosition: 7 };
const upperItem = { zOrderPosition: 7 };
const mixedParent = { pageItems: [upperItem, lowerItem] };
lowerItem.parent = mixedParent;
upperItem.parent = mixedParent;
assert.strictEqual(context.itemZIndex(upperItem, 0), 2);
assert.strictEqual(context.itemZIndex(lowerItem, 0), 1);

const grouped = context.gd(fakeGroupWithPath(7), 1);
assert.strictEqual(grouped.zIndex, 7);

const strokeGroups = [];
context.addPathAsGroup(square(7, true), [], strokeGroups, 1);
assert.strictEqual(strokeGroups[0].zIndex, 7);

context.COMPOUND_COUNTER = 0;
const compoundPaths = [];
context.aCP({ name: 'ring', zOrderPosition: 8, pathItems: [square(1, false), square(1, false)] }, compoundPaths, 1);
assert.strictEqual(compoundPaths.length, 2);
assert.strictEqual(compoundPaths[0].compoundKey, 'compound_0000');
assert.strictEqual(compoundPaths[1].compoundKey, compoundPaths[0].compoundKey);
assert.strictEqual(compoundPaths[0].zIndex, 8);
assert.strictEqual(compoundPaths[1].zIndex, 8);

const outlined = context.otl(fakeTextWithCompoundOutline(), 1);
assert.strictEqual(outlined.length, 2);
assert.strictEqual(outlined[0].textGroupKey, outlined[0].textGroupId);
assert.strictEqual(outlined[1].textGroupKey, outlined[0].textGroupId);
assert.strictEqual(outlined[0].zIndex, 9);
assert.strictEqual(outlined[1].zIndex, 9);

assert.strictEqual(context.ownedSyncFile('sync_2026-01-01.json'), true);
assert.strictEqual(context.ownedSyncFile('latest_sync.json.tmp'), true);
assert.strictEqual(context.ownedSyncFile('customer.json'), false);
assert.strictEqual(context.ownedSyncFile('photo.png'), false);
assert.strictEqual(context.esc('a\rb\tc\u0001'), 'a\\rb\\tc\\u0001');

memoryFiles.clear();
memoryFiles.set('C:/out/sync_old.json', 'old sync');
memoryFiles.set('C:/out/customer.json', 'customer data');
memoryFiles.set('C:/out/photo.png', 'png data');
context.app.activeDocument = {
  name: 'contract.ai',
  width: 100,
  height: 100,
  selection: [square(5, false)]
};

const exportResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(exportResult.jsonFile, 'latest_sync.json');
assert.strictEqual(memoryFiles.has('C:/out/latest_sync.json'), true);
const exported = JSON.parse(memoryFiles.get('C:/out/latest_sync.json'));
assert.strictEqual(exported.schemaVersion, 2);
assert.strictEqual(memoryFiles.has('C:/out/sync_old.json'), false);
assert.strictEqual(memoryFiles.has('C:/out/customer.json'), true);
assert.strictEqual(memoryFiles.has('C:/out/photo.png'), true);
assert.deepStrictEqual(Array.from(memoryFiles.keys()).filter(function (name) {
  return /\.log$/i.test(name);
}), []);

memoryFiles.clear();
context.app.activeDocument = {
  name: 'unsupported.ai',
  width: 100,
  height: 100,
  selection: [{ typename: 'LivePaintGroup', name: 'live paint' }]
};
const unsupportedResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.deepStrictEqual(unsupportedResult.diagnostics || [], [{
  index: 1,
  type: 'LivePaintGroup',
  name: 'live paint',
  status: 'skipped',
  reason: '不支持的对象类型'
}]);
assert.deepStrictEqual(unsupportedResult.errors, ['第 1 项（LivePaintGroup）已跳过：不支持的对象类型']);

memoryFiles.clear();
context.app.activeDocument = {
  name: 'compound.ai',
  width: 100,
  height: 100,
  selection: [{
    typename: 'CompoundPathItem',
    name: 'ring',
    pathItems: [square(1, false), square(1, false)]
  }]
};
const compoundResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.deepStrictEqual(compoundResult.diagnostics || [], [{
  index: 1,
  type: 'CompoundPathItem',
  name: 'ring',
  status: 'exported',
  pathCount: 2
}]);
assert.deepStrictEqual(compoundResult.errors, []);

memoryFiles.clear();
context.app.activeDocument = {
  name: 'empty-compound.ai',
  width: 100,
  height: 100,
  selection: [{ typename: 'CompoundPathItem', name: 'empty ring', pathItems: [] }]
};
const emptyCompoundResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.deepStrictEqual(emptyCompoundResult.diagnostics || [], [{
  index: 1,
  type: 'CompoundPathItem',
  name: 'empty ring',
  status: 'skipped',
  pathCount: 0,
  reason: '复合路径不包含可导出的子路径'
}]);
assert.deepStrictEqual(emptyCompoundResult.errors, ['第 1 项（CompoundPathItem）已跳过：复合路径不包含可导出的子路径']);

memoryFiles.clear();
let sourcePluginRemoved = false;
let expandedPluginRemoved = false;
let expandCommandCalls = 0;
const expandedPluginGroup = fakeGroupWithPath(6);
expandedPluginGroup.remove = function () { expandedPluginRemoved = true; };
const temporaryPlugin = { typename: 'PluginItem', remove: function () { throw new Error('expanded plugin should replace the temporary plugin'); } };
const sourcePlugin = {
  typename: 'PluginItem',
  name: 'third-party effect',
  duplicate: function () { return temporaryPlugin; },
  remove: function () { sourcePluginRemoved = true; }
};
context.app.activeDocument = {
  name: 'expand-plugin.ai',
  width: 100,
  height: 100,
  selection: [sourcePlugin]
};
context.app.executeMenuCommand = function (command) {
  assert.strictEqual(command, 'expandStyle');
  expandCommandCalls++;
  context.app.activeDocument.selection = [expandedPluginGroup];
};
const expandedPluginResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(expandedPluginResult.count, 1);
assert.deepStrictEqual(expandedPluginResult.errors, []);
assert.deepStrictEqual(expandedPluginResult.diagnostics || [], [{
  index: 1,
  type: 'PluginItem',
  name: 'third-party effect',
  status: 'exported',
  temporaryExpansion: true,
  expansionCommand: 'expandStyle'
}]);
assert.strictEqual(expandCommandCalls, 1);
assert.strictEqual(sourcePluginRemoved, false);
assert.strictEqual(expandedPluginRemoved, true);
assert.strictEqual(context.app.activeDocument.selection[0], sourcePlugin);
assert.strictEqual(JSON.parse(memoryFiles.get('C:/out/latest_sync.json')).groups.length, 1);

memoryFiles.clear();
let unchangedTemporaryRemoved = false;
const unchangedPlugin = {
  typename: 'PluginItem',
  name: 'unexpandable effect',
  duplicate: function () { return { typename: 'PluginItem', remove: function () { unchangedTemporaryRemoved = true; } }; }
};
context.app.activeDocument = {
  name: 'unexpandable-plugin.ai',
  width: 100,
  height: 100,
  selection: [unchangedPlugin]
};
context.app.executeMenuCommand = function (command) { assert.strictEqual(command, 'expandStyle'); };
const unchangedPluginResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(unchangedPluginResult.count, 0);
assert.strictEqual(unchangedTemporaryRemoved, true);
assert.deepStrictEqual(unchangedPluginResult.diagnostics || [], [{
  index: 1,
  type: 'PluginItem',
  name: 'unexpandable effect',
  status: 'skipped',
  reason: '自动扩展未生成可导出路径',
  expansionCommand: 'expandStyle'
}]);
assert.deepStrictEqual(unchangedPluginResult.errors, ['第 1 项（PluginItem）已跳过：自动扩展未生成可导出路径']);
assert.strictEqual(context.app.activeDocument.selection[0], unchangedPlugin);

memoryFiles.clear();
let emptySelectionTemporaryRemoved = false;
const emptySelectionPlugin = {
  typename: 'PluginItem',
  name: 'empty expansion',
  duplicate: function () { return { typename: 'PluginItem', remove: function () { emptySelectionTemporaryRemoved = true; } }; }
};
context.app.activeDocument = {
  name: 'empty-expansion.ai',
  width: 100,
  height: 100,
  selection: [emptySelectionPlugin]
};
context.app.executeMenuCommand = function (command) {
  assert.strictEqual(command, 'expandStyle');
  context.app.activeDocument.selection = [];
};
const emptySelectionResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(emptySelectionResult.count, 0);
assert.strictEqual(emptySelectionTemporaryRemoved, true);
assert.deepStrictEqual(emptySelectionResult.errors, ['第 1 项（PluginItem）已跳过：自动扩展未生成可导出路径']);
assert.strictEqual(context.app.activeDocument.selection[0], emptySelectionPlugin);

memoryFiles.clear();
let failedTemporaryRemoved = false;
const failedPlugin = {
  typename: 'PluginItem',
  name: 'broken effect',
  duplicate: function () { return { typename: 'PluginItem', remove: function () { failedTemporaryRemoved = true; } }; }
};
context.app.activeDocument = {
  name: 'failed-plugin.ai',
  width: 100,
  height: 100,
  selection: [failedPlugin]
};
context.app.executeMenuCommand = function () { throw new Error('expand command failed'); };
const failedPluginResult = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(failedPluginResult.count, 0);
assert.strictEqual(failedTemporaryRemoved, true);
assert.deepStrictEqual(failedPluginResult.diagnostics || [], [{
  index: 1,
  type: 'PluginItem',
  name: 'broken effect',
  status: 'skipped',
  reason: '自动扩展失败: expand command failed',
  expansionCommand: 'expandStyle'
}]);
assert.deepStrictEqual(failedPluginResult.errors, ['第 1 项（PluginItem）已跳过：自动扩展失败: expand command failed']);
assert.strictEqual(context.app.activeDocument.selection[0], failedPlugin);

let movingZ = 2;
const movingPath = square(2, false);
Object.defineProperty(movingPath, 'zOrderPosition', { get: function () { return movingZ; } });
const shiftingText = fakeTextWithCompoundOutline();
shiftingText.typename = 'TextFrame';
const originalDuplicate = shiftingText.duplicate;
shiftingText.duplicate = function () { movingZ = 3; return originalDuplicate(); };
context.app.activeDocument = {
  name: 'stack.ai',
  width: 100,
  height: 100,
  selection: [shiftingText, movingPath]
};
const stackedExport = JSON.parse(context.exportSelectionAsJSON('C:/out'));
assert.strictEqual(stackedExport.errors.length, 0);
const stackedJson = JSON.parse(memoryFiles.get('C:/out/latest_sync.json'));
assert.strictEqual(stackedJson.paths.filter(function (item) { return item.name === 'square'; })[0].zIndex, 2);

memoryFiles.clear();
memoryFiles.set('C:/out/latest_sync.json', 'known good');
renameFailures.add('C:/out/latest_sync.json.tmp->C:/out/latest_sync.json');
const failedExport = JSON.parse(context.exportSelectionAsJSON('C:/out'));
renameFailures.clear();
assert.strictEqual(failedExport.errors.length, 1);
assert.strictEqual(memoryFiles.get('C:/out/latest_sync.json'), 'known good');

console.log('PASS illustrator protocol');
