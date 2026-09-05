# PluginItem 自动扩展副本 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自动在临时 `PluginItem` 副本上执行 Illustrator“扩展外观”，并导出生成的路径。

**Architecture:** 导出前拍摄选区快照。每个 `PluginItem` 复制后成为唯一选区，执行 `expandStyle`，仅导出命令生成的组、路径和复合路径；清理临时选区后恢复用户原选区。只使用这一条无对话框命令。

**Tech Stack:** Illustrator ExtendScript、CEP JavaScript、Node `assert`/`vm`。

## Global Constraints

- 原对象不调用 `remove` 或 `executeMenuCommand`。
- 不修改 `latest_sync.json` schema、面板、依赖或配置。
- 命令未产生可导出路径即清理副本并报告错误；不尝试其他插件命令。

---

### Task 1: 自动扩展并导出临时 PluginItem 副本

**Files:**
- Modify: `illustrator/su-ai-png-export/host/main.jsx:443-505`
- Test: `test/illustrator_protocol_test.js`

**Interfaces:**
- Consumes: `PluginItem#duplicate()`, `Application#executeMenuCommand("expandStyle")`, `Document#selection`, `gd`, `aCP`, `addPathAsGroup`.
- Produces: temporary-expansion diagnostics and the existing path/group JSON output.

- [x] **Step 1: Write failing tests for command output, no-output, and command error**

    const expanded = fakeGroupWithPath(1);
    let sourceRemoved = false, expandedRemoved = false;
    expanded.remove = function () { expandedRemoved = true; };
    const sourcePlugin = { typename: 'PluginItem', duplicate: function () { return { typename: 'PluginItem' }; },
      remove: function () { sourceRemoved = true; } };
    context.app.executeMenuCommand = function (command) {
      assert.strictEqual(command, 'expandStyle');
      context.app.activeDocument.selection = [expanded];
    };
    context.app.activeDocument.selection = [sourcePlugin];
    const result = JSON.parse(context.exportSelectionAsJSON('C:/out'));
    assert.strictEqual(result.count, 1);
    assert.strictEqual(sourceRemoved, false);
    assert.strictEqual(expandedRemoved, true);

Also assert that a command leaving `PluginItem` selected returns count `0` and `自动扩展未生成可导出路径`; a thrown command must clean the duplicate and report `自动扩展失败`.

- [x] **Step 2: Run the test to verify it fails**

Run: `node test\\illustrator_protocol_test.js`  
Expected: FAIL because non-tracing `PluginItem` still follows the prior skip branch.

- [x] **Step 3: Replace the tracing-only branch with the one-command temporary expansion branch**

    var originalSelection = [];
    for (var si = 0; si < doc.selection.length; si++) originalSelection.push(doc.selection[si]);
    // For PluginItem: duplicate, set doc.selection to the duplicate,
    // app.executeMenuCommand("expandStyle"), serialize GroupItem/PathItem/CompoundPathItem,
    // delete temporary output, then restore doc.selection = originalSelection.

Add `// ponytail: expandStyle only; add a plugin-specific command only after a real object requires it.` next to the command. Do not call `expand`, because it can require a dialog.

- [x] **Step 4: Run automated verification**

Run: `node test\\illustrator_protocol_test.js; node test\\ai_global_shortcut_removal_test.js; node --check illustrator\\su-ai-png-export\\client\\js\\main.js; git diff --check`  
Expected: all commands exit `0`.

- [x] **Step 5: Deploy and commit**

    git add illustrator/su-ai-png-export/host/main.jsx test/illustrator_protocol_test.js docs/superpowers/specs/2026-09-05-pluginitem-temporary-expand-design.md docs/superpowers/plans/2026-09-05-pluginitem-temporary-expand.md
    git commit -m "fix: expand PluginItem copies before export"

Copy only the changed host file to the installed CEP extension after making a dated backup, then compare SHA256 hashes.
