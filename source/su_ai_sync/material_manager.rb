module SU_AI_Sync
  class MaterialManager
    def initialize
      @materials = Sketchup.active_model.materials
      @cache = {}
    end

    def get_color(hex)
      normalized = hex.to_s.delete('#').upcase
      return nil unless normalized.length == 6
      return nil if normalized == 'FFFFFF'
      cache_key = "Sync_#{normalized}"
      return @cache[cache_key] if @cache[cache_key]
      existing = @materials[cache_key]
      if existing
        @cache[cache_key] = existing
        return existing
      end
      begin
        r = normalized[0..1].to_i(16)
        g = normalized[2..3].to_i(16)
        b = normalized[4..5].to_i(16)
        material = @materials.add(cache_key)
        material.color = Sketchup::Color.new(r, g, b)
        @cache[cache_key] = material
        material
      rescue => e
        Logger.error("Material: #{e.message}")
        nil
      end
    end

    def get_image_material(image_path, name)
      normalized_path = File.expand_path(image_path.to_s).tr("\\", "/").downcase
      identity = "#{normalized_path}|#{name}"
      path_hash = identity.each_byte.reduce(2_166_136_261) do |hash, byte|
        ((hash ^ byte) * 16_777_619) & 0xffffffff
      end
      safe_name = name.to_s.gsub(/[^\p{L}\p{N}_.-]+/u, "_")[0, 40]
      safe_name = "Image" if safe_name.empty?
      cache_key = "Sync_Image_#{safe_name}_#{path_hash.to_s(16).rjust(8, '0')}"
      return @cache[cache_key] if @cache[cache_key]
      existing = @materials[cache_key]
      if existing
        @cache[cache_key] = existing
        return existing
      end
      begin
        material = @materials.add(cache_key)
        material.texture = image_path if File.exist?(image_path)
        @cache[cache_key] = material
        material
      rescue => e
        Logger.error("Image material: #{e.message}")
        nil
      end
    end
  end
end
