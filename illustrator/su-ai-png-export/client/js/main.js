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
    var jsonShortcutInput = document.getElementById("jsonShortcut");
    var pngShortcutInput = document.getElementById("pngShortcut");
    var setJsonShortcutBtn = document.getElementById("setJsonShortcutBtn");
    var setPngShortcutBtn = document.getElementById("setPngShortcutBtn");
    var clearJsonShortcutBtn = document.getElementById("clearJsonShortcutBtn");
    var clearPngShortcutBtn = document.getElementById("clearPngShortcutBtn");
    var shortcuts = {
        json: localStorage.getItem("suai.shortcut.json") || "",
        png: localStorage.getItem("suai.shortcut.png") || ""
    };
    var recordingShortcut = "";
    var shortcutHostPath = csInterface.getSystemPath(SystemPath.EXTENSION) + "/bin/SUAIShortcutHost.exe";
    var shortcutCommandPending = false;
    var shortcutHeartbeatCount = 0;

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

    function keyFromEvent(event) {
        var key = event.key || "";
        var keyCode = event.keyCode || event.which || 0;
        if (!key || key === "Unidentified") {
            if (keyCode >= 112 && keyCode <= 123) return "F" + (keyCode - 111);
            if (keyCode >= 65 && keyCode <= 90) return String.fromCharCode(keyCode);
            if (keyCode >= 48 && keyCode <= 57) return String.fromCharCode(keyCode);
            var specialKeys = {13:"Enter",27:"Escape",32:"Space",37:"ArrowLeft",38:"ArrowUp",39:"ArrowRight",40:"ArrowDown",46:"Delete"};
            return specialKeys[keyCode] || "";
        }
        if (key === "Esc") key = "Escape";
        if (key === " ") key = "Space";
        if (/^F([1-9]|1[0-2])$/i.test(key)) return key.toUpperCase();
        return key.length === 1 ? key.toUpperCase() : key;
    }

    function shortcutFromEvent(event) {
        var key = keyFromEvent(event);
        if (key === "Control" || key === "Shift" || key === "Alt" || key === "Meta") return "";
        var functionKey = /^F([1-9]|1[0-2])$/.test(key);
        if (!key || (!functionKey && !event.ctrlKey && !event.altKey && !event.shiftKey)) return "";
        var parts = [];
        if (event.ctrlKey) parts.push("Ctrl");
        if (event.altKey) parts.push("Alt");
        if (event.shiftKey) parts.push("Shift");
        parts.push(key);
        return parts.join("+");
    }

    function showShortcut(shortcut) {
        return shortcut ? shortcut.replace(/\+/g, " + ") : "未设置";
    }

    function renderShortcuts() {
        jsonShortcutInput.value = recordingShortcut === "json" ? "按组合键或 F1-F12" : showShortcut(shortcuts.json);
        pngShortcutInput.value = recordingShortcut === "png" ? "按组合键或 F1-F12" : showShortcut(shortcuts.png);
        jsonShortcutInput.className = "shortcut-input" + (recordingShortcut === "json" ? " recording" : "");
        pngShortcutInput.className = "shortcut-input" + (recordingShortcut === "png" ? " recording" : "");
    }

    function saveShortcut(action, shortcut) {
        var other = action === "json" ? "png" : "json";
        if (shortcut && shortcuts[other] === shortcut) {
            shortcuts[other] = "";
            localStorage.removeItem("suai.shortcut." + other);
        }
        shortcuts[action] = shortcut;
        if (shortcut) localStorage.setItem("suai.shortcut." + action, shortcut);
        else localStorage.removeItem("suai.shortcut." + action);
        recordingShortcut = "";
        renderShortcuts();
        syncGlobalShortcuts();
        setStatus(shortcut ? "快捷键已保存" : "快捷键已清除", "info");
    }

    function syncGlobalShortcuts() {
        var script = "configureGlobalShortcuts(\"" + escape(shortcuts.json) + "\",\"" + escape(shortcuts.png) + "\",\"" + escape(shortcutHostPath) + "\")";
        csInterface.evalScript(script);
    }

    function maintainGlobalShortcutHost() {
        shortcutHeartbeatCount++;
        csInterface.evalScript("touchGlobalShortcutHeartbeat()");
        if (shortcutHeartbeatCount % 5 === 0) {
            csInterface.evalScript("ensureGlobalShortcutHost(\"" + escape(shortcutHostPath) + "\")");
        }
    }

    function pollGlobalShortcutCommand() {
        if (shortcutCommandPending) return;
        shortcutCommandPending = true;
        csInterface.evalScript("consumeGlobalShortcutCommand()", function (result) {
            shortcutCommandPending = false;
            var command = String(result || "").replace(/^"|"$/g, "");
            if (command === "json" && !exportJsonBtn.disabled) doJsonExport();
            else if (command === "png" && !exportBtn.disabled) doExport();
        });
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

    function updateSelectionInfo() {
        csInterface.evalScript("getSelectionInfo()", function (result) {
            try {
                var info = JSON.parse(result);
                if (info.count > 0) {
                    setStatus("已选中 " + info.count + " 个对象", "info");
                } else {
                    setStatus("就绪 - 选择对象后点击导出", "");
                }
            } catch (e) {
                // ignore
            }
        });
    }

    // ===== 浏览导出目录 =====

    function browseFolder() {
        // 调用 AI 原生目录选择对话框
        var defaultPath = exportPathInput.value || "";
        csInterface.evalScript("pickExportFolder(\"" + escape(defaultPath) + "\")", function (result) {
            if (result && result.length > 0 && result !== "null") {
                exportPathInput.value = result;
                saveExportConfig(result);
                setStatus("导出目录已设置", "info");
            }
        });
    }

    function escape(s) {
        return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    }

    // ===== 执行导出 =====

    function doExport() {
        var folderPath = exportPathInput.value.trim();
        if (!folderPath || folderPath.length < 2) {
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
                    // 刷新选中信息
                    updateSelectionInfo();
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

            exportBtn.disabled = false;
            exportBtn.textContent = "🖼 导出图片";
        });
    }

    // ===== 热加载 =====

    function doJsonExport() {
        var folderPath = exportPathInput.value.trim();
        if (!folderPath || folderPath.length < 2) {
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
                if (data.errors && data.errors.length > 0) {
                    for (var i = 0; i < data.errors.length; i++) {
                        addLog("❌ " + data.errors[i], "err");
                    }
                }
                if (data.count > 0) {
                    setStatus("✅ JSON 导出完成: " + data.count + " 个路径", "success");
                    addLog("✅ 文件: " + data.jsonFile, "ok");
                    updateSelectionInfo();
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
            exportJsonBtn.disabled = false;
            exportJsonBtn.textContent = "📄 导出轮廓";
        });
    }

    function reloadExtension() {
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
        });
    }

    // ===== 事件绑定 =====

    browseBtn.addEventListener("click", browseFolder);

    exportBtn.addEventListener("click", doExport);

    exportJsonBtn.addEventListener("click", doJsonExport);

    setJsonShortcutBtn.addEventListener("click", function () {
        recordingShortcut = "json";
        renderShortcuts();
        jsonShortcutInput.focus();
        setStatus("请按组合键或 F1-F12", "info");
    });

    setPngShortcutBtn.addEventListener("click", function () {
        recordingShortcut = "png";
        renderShortcuts();
        pngShortcutInput.focus();
        setStatus("请按组合键或 F1-F12", "info");
    });

    clearJsonShortcutBtn.addEventListener("click", function () { saveShortcut("json", ""); });
    clearPngShortcutBtn.addEventListener("click", function () { saveShortcut("png", ""); });

    window.addEventListener("keydown", function (event) {
        if (event.repeat) return;
        var shortcut = shortcutFromEvent(event);
        if (recordingShortcut) {
            event.preventDefault();
            event.stopPropagation();
            if (event.stopImmediatePropagation) event.stopImmediatePropagation();
            if (shortcut) saveShortcut(recordingShortcut, shortcut);
            return;
        }
        if (!shortcut) return;
        if (shortcut === shortcuts.json && !exportJsonBtn.disabled) {
            event.preventDefault();
            event.stopPropagation();
            doJsonExport();
        } else if (shortcut === shortcuts.png && !exportBtn.disabled) {
            event.preventDefault();
            event.stopPropagation();
            doExport();
        }
    }, true);


    exportAsBtn.addEventListener("click", function() {
        setStatus("正在打开导出对话框...", "info");
        csInterface.evalScript("openExportDialog()", function(result) {
            var r = result.replace(/"/g, "");
            if (r === "ok") {
                setStatus("导出对话框已打开", "success");
            } else {
                setStatus("打开失败: " + r, "error");
            }
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

    // ===== 定时刷新选中信息 =====
    // 每 2 秒检查一次选中状态变化
    var lastSelCount = -1;
    setInterval(function () {
        csInterface.evalScript("getSelectionInfo()", function (result) {
            try {
                var info = JSON.parse(result);
                if (info.count !== lastSelCount) {
                    lastSelCount = info.count;
                    if (info.count > 0) {
                        setStatus("已选中 " + info.count + " 个对象", "info");
                    } else {
                        setStatus("就绪 - 选择对象后点击导出", "");
                    }
                }
            } catch (e) {}
        });
    }, 2000);

    // ===== 初始化 =====

    // 加载已保存的导出目录配置
    loadExportConfig();
    renderShortcuts();
    syncGlobalShortcuts();
    setInterval(maintainGlobalShortcutHost, 1000);
    setInterval(pollGlobalShortcutCommand, 200);
    setStatus("就绪 - 选择对象后点击导出", "");

    // 面板关闭时清理
    window.addEventListener("beforeunload", function () {
        // 保存当前配置
        var path = exportPathInput.value.trim();
        if (path) saveExportConfig(path);
        csInterface.evalScript("disableGlobalShortcuts()");
    });

})();









