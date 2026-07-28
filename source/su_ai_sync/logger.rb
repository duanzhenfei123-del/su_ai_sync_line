module SU_AI_Sync
  module Logger
    @debug_mode = false
    def self.debug_mode=(value); @debug_mode = value; end

    # 清理日志：每次启动时将上次日志备份为 .bak，重新开始记录
    def self.cleanup_on_startup
      return unless File.exist?(LOG_FILE)
      begin
        bak = LOG_FILE.sub(/\.log$/, ".log.bak")
        FileUtils.cp(LOG_FILE, bak)
        File.truncate(LOG_FILE, 0)
      rescue => e
        # 备份失败不影响使用
      end
    end
    def self.log(level, message)
      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      line = "[#{timestamp}] [#{level}] #{message}"
      begin
        dir = File.dirname(LOG_FILE)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        File.write(LOG_FILE, line + "\n", mode: "a", encoding: "UTF-8")
      rescue
      end
      puts line if @debug_mode
    end
    def self.info(msg); log("INFO", msg); end
    def self.warn(msg); log("WARN", msg); end
    def self.error(msg); log("ERROR", msg); end
    def self.debug(msg); log("DEBUG", msg) if @debug_mode; end
  end
end
