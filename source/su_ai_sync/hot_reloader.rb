module SU_AI_Sync
  class HotReloader
    PLUGIN_DIR = File.join(__dir__, "..").freeze

    def reload!
      Logger.info("=== Hot reload ===")
      begin
        files = [
          "su_ai_sync/logger.rb",
          "su_ai_sync/geometry_math.rb",
          "su_ai_sync/material_manager.rb",
          "su_ai_sync/geometry_builder.rb",
          "su_ai_sync/importer.rb",
          "su_ai_sync/hot_reloader.rb",
          "su_ai_sync/ui_manager.rb",
          "su_ai_sync.rb"
        ]
        files.each do |f|
          path = File.join(PLUGIN_DIR, f)
          load path if File.exist?(path)
        end
        Logger.info("Hot reload done")
        UI.messagebox("Plugin reloaded!")
        true
      rescue => e
        Logger.error("Reload: #{e.message}")
        UI.messagebox("Reload failed: #{e.message}")
        false
      end
    end
  end
end
