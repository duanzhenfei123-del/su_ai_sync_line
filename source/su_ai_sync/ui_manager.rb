require "cgi"
require "base64"

module SU_AI_Sync
  class UI_Manager
    PLUGIN = "su_ai_sync"

    def initialize
      @hot_reloader = HotReloader.new
      @dialog = nil
      @scale = Sketchup.read_default(PLUGIN, "scale", 1.0).to_f
      @create_faces = Sketchup.read_default(PLUGIN, "faces", 1).to_i == 1
      @curve_segs = Sketchup.read_default(PLUGIN, "segs", 12).to_i
      @extrude_enabled = Sketchup.read_default(PLUGIN, "extrude_enabled", 0).to_i == 1
      @extrude_thickness = Sketchup.read_default(PLUGIN, "extrude_thickness", 10.0).to_f
      @z_stack_enabled = Sketchup.read_default(PLUGIN, "z_stack", 0).to_i == 1
      @layer_gap = LayerLayout.normalize_gap(
        Sketchup.read_default(PLUGIN, "layer_gap", 10.0)
      )
      @placement = Sketchup.read_default(PLUGIN, "placement", "origin")
      @import_folder = SU_AI_Sync.import_folder
      Logger.info("UI_Manager: import_folder = #{@import_folder}")
    end

    def show
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
      @dialog = create_dialog
      @dialog.show
    end

    def close
      @dialog.close if @dialog&.visible?
    end

    private

    def create_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: DISPLAY_NAME,
        preferences_key: "su_ai_sync_dialog",
        scrollable: true, resizable: true,
        width: 374, height: 640,
        left: 200, top: 200,
        min_width: 340, min_height: 560
      )
      dialog.set_html(html_content)

      dialog.add_action_callback("import") do |_ctx, placement|
        model = Sketchup.active_model
        unless model
          set_import_status(dialog, "请先打开一个 SketchUp 模型", state: "error", waiting: false)
          UI.messagebox("请先打开一个 SketchUp 模型")
          next
        end
        @placement = placement == "mouse" ? "mouse" : "origin"
        Sketchup.write_default(PLUGIN, "placement", @placement)
        effective_extrude = @extrude_enabled ? @extrude_thickness : 0
        Logger.info("Import extrude=#{effective_extrude} (enabled=#{@extrude_enabled})")
        args = [@scale, @create_faces, @curve_segs, @import_folder, effective_extrude, @z_stack_enabled, @layer_gap]
        if @placement == "mouse"
          preview = Importer.new(model).import(*args, preview: true)
          unless preview[:success]
            set_import_status(dialog, preview[:message], state: "error", waiting: false)
            next
          end
          set_import_status(dialog, "移动鼠标预览，左键确认，Esc 取消", state: "active", waiting: true)
          model.select_tool(ImportPlacementTool.new(model, preview[:edges]) do |target|
            result = preview[:confirm].call(target) if target
            if result
              set_import_status(dialog, result[:message] || "导入完成", state: result[:success] ? "ready" : "error", waiting: false)
            else
              set_import_status(dialog, "已取消放置", waiting: false)
            end
          end)
        else
          result = Importer.new(model).import(*args)
          set_import_status(dialog, result[:message] || "导入完成", state: result[:success] ? "ready" : "error", waiting: false)
        end
      end

      dialog.add_action_callback("reload") do |_ctx|
        @hot_reloader.reload!
      end

      dialog.add_action_callback("open_log") do |_ctx|
        if File.exist?(LOG_FILE)
          UI.openURL("file:///#{LOG_FILE.gsub('\\', '/')}")
        else
          UI.messagebox("未找到日志文件")
        end
      end

      dialog.add_action_callback("set_debug") do |_ctx, value|
        @debug_enabled = value
        Logger.debug_mode = value
      end

      dialog.add_action_callback("set_scale") do |_ctx, value|
        @scale = value.to_f
        Sketchup.write_default(PLUGIN, "scale", @scale)
      end

      dialog.add_action_callback("set_face") do |_ctx, value|
        @create_faces = value
        Sketchup.write_default(PLUGIN, "faces", value ? 1 : 0)
        unless value
          @extrude_enabled = false
          Sketchup.write_default(PLUGIN, "extrude_enabled", 0)
        end
      end

      dialog.add_action_callback("set_segs") do |_ctx, value|
        @curve_segs = value.to_i
        Sketchup.write_default(PLUGIN, "segs", @curve_segs)
      end

      dialog.add_action_callback("set_extrude") do |_ctx, value|
        @extrude_thickness = value.to_f
        Sketchup.write_default(PLUGIN, "extrude_thickness", @extrude_thickness)
      end

      dialog.add_action_callback("set_extrude_enabled") do |_ctx, value|
        @extrude_enabled = value
        Sketchup.write_default(PLUGIN, "extrude_enabled", value ? 1 : 0)
        if value
          @create_faces = true
          Sketchup.write_default(PLUGIN, "faces", 1)
        end
      end

      dialog.add_action_callback("set_z_stack") do |_ctx, value|
        @z_stack_enabled = value == true
        Sketchup.write_default(PLUGIN, "z_stack", @z_stack_enabled ? 1 : 0)
      end

      dialog.add_action_callback("set_layer_gap") do |_ctx, value|
        @layer_gap = LayerLayout.normalize_gap(value)
        Sketchup.write_default(PLUGIN, "layer_gap", @layer_gap)
      end

      dialog.add_action_callback("drop_to_surface") do |_ctx|
        begin
          moved = ToolActions.drop_selection(Sketchup.active_model)
          if moved > 0
            set_import_status(dialog, "已坐落 #{moved} 个对象", state: "ready")
          end
        rescue StandardError => error
          Logger.error("Drop to surface failed: #{error.message}")
          UI.messagebox("落面失败: #{error.message}")
        end
      end

      dialog.add_action_callback("import_texture_aligned") do |_ctx|
        image = ToolActions.import_texture_aligned(Sketchup.active_model)
        if image
          set_import_status(dialog, "贴图已按选择对象对齐", state: "ready")
        end
      end

      dialog.add_action_callback("browse_folder") do |_ctx|
        browse_folder(dialog)
      end

      dialog.add_action_callback("reset_folder") do |_ctx|
        update_folder(dialog, SU_AI_Sync::EXPORT_DIR)
      end

      dialog.add_action_callback("set_folder_path") do |_ctx, path|
        raw = path.to_s.strip
        clean = raw.sub(/^\(默认\)\s*/, "")
        unless File.directory?(clean)
          dialog.execute_script("setFolder(#{JSON.generate(@import_folder)});")
          set_import_status(dialog, "路径不存在或不是文件夹", state: "error")
          next
        end
        update_folder(dialog, clean)
      end
      dialog
    end

    def set_import_status(dialog, status, state: "idle", waiting: nil)
      return unless dialog.visible?

      dialog.execute_script("showStatus(#{JSON.generate(status)}, #{JSON.generate(state)}, #{JSON.generate(waiting)});")
    end

    def browse_folder(dialog)
      path = UI.select_directory(
        title: "选择导入文件夹（包含 .json 和图片）",
        directory: @import_folder
      )
      return unless path

      update_folder(dialog, path)
    rescue => e
      Logger.error("Browse folder: #{e.message}")
      UI.messagebox("文件夹选择失败: #{e.message}")
    end
    def update_folder(dialog, path)
      @import_folder = path
      SU_AI_Sync.save_import_folder(path)
      dialog.execute_script("setFolder(#{JSON.generate(path)});")
      status, state = folder_status
      set_import_status(dialog, status, state: state)
    end

    def folder_status
      return ["未找到同步数据", "idle"] unless File.directory?(@import_folder)

      found = Dir.children(@import_folder).any? do |entry|
        (entry == "latest_sync.json" || entry.match?(/^sync_.*\.json$/i)) && File.file?(File.join(@import_folder, entry))
      end
      found ? ["已找到同步数据", "ready"] : ["未找到同步数据", "idle"]
    rescue SystemCallError
      ["无法读取导入文件夹", "error"]
    end

    def html_content
      scale_selected_1 = @scale == 1.0 ? " selected" : ""
      scale_selected_10 = @scale == 10.0 ? " selected" : ""

      segs_options = [4,6,8,10,12,16,20,24].map { |n|
        sel = @curve_segs == n ? " selected" : ""
        "<option value=\"#{n}\"#{sel}>#{n}</option>"
      }.join("\n          ")

      folder_display = CGI.escapeHTML(@import_folder)
      status_text, status_state = folder_status
      donation_image = Base64.strict_encode64(File.binread(File.join(__dir__, "assets", "wechat_pay.png")))

      <<~HTML
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light;
              --ink: #182233;
              --muted: #596579;
              --border: #cbd3df;
              --blue: #2563eb;
              --accent: #1d4ed8;
            }
            * { box-sizing: border-box; }
            body {
              margin: 8px;
              background: #eef2f7;
              color: var(--ink);
              font: 13px/1.5 "Segoe UI", "Microsoft YaHei UI", sans-serif;
            }
            [hidden] { display: none !important; }
            h1, h2, p, fieldset { margin: 0; }
            h1 { font-size: 15px; font-weight: 650; }
            h2, legend, .field-label { font-size: 13px; font-weight: 600; }
            fieldset { min-width: 0; padding: 0; border: 0; }
            legend { padding: 0; }
            button:focus-visible, input:focus-visible, select:focus-visible, summary:focus-visible,
            .segments input:focus-visible + span {
              outline: 2px solid var(--blue);
              outline-offset: 2px;
            }
            button, input, select { font: inherit; color: inherit; }
            button, summary, select { cursor: pointer; }
            button:disabled { cursor: default; }
            button, select, input[type=text], input[type=number] {
              min-height: 36px;
              border: 1px solid var(--border);
              border-radius: 6px;
              background: #fff;
            }
            button { padding: 6px 11px; font-weight: 600; }
            button:not(:disabled):hover { border-color: #8796ad; background: #f3f6fb; }
            select, input[type=text], input[type=number] { padding: 5px 8px; }
            .panel {
              padding: 12px 14px 14px;
              background: #fff;
              border: 1px solid #dae1eb;
              border-radius: 9px;
            }
            .panel-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              gap: 6px;
              padding-bottom: 9px;
              border-bottom: 1px solid #e2e7ef;
            }
            .dtt-ai-sync-header-actions { display: flex; align-items: center; gap: 4px; }
            .dtt-ai-sync-donate { min-height: 32px; white-space: nowrap; padding: 4px 8px; }
            .dtt-ai-sync-donation {
              max-width: calc(100% - 16px);
              padding: 10px;
              border: 1px solid var(--border);
              border-radius: 8px;
            }
            .dtt-ai-sync-donation::backdrop { background: rgba(24, 34, 51, .50); }
            .dtt-ai-sync-donation form { margin-bottom: 6px; text-align: right; }
            .dtt-ai-sync-donation img { display: block; margin: auto; max-width: 100%; max-height: calc(100vh - 90px); }
            .import-options { display: grid; gap: 12px; margin-top: 12px; }
            .field-label { display: block; margin-bottom: 5px; }
            .row { display: flex; align-items: center; gap: 8px; }
            .columns { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }
            .columns select { width: 100%; }
            .folder-field { position: relative; flex: 1; min-width: 0; }
            #folder_input { width: 100%; padding-left: 30px; }
            .folder-icon {
              position: absolute;
              left: 9px;
              top: 14px;
              width: 14px;
              height: 10px;
              border: 1.4px solid var(--muted);
              border-radius: 2px;
              pointer-events: none;
            }
            .folder-icon::before {
              content: "";
              position: absolute;
              left: -1px;
              top: -4px;
              width: 7px;
              height: 4px;
              border: 1.4px solid var(--muted);
              border-bottom: 0;
              border-radius: 2px 2px 0 0;
              background: #fff;
            }
            .segments {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              overflow: hidden;
              border: 1px solid var(--border);
              border-radius: 6px;
            }
            .segments label { position: relative; text-align: center; }
            .segments label + label { border-left: 1px solid var(--border); }
            .segments input { position: absolute; opacity: 0; top: 0; left: 0; margin: 0; width: 100%; height: 100%; cursor: pointer; }
            .segments span { display: block; padding: 8px 5px; font-weight: 600; }
            .segments input:checked + span { background: #e8f0ff; color: var(--accent); }
            .segments input:focus-visible + span { outline-offset: -2px; }
            .segments input:disabled { cursor: default; }
            .hint { margin-top: 4px; color: var(--muted); font-size: 11.5px; }
            .toggle-label { display: flex; justify-content: space-between; align-items: center; gap: 8px; min-height: 27px; }
            .switch {
              -webkit-appearance: none;
              appearance: none;
              flex: 0 0 auto;
              position: relative;
              width: 32px;
              height: 18px;
              margin: 0;
              border: 1px solid #8c98ac;
              border-radius: 999px;
              background: #8c98ac;
              cursor: pointer;
            }
            .switch::after {
              content: "";
              position: absolute;
              top: 2px;
              left: 2px;
              width: 12px;
              height: 12px;
              border-radius: 50%;
              background: #fff;
            }
            .switch:checked { border-color: var(--blue); background: var(--blue); }
            .switch:checked::after { left: 16px; }
            .number-row { justify-content: space-between; }
            .number-row input { width: 78px; }
            .advanced { border: 1px solid var(--border); border-radius: 6px; background: #f8faff; }
            summary { list-style: none; }
            summary::-webkit-details-marker { display: none; }
            .advanced summary { position: relative; padding: 7px 10px; font-weight: 600; }
            .advanced summary::after {
              content: "";
              position: absolute;
              right: 12px;
              top: 13px;
              width: 6px;
              height: 6px;
              border: solid var(--muted);
              border-width: 0 1.5px 1.5px 0;
              transform: rotate(45deg);
            }
            .advanced[open] summary::after { top: 16px; transform: rotate(225deg); }
            .advanced-body { padding: 4px 10px 8px; border-top: 1px solid #e2e7ef; }
            .advanced-body .number-row { margin-top: 5px; }
            #importBtn {
              width: 100%;
              min-height: 40px;
              border-color: var(--blue);
              background: var(--blue);
              color: #fff;
              font-size: 14px;
            }
            #importBtn:hover:not(:disabled) { border-color: var(--accent); background: var(--accent); }
            #importBtn:disabled { border-color: #a8b9d4; background: #a8b9d4; color: #17263c; }
            .status-line { display: flex; align-items: baseline; gap: 7px; margin-top: 7px; color: var(--muted); font-size: 12px; }
            .status-line::before { content: ""; flex: 0 0 7px; height: 7px; border-radius: 50%; background: #8291a7; }
            .status-line[data-state="ready"]::before { background: #138044; }
            .status-line[data-state="active"]::before { background: var(--blue); }
            .status-line[data-state="error"] { color: #a5272b; }
            .status-line[data-state="error"]::before { background: #bd383c; }
            #status { overflow-wrap: anywhere; }
            .tools { margin-top: 12px; padding-top: 9px; border-top: 1px solid #e2e7ef; }
            .tools h2 { margin-bottom: 6px; }
            .tools button { width: 100%; }
            .settings { position: relative; }
            .settings summary {
              display: grid;
              place-items: center;
              width: 32px;
              height: 32px;
              border: 1px solid transparent;
              border-radius: 6px;
              color: #425169;
              font: 21px/1 "Segoe UI Symbol", sans-serif;
            }
            .settings summary:hover, .settings[open] summary { border-color: var(--border); background: #f3f6fb; }
            .settings-menu {
              position: absolute;
              top: 38px;
              right: 0;
              z-index: 1;
              display: grid;
              gap: 5px;
              width: 166px;
              padding: 6px;
              border: 1px solid var(--border);
              border-radius: 7px;
              background: #fff;
              box-shadow: 0 5px 16px #1c304127;
            }
            .settings-menu button { min-height: 30px; text-align: left; }
            .settings-menu label { padding: 0 5px; }
          </style>
        </head>
        <body>
          <main class="panel">
            <header class="panel-header">
              <h1>#{DISPLAY_NAME} · 段土土 · v#{VERSION}</h1>
              <div class="dtt-ai-sync-header-actions">
                <button type="button" class="dtt-ai-sync-donate" onclick="document.getElementById('dtt-ai-sync-donation').showModal()">打赏</button>
                <details class="settings">
                  <summary aria-label="插件设置" title="插件设置">&#9881;</summary>
                  <div class="settings-menu">
                    <button type="button" onclick="sketchup.reload()">热重载插件</button>
                    <button type="button" onclick="sketchup.open_log()">打开日志</button>
                    <button type="button" onclick="sketchup.reset_folder()">恢复默认文件夹</button>
                    <label class="toggle-label" for="debugChk">调试模式
                      <input class="switch" type="checkbox" id="debugChk" #{@debug_enabled ? 'checked' : ''} onchange="sketchup.set_debug(this.checked)">
                    </label>
                  </div>
                </details>
              </div>
            </header>

            <div class="import-options">
              <div>
                <label class="field-label" for="folder_input">导入文件夹</label>
                <div class="row">
                  <div class="folder-field">
                    <span class="folder-icon" aria-hidden="true"></span>
                    <input type="text" id="folder_input" value="#{folder_display}" title="#{folder_display}" onchange="onFolderChange(this.value)" onkeydown="if(event.key==='Enter')this.blur()">
                  </div>
                  <button type="button" onclick="sketchup.browse_folder()">浏览</button>
                </div>
              </div>

              <fieldset id="placement" aria-describedby="placementHint">
                <legend class="field-label">放置方式</legend>
                <div class="segments" onchange="updatePlacementHint()">
                  <label><input type="radio" name="placement" value="origin" #{@placement == 'mouse' ? '' : 'checked'}><span>自动定位</span></label>
                  <label><input type="radio" name="placement" value="mouse" #{@placement == 'mouse' ? 'checked' : ''}><span>跟随鼠标</span></label>
                </div>
                <p class="hint" id="placementHint">#{@placement == 'mouse' ? '移动鼠标预览，左键确认，Esc 取消' : '画板内按画板定位，画板外按对象归零'}</p>
              </fieldset>

              <div class="columns">
                <div>
                  <label class="field-label" for="scale">导入比例</label>
                  <select id="scale" onchange="sketchup.set_scale(this.value)">
                    <option value="1.0"#{scale_selected_1}>1:1 等大</option>
                    <option value="10.0"#{scale_selected_10}>1:10（放大 10 倍）</option>
                  </select>
                </div>
                <div>
                  <label class="field-label" for="segments">曲线精度</label>
                  <select id="segments" onchange="sketchup.set_segs(this.value)">
                    #{segs_options}
                  </select>
                </div>
              </div>

              <div class="columns">
                <label class="toggle-label" for="faceToggle">导入封面
                  <input class="switch" id="faceToggle" type="checkbox" #{@create_faces ? 'checked' : ''} onchange="toggleFace(this.checked)">
                </label>
                <label class="toggle-label" for="extrudeToggle">拉成体块
                  <input class="switch" id="extrudeToggle" type="checkbox" #{@extrude_enabled ? 'checked' : ''} onchange="toggleExtrude(this.checked)">
                </label>
              </div>
              <div id="extrudeRow" class="row number-row" #{@extrude_enabled ? '' : 'hidden'}>
                <label for="extrudeInput">挤出厚度（mm）</label>
                <input type="number" id="extrudeInput" value="#{@extrude_thickness}" min="0.1" step="1" onchange="sketchup.set_extrude(this.value)">
              </div>

              <details id="advancedOptions" class="advanced">
                <summary>高级选项</summary>
                <div class="advanced-body">
                  <label class="toggle-label" for="zStackToggle">按图层叠放
                    <input class="switch" id="zStackToggle" type="checkbox" #{@z_stack_enabled ? 'checked' : ''} onchange="toggleZStack(this.checked)">
                  </label>
                  <div id="layerGapRow" class="row number-row" #{@z_stack_enabled ? '' : 'hidden'}>
                    <label for="layerGapInput">层间距（mm）</label>
                    <input type="number" id="layerGapInput" value="#{@layer_gap}" min="0.1" step="1" onchange="sketchup.set_layer_gap(this.value)">
                  </div>
                </div>
              </details>

              <div>
                <button type="button" id="importBtn" onclick="doImport()">导入同步数据</button>
                <div class="status-line" data-state="#{status_state}"><span id="status" role="status">#{status_text}</span></div>
              </div>
            </div>

            <section class="tools" aria-labelledby="toolsHeading">
              <h2 id="toolsHeading">辅助工具</h2>
              <div class="columns">
                <button type="button" onclick="sketchup.drop_to_surface()">坐落物体表面</button>
                <button type="button" onclick="sketchup.import_texture_aligned()">导入贴图对齐</button>
              </div>
            </section>
          </main>
          <dialog id="dtt-ai-sync-donation" class="dtt-ai-sync-donation" aria-label="打赏">
            <form method="dialog"><button type="submit">关闭</button></form>
            <img src="data:image/png;base64,#{donation_image}" alt="微信与支付宝收款码合图">
          </dialog>
          <script>
            function selectedPlacement() {
              return document.querySelector('input[name="placement"]:checked').value;
            }

            function updatePlacementHint() {
              document.getElementById('placementHint').textContent = selectedPlacement() === 'mouse'
                ? '移动鼠标预览，左键确认，Esc 取消'
                : '画板内按画板定位，画板外按对象归零';
            }

            function showStatus(message, state, waiting = null) {
              const status = document.getElementById('status');
              status.textContent = message;
              status.parentElement.dataset.state = state;
              if (waiting !== null) {
                document.getElementById('importBtn').disabled = waiting;
                document.getElementById('placement').disabled = waiting;
              }
            }

            function doImport() {
              showStatus('正在导入…', 'active', true);
              sketchup.import(selectedPlacement());
            }

            function toggleFace(enabled) {
              sketchup.set_face(enabled);
              if (!enabled) {
                document.getElementById('extrudeToggle').checked = false;
                document.getElementById('extrudeRow').hidden = true;
              }
            }

            function toggleExtrude(enabled) {
              document.getElementById('extrudeRow').hidden = !enabled;
              if (enabled) {
                document.getElementById('faceToggle').checked = true;
                sketchup.set_extrude(document.getElementById('extrudeInput').value);
              }
              sketchup.set_extrude_enabled(enabled);
            }

            function toggleZStack(enabled) {
              document.getElementById('layerGapRow').hidden = !enabled;
              if (enabled) sketchup.set_layer_gap(document.getElementById('layerGapInput').value);
              sketchup.set_z_stack(enabled);
            }

            function setFolder(path) {
              const input = document.getElementById('folder_input');
              input.value = path;
              input.title = path;
            }

            function onFolderChange(path) {
              sketchup.set_folder_path(path);
            }

            const settings = document.querySelector('.settings');
            document.addEventListener('click', event => {
              if (settings.open && !settings.contains(event.target)) settings.open = false;
            });
            document.addEventListener('keydown', event => {
              if (event.key === 'Escape' && settings.open) {
                settings.open = false;
                settings.querySelector('summary').focus();
              }
            });
          </script>
        </body>
        </html>
      HTML
    end
  end
end
