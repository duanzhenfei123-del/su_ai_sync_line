# PluginItem 临时展开导出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 Illustrator 原稿的前提下，导出图像描摹型 `PluginItem` 的展开路径。

**Architecture:** 仅在选区循环中识别 `PluginItem.isTracing === true`。脚本复制该对象、在副本上调用 `tracing.expandTracing(false)`、复用现有 `gd` 序列化得到的 `GroupItem`，最后删除临时对象；非描摹插件对象继续明确跳过。前端复用已有详情日志，仅标明成功对象经过临时展开。

**Tech Stack:** Illustrator ExtendScript、CEP JavaScript、Node `assert`/`vm` 测试。

## Global Constraints

- 不修改原始 `PluginItem`，不调用原对象的 `remove`、`expandTracing` 或菜单展开命令。
- 不修改 `latest_sync.json` schema，不新增依赖、文件、面板控件或配置项。
- 仅支持 `isTracing === true`，其他插件对象必须可见地跳过。
- 临时展开组/副本须在所有结果路径中清理；清理失败必须在诊断中显示。

---

### Task 1: 在副本上导出图像描摹 PluginItem

**Files:**
- Modify: `illustrator/su-ai-png-export/host/main.jsx:449-477`
- Modify: `illustrator/su-ai-png-export/client/js/main.js:181-191`
- Test: `test/illustrator_protocol_test.js`

**Interfaces:**
- Consumes: `PluginItem#isTracing`, `PluginItem#duplicate()`, `TracingObject#expandTracing(false)`, existing `gd(item, scale)`.
- Produces: `exportSelectionAsJSON()` result diagnostics with `isTracing` and `temporaryExpansion`; existing JSON `groups` contains the paths read from the temporary group.

- [x] **Step 1: Write failing tracing-plugin test**

    const sourcePlugin = { typename: 'PluginItem', isTracing: true, duplicate: function () { return tempPlugin; } };
    context.app.activeDocument.selection = [sourcePlugin];
    const result = JSON.parse(context.exportSelectionAsJSON('C:/out'));
    assert.strictEqual(result.count, 1);
    assert.strictEqual(sourceRemoved, false);
    assert.strictEqual(expandedRemoved, true);
    assert.strictEqual(JSON.parse(memoryFiles.get('C:/out/latest_sync.json')).groups.length, 1);

- [x] **Step 2: Run the test to verify it fails**

Run: `node test\\illustrator_protocol_test.js`  
Expected: FAIL because `PluginItem` is still reported as skipped and `count` is `0`.

- [x] **Step 3: Add the minimal host branch**

    else if (t === "PluginItem" && item.isTracing === true) {
        var temporary = null, expanded = null;
        try {
            temporary = item.duplicate(); app.redraw();
            expanded = temporary.tracing.expandTracing(false);
            groups.push(gd(expanded, s));
            diagnostic.isTracing = true; diagnostic.temporaryExpansion = true;
        } catch (pluginError) {
            diagnostic.status = "skipped";
            diagnostic.reason = "图像描摹临时展开失败: " + pluginError.message;
            result.errors.push("第 " + diagnostic.index + " 项（PluginItem）已跳过：" + diagnostic.reason);
        } finally {
            var cleanupItem = expanded || temporary;
            if (cleanupItem) try { cleanupItem.remove(); } catch (cleanupError) {
                diagnostic.status = "skipped";
                diagnostic.reason = "临时展开对象清理失败: " + cleanupError.message;
                result.errors.push("第 " + diagnostic.index + " 项（PluginItem）已跳过：" + diagnostic.reason);
            }
        }
    }

Keep the existing generic unsupported branch for all other types. Add a dedicated non-tracing `PluginItem` skip reason. In the CEP formatter, replace the normal success suffix with `，临时展开后已导出` when `temporaryExpansion` is true.

- [x] **Step 4: Run tests to verify the behavior**

Run: `node test\\illustrator_protocol_test.js`  
Expected: PASS; the tracing plugin yields one serialized group, the original is untouched, and temporary artwork is deleted.

- [x] **Step 5: Add negative tests and run them**

    let nonTracingDuplicated = false;
    context.app.activeDocument.selection = [{ typename: 'PluginItem', isTracing: false,
      duplicate: function () { nonTracingDuplicated = true; } }];
    const nonTracing = JSON.parse(context.exportSelectionAsJSON('C:/out'));
    assert.strictEqual(nonTracing.count, 0);
    assert.strictEqual(nonTracingDuplicated, false);
    assert.strictEqual(nonTracing.diagnostics[0].reason, '非图像描摹插件对象，无法无损读取路径');

    let failedTempRemoved = false;
    context.app.activeDocument.selection = [{ typename: 'PluginItem', isTracing: true,
      duplicate: function () { return { tracing: { expandTracing: function () { throw new Error('expand failed'); } },
        remove: function () { failedTempRemoved = true; } }; } }];
    const failedTrace = JSON.parse(context.exportSelectionAsJSON('C:/out'));
    assert.strictEqual(failedTrace.count, 0);
    assert.strictEqual(failedTempRemoved, true);
    assert.ok(failedTrace.errors[0].indexOf('图像描摹临时展开失败') >= 0);

Run: `node test\\illustrator_protocol_test.js`  
Expected: PASS.

- [x] **Step 6: Run AI regressions and commit**

Run: `node test\\illustrator_protocol_test.js; node test\\ai_global_shortcut_removal_test.js; node --check illustrator\\su-ai-png-export\\client\\js\\main.js; git diff --check`  
Expected: all commands exit `0`.

    git add illustrator/su-ai-png-export/host/main.jsx illustrator/su-ai-png-export/client/js/main.js test/illustrator_protocol_test.js
    git commit -m "fix: export traced plugin items from temporary copy"
