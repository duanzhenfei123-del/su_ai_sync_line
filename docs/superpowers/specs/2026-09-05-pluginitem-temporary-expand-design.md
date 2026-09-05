# PluginItem 临时展开导出设计

日期：2026-09-05  
状态：已获用户确认

## 目标

AI 端导出轮廓时，支持 Illustrator 图像描摹生成的 `PluginItem`，同时绝不展开、转换、删除或重排原稿中的对象。

## 范围

- 仅处理 `item.typename === "PluginItem"` 且 `item.isTracing === true` 的选中对象。
- 在副本的 `tracing` 对象上调用 `expandTracing(false)`，取得只含描摹路径的 `GroupItem`。
- 使用现有 `gd` 路径遍历逻辑序列化临时组；随后删除临时组/副本。
- 其他 `PluginItem` 保持跳过，明确标注“非图像描摹插件对象，无法无损读取路径”。
- 不增加面板控件，不修改 `latest_sync.json` 的 schema，不保留临时文件或对象。

## 数据流与清理

1. 导出循环遇到 `PluginItem` 时读取 `isTracing`。
2. 非描摹对象：写入 `skipped` 诊断和错误原因，继续处理其他选区。
3. 描摹对象：调用 `duplicate()` 创建同层临时副本，调用 `app.redraw()` 等待描摹结果可用。
4. 调用副本 `tracing.expandTracing(false)`，以现有 `gd` 读取生成组的路径，并使用原对象的选区层级顺序。
5. 无论转换或读取是否失败，在 `finally` 中删除临时展开组或未转换副本；绝不调用原对象的 `remove`、`expandTracing` 或菜单展开命令。

## 诊断与失败处理

- 成功：面板详情显示 `PluginItem`、图像描摹标记和“临时展开后已导出”。
- 非描摹：提示不会自动转换第三方/效果插件对象。
- 展开或读取失败：提示临时展开失败及 Illustrator 返回的错误；其他已选对象仍继续导出。
- 临时清理失败：记录诊断错误，不改变原稿；不把清理失败伪装为成功。

## 验证

- 自动测试：描摹型 `PluginItem` 导出生成组，原对象不被删除，临时组被删除。
- 自动测试：非描摹 `PluginItem` 仍无输出且报告明确跳过原因。
- 自动测试：临时展开抛错后没有路径输出，错误可见且临时副本被清理。
- 人工测试：在 Illustrator 2023 选中图像描摹对象，导出后确认原稿未变化、JSON 含展开后的路径；再测试非描摹 `PluginItem` 的提示。
