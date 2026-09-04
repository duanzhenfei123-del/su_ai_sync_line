const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

function Folder(folderPath) {
  this.fsName = folderPath;
  this.exists = true;
}
Folder.desktop = { fsName: 'C:/Desktop' };
Folder.userData = { fsName: 'C:/UserData' };
Folder.selectDialog = function () { return null; };

function File(filePath) {
  this.fsName = filePath;
  this.name = String(filePath).split(/[\\/]/).pop();
  this.exists = false;
}

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

console.log('PASS illustrator protocol');
