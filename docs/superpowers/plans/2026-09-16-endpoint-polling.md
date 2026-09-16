# 端点吸附与选区轮询优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仅优化 SU 端点吸附与 AI 面板选区轮询。

**Architecture:** SU 用容差网格筛选候选端点、并查集建立唯一连通簇。AI 面板以一个定时器和状态锁控制选区查询。

**Tech Stack:** Ruby、CEP JavaScript、Node `assert`、现有 Ruby 测试运行器。

## Global Constraints

- 本阶段仅修改端点吸附与面板选区轮询。
- 不引入依赖，不改变面板布局。
- 导出结果保持到下一次面板操作。
- 端点容差保持最终模型 0.05 mm。

---

### Task 1: 网格化端点吸附

**Files:**
- Modify: `source/su_ai_sync/importer.rb:209-241`
- Modify: `test/importer_protocol_test.rb`

**Interfaces:**
- Consumes: `snap_path_endpoints!(paths, scale) -> Integer`。
- Produces: 原地更新端点和 `isClosed`，返回修复端点数。

- [ ] **Step 1: 写失败测试**

```ruby
paths = [{ 'verticesMM' => [[0.049, 0], [10, 0]], 'isClosed' => false }, { 'verticesMM' => [[0.051, 0], [20, 0]], 'isClosed' => false }, { 'verticesMM' => [[0.099, 0], [30, 0]], 'isClosed' => false }]
assert_equal(2, importer.send(:snap_path_endpoints!, paths, 1.0), 'transitive endpoint cluster repaired')
```

覆盖跨网格边界、同一路径首尾闭合、超过容差不变。

- [ ] **Step 2: 确认失败**

Run: `ruby test/importer_protocol_test.rb`

Expected: 新增传递连通或跨网格断言失败。

- [ ] **Step 3: 最小实现**

```ruby
buckets = Hash.new { |hash, key| hash[key] = [] }
endpoints.each_with_index { |entry, index| buckets[[entry[2].div(tolerance).floor, entry[3].div(tolerance).floor]] << index }
```

比较当前格和八个相邻格，距离满足容差时合并并查集根节点；按根聚合、平均坐标一次写回；同一路径首尾根相同才闭合。

- [ ] **Step 4: 确认通过并提交**

Run: `ruby test/importer_protocol_test.rb`

Expected: PASS。

Commit: `git add test/importer_protocol_test.rb source/su_ai_sync/importer.rb && git commit -m "perf: bucket endpoint snapping"`

### Task 2: 面板选区轮询控制

**Files:**
- Modify: `illustrator/su-ai-png-export/client/js/main.js:68-292`
- Create: `test/ai_selection_polling_test.js`

**Interfaces:**
- Consumes: `csInterface.evalScript('getSelectionInfo()', callback)`、`visibilitychange`、`beforeunload`。
- Produces: `startSelectionPolling()`, `stopSelectionPolling()`, `unlockSelectionStatus()`。

- [ ] **Step 1: 写失败测试**

```javascript
assert(js.includes('function startSelectionPolling()'), 'polling start helper missing');
assert(js.includes('selectionStatusLocked = true'), 'export result lock missing');
```

断言旧裸 `setInterval(function ()` 不存在，导出成功路径不调用 `updateSelectionInfo()`，卸载时停止轮询。

- [ ] **Step 2: 确认失败**

Run: `node test/ai_selection_polling_test.js`

Expected: FAIL，提示 polling helper missing。

- [ ] **Step 3: 最小实现**

```javascript
var selectionPollTimer = null;
var selectionStatusLocked = false;
function stopSelectionPolling() { if (selectionPollTimer !== null) clearInterval(selectionPollTimer); selectionPollTimer = null; }
```

导出开始停止轮询，回调结束锁定结果；下一次按钮操作解锁并启动轮询。隐藏停止，显示时仅未锁定且未导出才恢复，卸载清理定时器。

- [ ] **Step 4: 确认通过并提交**

Run: `node test/ai_selection_polling_test.js; node test/ai_global_shortcut_removal_test.js; node --check illustrator/su-ai-png-export/client/js/main.js`

Expected: 全部 PASS。

Commit: `git add illustrator/su-ai-png-export/client/js/main.js test/ai_selection_polling_test.js && git commit -m "perf: pause panel selection polling"`

### Task 3: 固化本轮开发范围

**Files:**
- Create: `docs/插件开发规范.md`

**Interfaces:**
- Consumes: 已确认设计规范。
- Produces: 本轮可审查范围约束。

- [ ] **Step 1: 写入范围条款**

```markdown
## 当前优化范围：端点吸附与选区轮询
本轮仅允许修改 SketchUp 端点自动吸附，以及 Illustrator 面板选区轮询和导出状态保持。
```

列出 PNG 清理、临时文档恢复、JSON 写入、导入结果反馈、材质刷新和白色材质处理为不在本轮范围。

- [ ] **Step 2: 自检并提交**

Run: `rg -n "当前优化范围|不在本轮范围" docs/插件开发规范.md; git diff --check`

Expected: 范围条款存在，格式检查通过。

Commit: `git add docs/插件开发规范.md && git commit -m "docs: constrain current optimization scope"`

### Task 4: 完整回归

**Files:**
- Verify: `test/run_all.rb`
- Verify: `test/illustrator_protocol_test.js`
- Verify: `test/ai_global_shortcut_removal_test.js`
- Verify: `test/ai_selection_polling_test.js`

**Interfaces:**
- Consumes: Tasks 1–3 的实现。
- Produces: 可报告的验证结果。

- [ ] **Step 1: 运行测试**

Run: `ruby test/run_all.rb; node test/illustrator_protocol_test.js; node test/ai_global_shortcut_removal_test.js; node test/ai_selection_polling_test.js`

Expected: 可用套件全部 PASS；若本机没有 SketchUp Ruby API，记录限制。

- [ ] **Step 2: 检查工作树**

Run: `git status --short; git log --oneline -4`

Expected: 本轮源码和规范均已提交，用户原有未跟踪文件不被纳入提交。
