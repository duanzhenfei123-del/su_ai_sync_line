module SU_AI_Sync
  class Importer
    def initialize(model)
      @model = model
      @material_manager = MaterialManager.new
      @geometry_builder = GeometryBuilder.new(model, @material_manager)
    end

    def import(scale = 1.0, create_faces = true, curve_segs = 12, import_folder = nil, extrude_thickness = 0)
      Logger.reset_for_import
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
        repaired = snap_path_endpoints!(paths, effective_scale)
        groups.each { |group| repaired += snap_group_endpoints!(group, effective_scale) }
        Logger.info("Endpoint repairs: #{repaired}") if repaired > 0

        Logger.info("Paths: #{paths.length}, Groups: #{groups.length}, Images: #{images.length}")

        @model.start_operation("SU+AI Sync Import", true)
        begin
          temp_group = @model.entities.add_group

          text_paths = paths.select do |path_data|
            path_data['isTextOutline'] || !path_data['textGroupKey'].to_s.empty?
          end
          regular_paths = paths - text_paths

          text_paths.group_by { |path_data| path_data['textGroupKey'] || path_data['textGroupId'] || 'text' }.each_value do |outline_paths|
            text_group = temp_group.entities.add_group
            text_group.name = "AI文字"
            # 一个文字组可能包含多个字形外轮廓与内孔；统一按复合路径构建，
            # 让被外轮廓包住的轮廓成为孔洞，而不是再次生成封面。
            @geometry_builder.build_compound_path(outline_paths, text_group, effective_scale, create_faces, curve_segs, extrude_thickness)
          end

          compound_paths = regular_paths.select { |path_data| !path_data['compoundKey'].to_s.empty? }
          compound_paths.group_by { |path_data| path_data['compoundKey'].to_s }.each_value do |members|
            path_group = temp_group.entities.add_group
            @geometry_builder.build_compound_path(members, path_group, effective_scale, create_faces, curve_segs, extrude_thickness)
          end

          (regular_paths - compound_paths).each do |path_data|
            path_group = temp_group.entities.add_group
            @geometry_builder.build_path(path_data, path_group, effective_scale, create_faces, curve_segs, extrude_thickness)
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

    def snap_group_endpoints!(group, scale)
      repaired = snap_path_endpoints!(group['paths'] || [], scale)
      (group['groups'] || []).each { |child| repaired += snap_group_endpoints!(child, scale) }
      repaired
    end

    # 修复导出精度造成的微小断口；容差为最终模型中的 0.05 mm。
    def snap_path_endpoints!(paths, scale)
      tolerance = 0.05 / [scale.to_f.abs, 0.0001].max
      tolerance_squared = tolerance * tolerance
      endpoints = []
      paths.each do |path|
        vertices = path['verticesMM']
        next unless vertices.is_a?(Array) && vertices.length >= 2
        closed = path['isClosed'] == true || path['isClosed'] == 1 || path['isClosed'].to_s == '1'
        next if closed
        endpoints << [path, 0, vertices.first[0].to_f, vertices.first[1].to_f]
        endpoints << [path, vertices.length - 1, vertices.last[0].to_f, vertices.last[1].to_f]
      end
      repaired = 0
      endpoints.each_with_index do |endpoint, index|
        next if endpoint[4]
        cluster = [endpoint]
        endpoints[(index + 1)..-1].to_a.each do |other|
          dx = endpoint[2] - other[2]; dy = endpoint[3] - other[3]
          cluster << other if dx * dx + dy * dy <= tolerance_squared
        end
        next if cluster.length < 2
        x = cluster.sum { |entry| entry[2] } / cluster.length
        y = cluster.sum { |entry| entry[3] } / cluster.length
        counts = Hash.new(0)
        cluster.each do |entry|
          entry[0]['verticesMM'][entry[1]] = [x, y]
          counts[entry[0].object_id] += 1
          entry << true
        end
        counts.each { |path_id, count| paths.find { |path| path.object_id == path_id }['isClosed'] = true if count > 1 }
        repaired += cluster.length - 1
      end
      repaired
    end

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
        points = geometry['p']
        count = geometry['c'] == 1 ? points.length : points.length - 1
        count.times.map do |index|
          from = points[index]; to = points[(index + 1) % points.length]
          { "c1" => from["r"] || from["a"], "c2" => to["l"] || to["a"] }
        end
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
            "uvCrop" => item["uvCrop"] || [0, 0, 1, 1],
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
