require "sketchup.rb"
require "json"
require "fileutils"

module SU_AI_Sync
  VERSION = "3.7.3"
  IS_WINDOWS = Sketchup.platform == :platform_win
  USER_HOME = (ENV["USERPROFILE"] || ENV["HOME"] || Dir.home).freeze
  APP_DATA_DIR = if IS_WINDOWS
                   ENV["LOCALAPPDATA"] || File.join(USER_HOME, "AppData", "Local")
                 else
                   File.join(USER_HOME, "Library", "Application Support")
                 end.freeze
  EXPORT_DIR = File.join(USER_HOME, "Desktop", "ai-export").freeze
  CONFIG_DIR = File.join(APP_DATA_DIR, "su_ai_sync", "config").freeze
  LOG_FILE = File.join(APP_DATA_DIR, "su_ai_sync", "logs", "su_sync.log").freeze
  FOLDER_CONFIG = File.join(CONFIG_DIR, "import_folder.txt").freeze

  def self.import_folder
    if File.exist?(FOLDER_CONFIG)
      saved = File.read(FOLDER_CONFIG, encoding: "UTF-8").strip
      return saved unless saved.empty?
    end
    EXPORT_DIR
  end

  def self.save_import_folder(path)
    FileUtils.mkdir_p(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)
    File.write(FOLDER_CONFIG, path, encoding: "UTF-8")
  end

  base = __dir__
  load File.join(base, "su_ai_sync", "logger.rb")
  Logger.info("Logger loaded")
  load File.join(base, "su_ai_sync", "geometry_math.rb")
  Logger.info("GeometryMath loaded")
  load File.join(base, "su_ai_sync", "material_manager.rb")
  Logger.info("MaterialManager loaded")
  load File.join(base, "su_ai_sync", "geometry_builder.rb")
  Logger.info("GeometryBuilder loaded")
  load File.join(base, "su_ai_sync", "layer_layout.rb")
  Logger.info("LayerLayout loaded")
  load File.join(base, "su_ai_sync", "importer.rb")
  Logger.info("Importer loaded")
  load File.join(base, "su_ai_sync", "tool_actions.rb")
  Logger.info("ToolActions loaded")
  load File.join(base, "su_ai_sync", "hot_reloader.rb")
  Logger.info("HotReloader loaded")
  load File.join(base, "su_ai_sync", "ui_manager.rb")
  Logger.info("UIManager loaded")

  def self.show_dialog
    @ui_manager ||= UI_Manager.new
    @ui_manager.show
  end

  def self.quick_import
    model = Sketchup.active_model
    unless model
      UI.messagebox("请先打开一个 SketchUp 模型")
      return
    end

    scale = Sketchup.read_default("su_ai_sync", "scale", 1.0).to_f
    create_faces = Sketchup.read_default("su_ai_sync", "faces", 1).to_i == 1
    curve_segs = Sketchup.read_default("su_ai_sync", "segs", 12).to_i
    extrude_enabled = Sketchup.read_default("su_ai_sync", "extrude_enabled", 0).to_i == 1
    extrude_thickness = extrude_enabled ? Sketchup.read_default("su_ai_sync", "extrude_thickness", 10.0).to_f : 0
    z_stack = Sketchup.read_default("su_ai_sync", "z_stack", 0).to_i == 1
    layer_gap = LayerLayout.normalize_gap(
      Sketchup.read_default("su_ai_sync", "layer_gap", 10.0)
    )

    Logger.info("=== Quick import (scale:#{scale}, faces:#{create_faces}, segs:#{curve_segs}, extrude:#{extrude_thickness}, zstack:#{z_stack ? layer_gap : '-'}) ===")

    importer = Importer.new(model)
    result = importer.import(
      scale, create_faces, curve_segs, import_folder, extrude_thickness,
      z_stack, layer_gap
    )

    if result[:success]
      parts = []
      parts << "#{result[:paths]} 路径" if result[:paths] && result[:paths] > 0
      parts << "#{result[:groups]} 组" if result[:groups] && result[:groups] > 0
      parts << "#{result[:images]} 图片" if result[:images] && result[:images] > 0
      msg = "导入完成: #{parts.join(", ")}" unless parts.empty?
      UI.messagebox(msg || "导入完成")
      Logger.info("Quick import success: #{msg}")
    else
      Logger.warn("Quick import failed: #{result[:message]}")
    end
  end

  unless file_loaded?(__FILE__)
    Logger.info("Registering menu and toolbar")

    menu = UI.menu("Plugins")
    submenu = menu.add_submenu("SU+AI 同步")
    submenu.add_item("直接导入") { quick_import }
    submenu.add_item("控制面板") { show_dialog }

    toolbar = UI::Toolbar.new("SU+AI 同步")
    cmd_import = UI::Command.new("直接导入") { quick_import }
    cmd_import.small_icon = File.join(__dir__, "su_ai_sync", "icon_import.png")
    cmd_import.large_icon = File.join(__dir__, "su_ai_sync", "icon_import.png")
    cmd_import.tooltip = "直接导入"
    cmd_import.status_bar_text = "使用默认设置从 AI 导入数据"
    toolbar.add_item(cmd_import)

    cmd_panel = UI::Command.new("控制面板") { show_dialog }
    cmd_panel.small_icon = File.join(__dir__, "su_ai_sync", "icon_panel.png")
    cmd_panel.large_icon = File.join(__dir__, "su_ai_sync", "icon_panel.png")
    cmd_panel.tooltip = "控制面板"
    cmd_panel.status_bar_text = "打开 SU+AI 同步控制面板"
    toolbar.add_item(cmd_panel)

    toolbar.show

    file_loaded(__FILE__)
    Logger.info("Plugin loaded v#{VERSION}")
  end
end
