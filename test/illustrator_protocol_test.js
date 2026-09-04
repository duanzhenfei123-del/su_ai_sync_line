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

assert.strictEqual(context.VERSION, '3.7');

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
    duplicate: function () {
      return { createOutline: function () { return outline; } };
    }
  };
}

assert.strictEqual(context.itemZIndex({ zOrderPosition: 7 }, 3), 7);
assert.strictEqual(context.itemZIndex({}, 3), 3);

const grouped = context.gd(fakeGroupWithPath(7), 1);
assert.strictEqual(grouped.zIndex, 7);

const strokeGroups = [];
context.addPathAsGroup(square(7, true), [], strokeGroups, 1);
assert.strictEqual(strokeGroups[0].zIndex, 7);

context.COMPOUND_COUNTER = 0;
const compoundPaths = [];
context.aCP({ name: 'ring', pathItems: [square(1, false), square(1, false)] }, compoundPaths, 1);
assert.strictEqual(compoundPaths.length, 2);
assert.strictEqual(compoundPaths[0].compoundKey, 'compound_0000');
assert.strictEqual(compoundPaths[1].compoundKey, compoundPaths[0].compoundKey);

const outlined = context.otl(fakeTextWithCompoundOutline(), 1);
assert.strictEqual(outlined.length, 2);
assert.strictEqual(outlined[0].textGroupKey, outlined[0].textGroupId);
assert.strictEqual(outlined[1].textGroupKey, outlined[0].textGroupId);

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
memoryFiles.set('C:/out/latest_sync.json', 'known good');
renameFailures.add('C:/out/latest_sync.json.tmp->C:/out/latest_sync.json');
const failedExport = JSON.parse(context.exportSelectionAsJSON('C:/out'));
renameFailures.clear();
assert.strictEqual(failedExport.errors.length, 1);
assert.strictEqual(memoryFiles.get('C:/out/latest_sync.json'), 'known good');

console.log('PASS illustrator protocol');
