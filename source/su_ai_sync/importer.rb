module SU_AI_Sync
  class Importer
    def initialize(model)
      @model = model
      @material_manager = MaterialManager.new
      @geometry_builder = GeometryBuilder.new(model, @material_manager)
    end

    def import(scale = 1.0, create_faces = true, curve_segs = 12,
               import_folder = nil, extrude_thickness = 0,
               z_stack = false, layer_gap = 10.0)
      Logger.reset_for_import
      label = create_faces ? "faces on" : "lines only"
      extrude_label = extrude_thickness > 0 ? ", extrude:#{extrude_thickness}mm" : ""
      z_stack_label = z_stack ? ", zstack:#{LayerLayout.normalize_gap(layer_gap)}mm" : ""
      Logger.info("=== Import (scale:#{scale}, #{label}#{extrude_label}#{z_stack_label}, segs:#{curve_segs}) ===")

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
        validate_data!(data)
        Logger.info("JSON parsed: version #{data["version"] || "unknown"}")

        effective_scale = (data["scale"] || 1.0) * scale

        paths = normalize_paths(data, import_path)
        groups = (data["groups"] || []).map { |group| normalize_group(group) }
        images = normalize_images(data, import_path)
        repaired = snap_path_endpoints!(paths, effective_scale)
        groups.each { |group| repaired += snap_group_endpoints!(group, effective_scale) }
        Logger.info("Endpoint repairs: #{repaired}") if repaired > 0

        Logger.info("Paths: #{paths.length}, Groups: #{groups.length}, Images: #{images.length}")

        @geometry_builder.soften_enabled = extrude_thickness.to_f > 0
        @model.start_operation("SU+AI Sync Import", true)
        begin
          temp_group = @model.entities.add_group

          if z_stack
            items = LayerLayout.path_units(paths) + groups.map do |group|
              { 'unitType' => 'group', 'zIndex' => group['zIndex'], 'group' => group }
            end
            ordered = LayerLayout.order(items)
            ordered.each_with_index do |item, index|
              layer_group = temp_group.entities.add_group
              build_layer_item(
                item, layer_group, effective_scale, create_faces,
                curve_segs, extrude_thickness
              )
              offset = LayerLayout.offset_mm(index, ordered.length, layer_gap)
              unless offset.zero?
                layer_group.transform!(
                  Geom::Transformation.translation([0, 0, offset.mm])
                )
              end
            end
          else
            build_flat_import(
              paths, groups, temp_group, effective_scale, create_faces,
              curve_segs, extrude_thickness
            )
          end

          build_images(images, temp_group, effective_scale, curve_segs)

          align_bottom_left_to_origin(temp_group)
          temp_group.name = "AI导入 (#{paths.length}p #{groups.length}g)"

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

    def validate_data!(data)
      raise ArgumentError, '同步数据根节点必须是对象' unless data.is_a?(Hash)

      raw_version = data.fetch('schemaVersion', 1)
      begin
        version = Integer(raw_version)
      rescue ArgumentError, TypeError
        raise ArgumentError, "无效的数据协议版本: #{raw_version.inspect}"
      end
      raise ArgumentError, "不支持的数据协议版本: #{version}" unless [1, 2].include?(version)

      %w[paths groups images].each do |key|
        raise ArgumentError, "#{key} 必须是数组" if data.key?(key) && !data[key].is_a?(Array)
      end
      version
    end

    def text_path?(path)
      path['isTextOutline'] ||
        !path['textGroupKey'].to_s.empty? ||
        !path['textGroupId'].to_s.empty?
    end

    def text_group_key(path)
      [path['textGroupKey'], path['textGroupId']]
        .find { |value| !value.to_s.empty? } || 'text'
    end

    def build_flat_import(paths, groups, parent, scale, create_faces, curve_segs, extrude_thickness)
      text_paths = paths.select { |path| text_path?(path) }
      regular_paths = paths - text_paths

      text_paths
        .group_by { |path| text_group_key(path) }
        .each_value do |members|
          text_group = parent.entities.add_group
          text_group.name = 'AI文字'
          @geometry_builder.build_compound_path(
            members, text_group, scale, create_faces, curve_segs, extrude_thickness
          )
        end

      compound_paths = regular_paths.select { |path| !path['compoundKey'].to_s.empty? }
      compound_paths.group_by { |path| path['compoundKey'].to_s }.each_value do |members|
        path_group = parent.entities.add_group
        @geometry_builder.build_compound_path(
          members, path_group, scale, create_faces, curve_segs, extrude_thickness
        )
      end

      (regular_paths - compound_paths).each do |path|
        path_group = parent.entities.add_group
        @geometry_builder.build_path(
          path, path_group, scale, create_faces, curve_segs, extrude_thickness
        )
      end

      groups.each do |group|
        @geometry_builder.build_group(
          group, parent, scale, create_faces, curve_segs, extrude_thickness
        )
      end
    end

    def build_layer_item(item, parent, scale, create_faces, curve_segs, extrude_thickness)
      case item['unitType']
      when 'text'
        parent.name = 'AI文字'
        @geometry_builder.build_compound_path(
          item['paths'], parent, scale, create_faces, curve_segs, extrude_thickness
        )
      when 'compound'
        @geometry_builder.build_compound_path(
          item['paths'], parent, scale, create_faces, curve_segs, extrude_thickness
        )
      when 'path'
        @geometry_builder.build_path(
          item['paths'].first, parent, scale, create_faces, curve_segs, extrude_thickness
        )
      when 'group'
        @geometry_builder.build_group(
          item['group'], parent, scale, create_faces, curve_segs, extrude_thickness
        )
      else
        raise ArgumentError, "Unknown layer unit: #{item['unitType'].inspect}"
      end
    end

    def build_images(images, parent, scale, curve_segs)
      images.each do |image|
        if !image['surfacePathId'].to_s.empty?
          @geometry_builder.apply_image_to_existing_face(image, parent, scale)
        else
          image_group = parent.entities.add_group
          @geometry_builder.build_image(image, image_group, scale, curve_segs)
        end
      end
    end

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

      return 0 if endpoints.length < 2

      buckets = Hash.new { |hash, key| hash[key] = [] }
      endpoints.each_with_index do |endpoint, index|
        buckets[[(endpoint[2] / tolerance).floor, (endpoint[3] / tolerance).floor]] << index
      end

      parents = (0...endpoints.length).to_a
      find_root = lambda do |index|
        root = index
        root = parents[root] while parents[root] != root
        while parents[index] != index
          parent = parents[index]
          parents[index] = root
          index = parent
        end
        root
      end
      merge = lambda do |left, right|
        left_root = find_root.call(left)
        right_root = find_root.call(right)
        parents[right_root] = left_root unless left_root == right_root
      end

      # ponytail: a fully dense tolerance cell still compares pairs; add a spatial index only if dense artwork is measured slow.
      endpoints.each_with_index do |endpoint, index|
        cell_x = (endpoint[2] / tolerance).floor
        cell_y = (endpoint[3] / tolerance).floor
        (-1..1).each do |offset_x|
          (-1..1).each do |offset_y|
            buckets[[cell_x + offset_x, cell_y + offset_y]].each do |other_index|
              next if other_index <= index

              other = endpoints[other_index]
              dx = endpoint[2] - other[2]
              dy = endpoint[3] - other[3]
              merge.call(index, other_index) if dx * dx + dy * dy <= tolerance_squared
            end
          end
        end
      end

      clusters = Hash.new { |hash, key| hash[key] = [] }
      endpoints.each_with_index { |endpoint, index| clusters[find_root.call(index)] << endpoint }
      repaired = 0
      clusters.each_value do |cluster|
        next if cluster.length < 2

        x = cluster.sum { |entry| entry[2] } / cluster.length
        y = cluster.sum { |entry| entry[3] } / cluster.length
        path_counts = {}
        cluster.each do |entry|
          entry[0]['verticesMM'][entry[1]] = [x, y]
          path_counts[entry[0].object_id] ||= [entry[0], 0]
          path_counts[entry[0].object_id][1] += 1
        end
        path_counts.each_value { |path, count| path['isClosed'] = true if count > 1 }
        repaired += cluster.length - 1
      end
      repaired
    end

    def align_bottom_left_to_origin(group)
      bounds = group.bounds
      min = bounds.min
      if min.x != 0 || min.y != 0
        translation = Geom::Transformation.translation([-min.x, -min.y, 0])
        group.transform!(translation)
        Logger.info("Group aligned: bottom-left (#{min.x}, #{min.y}) moved to (0, 0)")
      end
    end

    def locate_json(directory)
      Logger.info("locate_json: scanning #{directory}")
      return nil unless File.directory?(directory)
      latest = File.join(directory, "latest_sync.json")
      return latest if File.exist?(latest)
      legacy = Dir.children(directory)
                  .select { |entry| entry.match?(/^sync_.*\.json$/i) }
                  .map { |entry| File.join(directory, entry) }
                  .select { |candidate| File.file?(candidate) }
                  .max_by { |candidate| File.mtime(candidate) }
      return legacy if legacy
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

    def normalize_group(group)
      raise ArgumentError, 'group 必须是对象' unless group.is_a?(Hash)

      normalized = group.dup
      normalized['paths'] = (group['paths'] || []).map { |path| normalize_path(path) }
      normalized['groups'] = (group['groups'] || []).map { |child| normalize_group(child) }
      normalized
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
