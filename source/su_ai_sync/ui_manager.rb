require "set" unless defined?(Set)

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

    private

    def escape_js(text)
      text.to_s.gsub("\\", "\\\\").gsub("'", "\\'").gsub("\n", "\\n")
    end

    def create_dialog
      dialog = UI::HtmlDialog.new(
        dialog_title: "SU+AI 同步",
        preferences_key: "su_ai_sync_dialog",
        scrollable: true, resizable: true,
        width: 360, height: 620,
        left: 200, top: 200,
        min_width: 340, min_height: 560
      )
      dialog.set_html(html_content)

      dialog.add_action_callback("import") do |_ctx|
        model = Sketchup.active_model
        unless model
          UI.messagebox("请先打开一个 SketchUp 模型")
          next
        end
        effective_extrude = @extrude_enabled ? @extrude_thickness : 0
        Logger.info("Import extrude=#{effective_extrude} (enabled=#{@extrude_enabled})")
        result = Importer.new(model).import(
          @scale, @create_faces, @curve_segs, @import_folder, effective_extrude,
          @z_stack_enabled, @layer_gap
        )
        status = result[:message] || "导入完成"
        dialog.execute_script("document.getElementById('status').textContent = '#{escape_js(status)}';")
      end

      dialog.add_action_callback("reload") do |_ctx|
        dialog.close
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
            dialog.execute_script(
              "document.getElementById('status').textContent = '已坐落 #{moved} 个对象';"
            )
          end
        rescue StandardError => error
          Logger.error("Drop to surface failed: #{error.message}")
          UI.messagebox("落面失败: #{error.message}")
        end
      end

      dialog.add_action_callback("import_texture_aligned") do |_ctx|
        image = ToolActions.import_texture_aligned(Sketchup.active_model)
        if image
          dialog.execute_script(
            "document.getElementById('status').textContent = '贴图已按选择对象对齐';"
          )
        end
      end

      dialog.add_action_callback("browse_folder") do |_ctx|
        browse_folder(dialog)
      end

      dialog.add_action_callback("reset_folder") do |_ctx|
        @import_folder = SU_AI_Sync::EXPORT_DIR
        SU_AI_Sync.save_import_folder(@import_folder)
        dialog.execute_script(
          "document.getElementById('folder_input').value = '#{escape_js("(默认) " + SU_AI_Sync::EXPORT_DIR)}';" +
          "document.getElementById('status').textContent = '已恢复默认文件夹';"
        )
      end

      dialog.add_action_callback("set_folder_path") do |_ctx, path|
        raw = path.to_s.strip
        clean = raw.sub(/^\(默认\)\s*/, "")
        unless File.directory?(clean)
          dialog.execute_script("document.getElementById('status').textContent = '错误：路径不存在或不是文件夹';")
          next
        end
        @import_folder = clean
        SU_AI_Sync.save_import_folder(clean)
        begin
          json_count = Dir.entries(clean).count { |e| e.downcase.end_with?(".json") }
        rescue
          json_count = 0
        end
        safe = escape_js(clean)
        dialog.execute_script("document.getElementById('folder_input').value = '#{safe}';")
        status = json_count > 0 ? "已找到 #{json_count} 个 .json 文件" : "警告：未找到 .json 文件"
        dialog.execute_script("document.getElementById('status').textContent = '#{status}';")
      end


      dialog
    end

    def browse_folder(dialog)
      path = UI.select_directory(
        title: "选择导入文件夹（包含 .json 和图片）",
        directory: @import_folder
      )
      return unless path

      @import_folder = path
      SU_AI_Sync.save_import_folder(path)
      json_count = File.directory?(path) ? Dir.entries(path).count { |entry| entry.downcase.end_with?(".json") } : 0
      dialog.execute_script("document.getElementById('folder_input').value = '#{escape_js(path)}';")
      status = json_count > 0 ? "已找到 #{json_count} 个 .json 文件" : "警告：未找到 .json 文件"
      dialog.execute_script("document.getElementById('status').textContent = '#{status}';")
    rescue => e
      Logger.error("Browse folder: #{e.message}")
      UI.messagebox("文件夹选择失败: #{e.message}")
    end


    def html_content
      scale_selected_1 = @scale == 1.0 ? " selected" : ""
      scale_selected_10 = @scale == 10.0 ? " selected" : ""

      segs_options = [4,6,8,10,12,16,20,24].map { |n|
        sel = @curve_segs == n ? " selected" : ""
        "<option value=\"#{n}\"#{sel}>#{n}</option>"
      }.join("\n          ")

      face_btn_class = @create_faces ? "btn-on" : "btn-off"
      face_btn_text = ""
      extrude_btn_class = @extrude_enabled ? "btn-on" : "btn-off"
      extrude_btn_text = ""
      extrude_row_display = @extrude_enabled ? "flex" : "none"
      z_stack_btn_class = @z_stack_enabled ? "btn-on" : "btn-off"
      z_stack_btn_text = @z_stack_enabled ? "按图层叠放：开" : "按图层叠放：关"
      layer_gap_display = @z_stack_enabled ? "flex" : "none"

      ext_placeholder = @extrude_enabled ? "" : " style=\"display:none\""

      folder_display = if @import_folder == SU_AI_Sync::EXPORT_DIR
        "(默认) " + SU_AI_Sync::EXPORT_DIR
      else
        escape_js(@import_folder)
      end

      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8">
        <style>
        body{font-family:sans-serif;margin:15px;background:#f5f5f5}
        .container{background:white;padding:20px;border-radius:8px}
        h2{margin:0 0 20px 0;color:#333;font-size:18px}
        .btn{width:100%;padding:12px;margin:8px 0;border:none;border-radius:4px;cursor:pointer;font-size:14px}
        .btn-primary{background:#2196F3;color:white}
        .btn-on{background:#2196F3;color:white}
        .btn-off{background:#BDBDBD;color:white}
        .btn-secondary{background:#607D8B;color:white}
        .btn-small{background:#9E9E9E;color:white;padding:8px}
        .toggle-off{background:#BDBDBD;color:white}
        .btn-success{background:#4CAF50;color:white}
        .divider{height:1px;background:#e0e0e0;margin:15px 0}
        .status{padding:10px;background:#E3F2FD;border-radius:4px;font-size:13px}
        .row{display:flex;align-items:center;margin:10px 0;gap:8px}
        .row label{font-size:13px;color:#555;white-space:nowrap}
        .row select{flex:1;padding:6px;border:1px solid #ccc;border-radius:4px;font-size:13px}
        .info{font-size:12px;color:#666;line-height:1.6}
        .folder_row{display:flex;align-items:center;margin:8px 0;gap:6px;flex-wrap:wrap}
        .folder_path{font-size:11px;color:#333;background:#f0f0f0;padding:6px 8px;border-radius:3px;word-break:break-all;flex:1;min-width:0}
        .folder_input{font-size:11px;color:#333;background:#fff;padding:6px 8px;border:1px solid #bbb;border-radius:3px;flex:1;min-width:0;font-family:monospace}
        .folder_input:focus{border-color:#2196F3;outline:none}
        .folder_btn{font-size:12px;padding:5px 10px;border:none;border-radius:3px;cursor:pointer;white-space:nowrap}
        .folder_btn_browse{background:#4CAF50;color:white}
        .folder_btn_reset{background:#f44336;color:white}
        .btn_row{display:flex;gap:8px;margin:8px 0}
        .bottom_bar{display:flex;align-items:center;gap:6px;padding:6px 0;border-top:1px solid #e0e0e0;margin-top:6px}
        </style></head><body><div class="container">
        <h2>SU+AI 同步 v3.6.3</h2>
        <div style="text-align:center;font-size:12px;color:#999;margin:-10px 0 8px 0">作者：段土土</div>
        <button class="btn btn-primary" onclick="doImport()">导入同步数据</button>
        <div class="row"><label>导入比例:</label>
        <select onchange="sketchup.set_scale(this.value)">
          <option value="1.0"#{scale_selected_1}>1:1 (等大)</option>
          <option value="10.0"#{scale_selected_10}>1:10 (放大10倍)</option>
        </select></div>
        <div class="row"><label>曲线精度:</label>
        <select onchange="sketchup.set_segs(this.value)">
          #{segs_options}
        </select></div>
        <div class="btn_row">
          <button class="btn #{face_btn_class}" id="faceBtn" onclick="toggleFace()" style="flex:1">导入封面</button>
          <button class="btn #{extrude_btn_class}" id="extrudeBtn" onclick="toggleExtrude()" style="flex:1">拉成体块</button>
        </div>
        <div class="row" id="extrudeRow" style="display:#{extrude_row_display}"><label>挤出厚度(mm):</label><input type="number" id="extrudeInput" value="#{@extrude_thickness}" min="0.1" step="1" style="width:80px;flex:none;padding:6px;border:1px solid #ccc;border-radius:4px;font-size:13px" onchange="sketchup.set_extrude(this.value)"></div>
        <div class="status" id="status">等待导入...</div>
        <div class="divider"></div>
        <div style="font-size:13px;color:#333;font-weight:bold;margin:8px 0 4px 0">图层与辅助工具</div>
        <button class="btn #{z_stack_btn_class}" id="zStackBtn" onclick="toggleZStack()">#{z_stack_btn_text}</button>
        <div class="row" id="layerGapRow" style="display:#{layer_gap_display}">
          <label>层间距(mm):</label>
          <input type="number" id="layerGapInput" value="#{@layer_gap}" min="0.1" step="1" style="width:80px;flex:none;padding:6px;border:1px solid #ccc;border-radius:4px;font-size:13px" onchange="sketchup.set_layer_gap(this.value)">
        </div>
        <div class="btn_row">
          <button class="btn btn-secondary" onclick="sketchup.drop_to_surface()" style="flex:1">坐落物体表面</button>
          <button class="btn btn-secondary" onclick="sketchup.import_texture_aligned()" style="flex:1">导入贴图对齐</button>
        </div>
        <div class="divider"></div>
        <div style="font-size:13px;color:#333;font-weight:bold;margin:8px 0 4px 0">导入文件夹</div>
        <div class="folder_row">
          <input type="text" class="folder_input" id="folder_input" value="#{folder_display}" placeholder="粘贴路径后按 Enter 确认..." onchange="onFolderChange(this.value)" onkeydown="if(event.key==='Enter')onFolderChange(this.value)">
        </div>
        <div class="folder_row">
          <button class="folder_btn folder_btn_browse" onclick="sketchup.browse_folder()">浏览...</button>
          <button class="folder_btn folder_btn_reset" onclick="sketchup.reset_folder()">恢复默认</button>
        </div>
        <div class="divider"></div>
        <div class="bottom_bar">
          <button class="btn btn-small" onclick="sketchup.reload()" style="flex:1;font-size:12px">热重载插件</button>
          <button class="btn btn-small" onclick="sketchup.open_log()" style="flex:1;font-size:12px">打开日志</button>
          <div class="cb" style="display:flex;align-items:center;gap:4px;flex:1;justify-content:center"><input type="checkbox" id="debugChk" onchange="sketchup.set_debug(this.checked)"><label for="debugChk" style="font-size:12px;color:#555;cursor:pointer">调试模式</label></div>
        </div>
        <div class="divider"></div>
        <div class="info"><b>使用方法：</b><br>1. 在 AI 中选择图形后导出到文件夹<br>2. 选择比例/细分/封面<br>3. 确认文件夹路径正确<br>4. 点击导入</div>
        </div><script>
        function doImport(){document.getElementById('status').textContent='正在导入...';sketchup.import();}
        function toggleFace(){
          var btn = document.getElementById('faceBtn');
          var isOn = btn.classList.contains('btn-on') ? false : true;
          sketchup.set_face(isOn);
          btn.textContent = '导入封面';
          btn.className = 'btn ' + (isOn ? 'btn-on' : 'btn-off');
          if(!isOn){
            var ebtn = document.getElementById('extrudeBtn');
            sketchup.set_extrude_enabled(false);
            ebtn.textContent = '拉成体块';
            ebtn.className = 'btn btn-off';
            document.getElementById('extrudeRow').style.display = 'none';
          }
        }
        function toggleExtrude(){
          var btn = document.getElementById('extrudeBtn');
          var isOn = btn.classList.contains('btn-on') ? false : true;
          if(isOn){
            var fbtn = document.getElementById('faceBtn');
            sketchup.set_face(true);
            fbtn.textContent = '导入封面';
            fbtn.className = 'btn btn-on';
          }
          sketchup.set_extrude_enabled(isOn);
          btn.textContent = '拉成体块';
          btn.className = 'btn ' + (isOn ? 'btn-on' : 'btn-off');
          document.getElementById('extrudeRow').style.display = isOn ? 'flex' : 'none';
          if(isOn)sketchup.set_extrude(document.getElementById('extrudeInput').value);
        }
        function toggleZStack(){
          var button = document.getElementById('zStackBtn');
          var enabled = !button.classList.contains('btn-on');
          button.className = 'btn ' + (enabled ? 'btn-on' : 'btn-off');
          button.textContent = enabled ? '按图层叠放：开' : '按图层叠放：关';
          document.getElementById('layerGapRow').style.display = enabled ? 'flex' : 'none';
          sketchup.set_z_stack(enabled);
          if(enabled)sketchup.set_layer_gap(document.getElementById('layerGapInput').value);
        }
        function onFolderChange(val){if(val.trim())sketchup.set_folder_path(val);}
        </script></body></html>
      HTML
    end
  end
end
