module SU_AI_Sync
  class HotReloader
    PLUGIN_DIR = File.join(__dir__, "..").freeze

    def reload!
      Logger.info("=== Hot reload ===")
      begin
        load File.expand_path("su_ai_sync.rb", PLUGIN_DIR)
        SU_AI_Sync.instance_variable_get(:@ui_manager)&.close
        SU_AI_Sync.instance_variable_set(:@ui_manager, nil)
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
