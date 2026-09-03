module SU_AI_Sync
  module Logger
    @debug_mode = false
    def self.debug_mode=(value); @debug_mode = value; end

    # 每次导入只保留一份日志，不创建备份或轮转文件。
    def self.reset_for_import
      begin
        [
          LOG_FILE,
          LOG_FILE.sub(/\.log\z/i, ".log.bak"),
          LOG_FILE.sub(/\.log\z/i, ".old.log")
        ].uniq.each { |path| File.delete(path) if File.exist?(path) }
      rescue => error
        puts "[SU+AI Logger] 清理历史日志失败: #{error.message}" if @debug_mode
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
