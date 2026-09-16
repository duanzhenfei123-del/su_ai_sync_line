// SU+AI PNG 导出 — 面板主逻辑
// CEP 前端: 处理 UI 事件, 通过 CSInterface 与 ExtendScript 通信

(function () {
    "use strict";

    // ===== CSInterface 初始化 =====
    var csInterface = new CSInterface();

    // ===== DOM 引用 =====
    var exportPathInput = document.getElementById("exportPath");
    var resolutionInput = document.getElementById("resolution");
    var browseBtn = document.getElementById("browseBtn");
    var exportBtn = document.getElementById("exportBtn");
    var exportJsonBtn = document.getElementById("exportJsonBtn");
    var exportAsBtn = document.getElementById("exportAsBtn");
    var reloadBtn = document.getElementById("reloadBtn");
    var statusBar = document.getElementById("statusBar");
    var detailLog = document.getElementById("detailLog");
    // ===== 工具函数 =====

    function setStatus(text, type) {
        statusBar.textContent = text;
        statusBar.className = "status-bar" + (type ? " " + type : "");
    }

    function addLog(text, type) {
        var entry = document.createElement("div");
        entry.className = "log-entry" + (type ? " " + type : "");
        entry.textContent = text;
        detailLog.appendChild(entry);
        detailLog.scrollTop = detailLog.scrollHeight;
        // 自动展开日志
        detailLog.classList.add("open");
    }

    function clearLog() {
        detailLog.innerHTML = "";
    }

    // ===== 从 AI 端获取导出目录配置 =====

    function loadExportConfig() {
        // 先获取桌面路径，再读取配置
        csInterface.evalScript("Folder.desktop.fsName", function(desktopPath) {
            var defaultExportDir = (desktopPath || "C:\\") + "/ai-export";
            csInterface.evalScript("readExportConfig()", function (result) {
                try {
                    var cfg = JSON.parse(result);
                    if (cfg && cfg.exportFolder) {
                        exportPathInput.value = cfg.exportFolder;
                    } else {
                        exportPathInput.value = defaultExportDir;
                    }
                } catch (e) {
                    exportPathInput.value = defaultExportDir;
                }
            });
        });
    }

    function saveExportConfig(path) {
        csInterface.evalScript("writeExportConfig(\"" + String(path).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + "\")");
    }

    // ===== 获取选中信息 =====

    var lastSelCount = -1;
    var selectionPollTimer = null;
    var selectionStatusLocked = false;
    var selectionExporting = false;

    function pollSelectionInfo() {
        if (selectionExporting || selectionStatusLocked || document.hidden) return;
        csInterface.evalScript("getSelectionInfo()", function (result) {
            try {
                if (selectionExporting || selectionStatusLocked || document.hidden) return;
                var info = JSON.parse(result);
                if (info.count !== lastSelCount) {
                    lastSelCount = info.count;
                    if (info.count > 0) {
                        setStatus("已选中 " + info.count + " 个对象", "info");
                    } else {
                        setStatus("就绪 - 选择对象后点击导出", "");
                    }
                }
            } catch (e) {
                // ignore
            }
        });
    }

    function stopSelectionPolling() {
        if (selectionPollTimer !== null) clearInterval(selectionPollTimer);
        selectionPollTimer = null;
    }

    function startSelectionPolling() {
        if (selectionPollTimer !== null || selectionExporting || selectionStatusLocked || document.hidden) return;
        pollSelectionInfo();
        selectionPollTimer = setInterval(pollSelectionInfo, 2000);
    }

    function unlockSelectionStatus() {
        selectionStatusLocked = false;
        lastSelCount = -1;
    }

    // ===== 浏览导出目录 =====

    function browseFolder() {
        unlockSelectionStatus();
        // 调用 AI 原生目录选择对话框
        var defaultPath = exportPathInput.value || "";
        csInterface.evalScript("pickExportFolder(\"" + escape(defaultPath) + "\")", function (result) {
            if (result && result.length > 0 && result !== "null") {
                exportPathInput.value = result;
                saveExportConfig(result);
                setStatus("导出目录已设置", "info");
            }
            startSelectionPolling();
        });
    }

    function escape(s) {
        return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    }

    // ===== 执行导出 =====

    function doExport() {
        unlockSelectionStatus();
        selectionExporting = true;
        stopSelectionPolling();
        var folderPath = exportPathInput.value.trim();
        if (!folderPath || folderPath.length < 2) {
            selectionExporting = false;
            startSelectionPolling();
            setStatus("请先选择导出目录", "error");
            return;
        }

        var resolution = parseInt(resolutionInput.value, 10);
        if (isNaN(resolution) || resolution < 72) resolution = 150;
        if (resolution > 600) resolution = 600;

        // 禁用按钮
        exportBtn.disabled = true;
        exportBtn.textContent = "⏳ 导出中...";
        clearLog();
        setStatus("正在导出...", "info");

        // 保存配置
        saveExportConfig(folderPath);

        // 构造调用参数, 传给 ExtendScript
        var script = "exportSelectionAsPNG(\"" + escape(folderPath) + "\", " + resolution + ")";
        addLog("开始导出: " + folderPath, "");
        addLog("分辨率: " + resolution + " PPI", "");

        csInterface.evalScript(script, function (result) {
            try {
                var data = JSON.parse(result);

                if (data.errors && data.errors.length > 0) {
                    for (var i = 0; i < data.errors.length; i++) {
                        addLog("❌ " + data.errors[i], "err");
                    }
                }

                if (data.count > 0) {
                    setStatus("✅ 导出完成: " + data.count + "/" + data.total + " 个", "success");
                    addLog("✅ 成功导出 " + data.count + " 个 PNG", "ok");
                } else if (data.total === 0) {
                    setStatus("⚠️ 未选中任何对象", "error");
                    addLog("⚠️ 请先在 Illustrator 中选择对象", "err");
                } else {
                    setStatus("⚠️ 导出 " + data.count + "/" + data.total + " 个 (有失败)", "error");
                }
            } catch (e) {
                setStatus("❌ 导出失败: " + e.message, "error");
                addLog("❌ " + (result || e.message), "err");
            }

            selectionExporting = false;
            selectionStatusLocked = true;
            exportBtn.disabled = false;
            exportBtn.textContent = "🖼 导出图片";
        });
    }

    // ===== 热加载 =====

    function doJsonExport() {
        unlockSelectionStatus();
        selectionExporting = true;
        stopSelectionPolling();
        var folderPath = exportPathInput.value.trim();
        if (!folderPath || folderPath.length < 2) {
            selectionExporting = false;
            startSelectionPolling();
            setStatus("请先选择导出目录", "error");
            return;
        }

        exportJsonBtn.disabled = true;
        exportJsonBtn.textContent = "⏳ 导出 JSON...";
        clearLog();
        setStatus("正在导出 JSON...", "info");

        saveExportConfig(folderPath);

        var script = "exportSelectionAsJSON(\"" + escape(folderPath) + "\")";
        addLog("开始导出 JSON: " + folderPath, "");

        csInterface.evalScript(script, function (result) {
            try {
                var data = JSON.parse(result);
                if (data.diagnostics && data.diagnostics.length > 0) {
                    for (var d = 0; d < data.diagnostics.length; d++) {
                        var diagnostic = data.diagnostics[d];
                        var detail = "🔎 第 " + diagnostic.index + " 项：" + diagnostic.type;
                        if (typeof diagnostic.pathCount === "number") detail += "（" + diagnostic.pathCount + " 个子路径）";
                        detail += diagnostic.status === "skipped" ? "，已跳过：" + diagnostic.reason : diagnostic.temporaryExpansion ? "，临时展开后已导出" : "，已导出";
                        addLog(detail, diagnostic.status === "skipped" ? "err" : "");
                    }
                }
                if (data.errors && data.errors.length > 0) {
                    for (var i = 0; i < data.errors.length; i++) {
                        addLog("❌ " + data.errors[i], "err");
                    }
                }
                if (data.count > 0) {
                    setStatus("✅ JSON 导出完成: " + data.count + " 个路径", "success");
                    addLog("✅ 文件: " + data.jsonFile, "ok");
                } else if (data.total === 0) {
                    setStatus("⚠️ 未选中任何对象", "error");
                    addLog("⚠️ 请先在 Illustrator 中选择对象", "err");
                } else {
                    setStatus("⚠️ 导出 " + data.count + "/" + data.total + " 个 (有失败)", "error");
                }
            } catch (e) {
                setStatus("❌ JSON 导出失败: " + e.message, "error");
                addLog("❌ " + (result || e.message), "err");
            }
            selectionExporting = false;
            selectionStatusLocked = true;
            exportJsonBtn.disabled = false;
            exportJsonBtn.textContent = "📄 导出轮廓";
        });
    }

    function reloadExtension() {
        unlockSelectionStatus();
        stopSelectionPolling();
        setStatus("正在重载...", "info");
        clearLog();
        addLog("重载 ExtendScript 后端...", "");

        var extPath = csInterface.getSystemPath(SystemPath.EXTENSION) + "/host/main.jsx";
        var script = '$.evalFile("' + escape(extPath) + '")';

        csInterface.evalScript(script, function () {
            addLog("ExtendScript 已重载", "ok");
            // 验证关键函数
            csInterface.evalScript("typeof exportSelectionAsPNG", function(result) {
                addLog("exportSelectionAsPNG: " + result, result === "function" ? "ok" : "err");
            });
            csInterface.evalScript("typeof exportSelectionAsJSON", function(result) {
                addLog("exportSelectionAsJSON: " + result, result === "function" ? "ok" : "err");
            });
            csInterface.evalScript("typeof getSelectionInfo", function(result) {
                addLog("getSelectionInfo: " + result, result === "function" ? "ok" : "err");
            });
            csInterface.evalScript("typeof readExportConfig", function(result) {
                addLog("readExportConfig: " + result, result === "function" ? "ok" : "err");
            });
            setStatus("重载完成", "success");
            startSelectionPolling();
        });
    }

    // ===== 事件绑定 =====

    browseBtn.addEventListener("click", browseFolder);

    exportBtn.addEventListener("click", doExport);

    exportJsonBtn.addEventListener("click", doJsonExport);

    exportAsBtn.addEventListener("click", function() {
        unlockSelectionStatus();
        stopSelectionPolling();
        setStatus("正在打开导出对话框...", "info");
        csInterface.evalScript("openExportDialog()", function(result) {
            var r = result.replace(/"/g, "");
            if (r === "ok") {
                setStatus("导出对话框已打开", "success");
            } else {
                setStatus("打开失败: " + r, "error");
            }
            startSelectionPolling();
        });
    });

    reloadBtn.addEventListener("click", reloadExtension);

    // 回车触发导出
    exportPathInput.addEventListener("keydown", function (e) {
        if (e.key === "Enter") doExport();
    });
    resolutionInput.addEventListener("keydown", function (e) {
        if (e.key === "Enter") doExport();
    });

    // ===== 初始化 =====

    // 加载已保存的导出目录配置
    loadExportConfig();
    setStatus("就绪 - 选择对象后点击导出", "");
    startSelectionPolling();

    document.addEventListener("visibilitychange", function () {
        if (document.hidden) stopSelectionPolling();
        else startSelectionPolling();
    });

    window.addEventListener("beforeunload", function () {
        stopSelectionPolling();
        var path = exportPathInput.value.trim();
        if (path) saveExportConfig(path);
    });

})();
