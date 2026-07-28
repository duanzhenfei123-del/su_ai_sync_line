module SU_AI_Sync
  class MaterialManager
    def initialize
      @materials = Sketchup.active_model.materials
      @cache = {}
    end

    def get_color(hex)
      return nil unless hex && hex.length == 6
      cache_key = "Sync_#{hex}"
      return @cache[cache_key] if @cache[cache_key]
      existing = @materials[cache_key]
      if existing
        @cache[cache_key] = existing
        return existing
      end
      begin
        r = hex[0..1].to_i(16)
        g = hex[2..3].to_i(16)
        b = hex[4..5].to_i(16)
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
      cache_key = "Sync_Image_#{name}"
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
