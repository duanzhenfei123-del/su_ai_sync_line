module SU_AI_Sync
  class Importer
    def initialize(model)
      @model = model
      @material_manager = MaterialManager.new
      @geometry_builder = GeometryBuilder.new(model, @material_manager)
    end

    def import(scale = 1.0, create_faces = true, curve_segs = 12, import_folder = nil, extrude_thickness = 0)
      label = create_faces ? "faces on" : "lines only"
      extrude_label = extrude_thickness > 0 ? ", extrude:#{extrude_thickness}mm" : ""
      Logger.info("=== Import (scale:#{scale}, #{label}#{extrude_label}, segs:#{curve_segs}) ===")

      import_path = import_folder || SU_AI_Sync.import_folder
      Logger.info("Import folder: #{import_path}")

      json_file = locate_json(import_path)

      unless json_file
        UI.messagebox("未找到同步数据文件 (.json)\n路径: #{import_path}\n\n请先在 AI 中导出数据到该文件夹。")
        Logger.error("No JSON found in: #{import_path}")
        return { success: false, message: "No data" }
      end

      Logger.info("Found JSON: #{json_file}")

      begin
        data = JSON.parse(File.read(json_file, encoding: "UTF-8"))
        Logger.info("JSON parsed: version #{data["version"] || "unknown"}")

        effective_scale = (data["scale"] || 1.0) * scale

        paths = normalize_paths(data, import_path)
        groups = data["groups"] || []
        images = normalize_images(data, import_path)

        Logger.info("Paths: #{paths.length}, Groups: #{groups.length}, Images: #{images.length}")

        @model.start_operation("SU+AI Sync Import", true)
        begin
          temp_group = @model.entities.add_group

          regular_paths = paths.reject { |path_data| path_data['isTextOutline'] }
          text_paths = paths.select { |path_data| path_data['isTextOutline'] }

          regular_paths.each do |path_data|
            path_group = temp_group.entities.add_group
            @geometry_builder.build_path(path_data, path_group, effective_scale, create_faces, curve_segs, extrude_thickness)
          end

          text_paths.group_by { |path_data| path_data['textGroupId'] || 'text' }.each_value do |outline_paths|
            text_group = temp_group.entities.add_group
            text_group.name = "AI文字"
            @geometry_builder.build_text_outlines(outline_paths, text_group, effective_scale, create_faces, curve_segs, extrude_thickness)
          end

          groups.each do |group_data|
            @geometry_builder.build_group(group_data, temp_group, effective_scale, create_faces, curve_segs, extrude_thickness)
          end

          images.each do |image_data|
            if image_data['surfacePathId'] && !image_data['surfacePathId'].empty?
              @geometry_builder.apply_image_to_existing_face(image_data, temp_group, effective_scale)
            else
              image_group = temp_group.entities.add_group
              @geometry_builder.build_image(image_data, image_group, effective_scale, curve_segs)
            end
          end

          @geometry_builder.soften_edges(temp_group.entities, 20) if extrude_thickness.to_f > 0

          align_bottom_left_to_origin(temp_group)
          exploded = temp_group.explode
          if exploded && exploded.length > 0
            final_group = @model.entities.add_group(exploded)
            final_group.name = "AI导入 (#{paths.length}p #{groups.length}g)"
          end

          @model.commit_operation

          Logger.info("Import done: #{paths.length} paths, #{groups.length} groups, #{images.length} images")
          { success: true, paths: paths.length, groups: groups.length, images: images.length }
        rescue => e
          @model.abort_operation
          raise e
        end
      rescue JSON::ParserError => e
        UI.messagebox("JSON 解析错误: #{e.message}")
        Logger.error("JSON parse: #{e.message}")
        { success: false, message: e.message }
      rescue => e
        UI.messagebox("导入失败: #{e.message}")
        Logger.error("Import: #{e.message}")
        { success: false, message: e.message }
      end
    end

    private

    def align_bottom_left_to_origin(group)
      bounds = group.bounds
      min = bounds.min
      if min.x != 0 || min.y != 0
        translation = Geom::Transformation.new([-min.x, -min.y, 0])
        group.entities.transform_entities(translation, group.entities.to_a)
        Logger.info("Group aligned: bottom-left (#{min.x}, #{min.y}) moved to (0, 0)")
      end
    end

    def locate_json(directory)
      Logger.info("locate_json: scanning #{directory}")
      return nil unless File.directory?(directory)
      latest = File.join(directory, "latest_sync.json")
      return latest if File.exist?(latest)
      Dir.entries(directory).each do |entry|
        next unless entry.downcase.end_with?(".json")
        candidate = File.join(directory, entry)
        return candidate if File.file?(candidate)
      end
      Logger.info("locate_json: no json found")
      nil
    end

    def normalize_paths(data, directory)
      raw = data["paths"] || data["p"] || []
      raw.map { |item| normalize_path(item) }
    end

    def normalize_path(item)
      return item if item["verticesMM"]
      geometry = item["g"]
      return item unless geometry && geometry["p"]

      anchor_points = geometry["p"].map { |pt| pt["a"] }
      has_bezier = geometry["cv"].to_i > 0
      curves = if has_bezier
        geometry["p"].each_cons(2).map do |from, to|
          next unless from && to
          { "c1" => from["r"], "c2" => to["l"] }
        end.compact
      else
        []
      end

      stroke_rgb = item["s"]
      fill_rgb = item["f"]
      {
        "verticesMM" => anchor_points,
        "curves" => curves,
        "isClosed" => geometry["c"] == 1,
        "fillColor" => fill_rgb.is_a?(Array) ? fill_rgb.map { |c| c.to_s(16).rjust(2, "0") }.join : nil,
        "strokeColor" => stroke_rgb.is_a?(Array) ? stroke_rgb.map { |c| c.to_s(16).rjust(2, "0") }.join : nil,
        "strokeWidthMM" => item["sw"] || 0
      }
    end

    def normalize_images(data, directory)
      raw = data["images"] || data["im"] || []
      raw.map do |item|
        if item["f"]
          {
            "path" => File.join(directory, item["f"]),
            "position" => [item["ox"] || 0, item["oy"] || 0],
            "width" => item["w"] || 100,
            "height" => item["h"] || 100,
            "name" => item["f"],
            "maskPaths" => item["maskPaths"] || [],
            "surfacePathId" => item["surfacePathId"] || ""
          }
        else
          item
        end
      end
    end
  end
end
