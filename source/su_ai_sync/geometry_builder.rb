module SU_AI_Sync
  class GeometryBuilder
    POINT_TOLERANCE = 0.001
    attr_writer :soften_enabled

    def initialize(model, material_manager)
      @model = model; @material_manager = material_manager
      @soften_enabled = false
    end

    def build_path(data, parent, scale, create_faces, curve_segs, extrude_thickness = 0, material_mode = 'all')
      vs = data['verticesMM']; return if vs.nil? || vs.length < 2
      curves = data['curves']
      closed_value = data['isClosed']
      requested_closed = closed_value == true || closed_value == 1 || closed_value.to_s == '1'
      pts = clean_curve_points(subdivide_path(vs, curves, requested_closed, scale, curve_segs), requested_closed)
      closed = requested_closed && pts.length >= 3
      return if pts.length < 2

      face_created = false
      if create_faces && closed && !data['isClippingMask']
        clean_pts = pts
        if clean_pts.length >= 3
          if fast_prism_eligible?(data, extrude_thickness)
            block_faces = build_fast_prism(parent.entities, clean_pts, extrude_thickness.to_f.mm)
            if block_faces && !block_faces.empty?
              face_created = true
              orient_front_faces_if_needed(parent.entities, block_faces)
              soften_edges_by_angle(parent.entities, 25.0, block_faces) if @soften_enabled
              fc = data['fillColor']
              if material_mode != 'default' && fc && !fc.empty?
                material = @material_manager.get_color(fc)
                top_z = block_faces.map { |face| face.bounds.max.z }.max
                block_faces.each do |face|
                  next unless face.valid? && face.normal.z > 0.9
                  face.material = material if (face.bounds.max.z - top_z).abs < 0.001
                end
              end
              weld_prism_boundaries(parent.entities, block_faces)
            end
          end

          unless face_created
            begin
              faces_before = parent.entities.grep(Sketchup::Face).dup
              begin
                f = parent.entities.add_face(clean_pts)
              rescue => ex2
                Logger.info("add_face fallback: trying original vertices")
                begin
                  orig_pts = (data['verticesMM'] || []).map { |v| Geom::Point3d.new(v[0].to_f.mm * scale, v[1].to_f.mm * scale, 0) }
                  orig_pts.pop if orig_pts.length > 3 && orig_pts.first.distance(orig_pts.last) < 0.001
                  f = parent.entities.add_face(orig_pts) if orig_pts.length >= 3
                rescue
                  f = nil
                end
              end
              if f
                f.reverse! if f.normal.z < 0
                if data['isImageSurface']
                  f.set_attribute('su_ai_sync', 'surface_key', data['surfaceKey'].to_s)
                end
                face_created = true
                block_faces = nil
                if extrude_thickness.to_f > 0
                  Logger.info("pushpull: #{extrude_thickness.to_f}mm")
                  f.pushpull(extrude_thickness.mm)
                  existing_faces = {}
                  faces_before.each { |face| existing_faces[face] = true }
                  block_faces = parent.entities.grep(Sketchup::Face).select do |face|
                    face.valid? && !existing_faces[face]
                  end
                  orient_front_faces_if_needed(parent.entities, block_faces)
                  soften_edges_by_angle(parent.entities, 25.0, block_faces) if @soften_enabled
                  if data['isImageSurface']
                    block_faces.each do |block_face|
                      block_face.delete_attribute('su_ai_sync', 'surface_key')
                    end
                    horizontal_faces = block_faces.select { |block_face| block_face.normal.z.abs > 0.9 }
                    unless horizontal_faces.empty?
                      top_z = horizontal_faces.map { |block_face| block_face.bounds.max.z }.max
                      horizontal_faces.each do |block_face|
                        if (block_face.bounds.max.z - top_z).abs < 0.001
                          block_face.set_attribute('su_ai_sync', 'surface_key', data['surfaceKey'].to_s)
                        end
                      end
                    end
                  end
                end
                fc = data['fillColor']
                if material_mode != 'default' && fc && !fc.empty?
                  color_face = nil
                  if extrude_thickness.to_f > 0
                    new_faces = block_faces.select do |candidate|
                      candidate.valid? && !faces_before.include?(candidate) && candidate.normal.z > 0.9
                    end
                    color_face = new_faces.max_by { |candidate| candidate.bounds.max.z }
                  else
                    color_face = f if f.valid?
                  end
                  color_face.material = @material_manager.get_color(fc) if color_face
                end
                weld_horizontal_face_boundaries(parent.entities, block_faces || [f])
              end
            rescue => ex
              Logger.info("add_face failed: #{ex.message}")
            end
          end
        end
      end

      add_welded_curve(parent.entities, pts, closed) unless face_created

      sw = data['strokeWidthMM'] || 0
      stroke_color = data['strokeColor'].to_s
      if sw >= 0.01 && closed && !stroke_color.empty?
        sp = data['sp'] || 'center'
        case sp
        when 'inside'
          ops = offset_outward(pts, -(sw * scale).mm)
        when 'outside'
          ops = offset_outward(pts, (sw * scale).mm)
        else
          ops = offset_outward(pts, ((sw * scale) / 2.0).mm)
        end
        add_welded_curve(parent.entities, ops, true)
      end
    end

    def build_group(data, parent, scale, create_faces, curve_segs, extrude_thickness = 0, material_mode = 'all')
      g = parent.entities.add_group
      g.name = data['name'] || "AI_Group"
      paths = data['paths'] || []
      child_groups = data['groups'] || []
      if create_faces && paths.any? { |p| p['isImageSurface'] }
        build_image_surface_from_paths(paths, g, scale, curve_segs, extrude_thickness)
      else
        text_paths = paths.select { |path| !path['textGroupKey'].to_s.empty? }
        text_paths.group_by { |path| path['textGroupKey'].to_s }.each do |key, members|
          text_group = g.entities.add_group
          text_group.name = "AI_Text_#{key.sub(/^text_/, '')}"
          build_compound_path(members, text_group, scale, create_faces, curve_segs, extrude_thickness, material_mode)
        end
        build_path_collection(paths - text_paths, g, scale, create_faces, curve_segs, extrude_thickness, material_mode)
      end
      child_groups.each { |gd| build_group(gd, g, scale, create_faces, curve_segs, extrude_thickness, material_mode) }
    end

    def build_path_collection(paths, parent, scale, create_faces, curve_segs, extrude_thickness = 0, material_mode = 'all')
      if create_faces && hollow_frame_paths?(paths)
        build_hollow_frame(paths, parent, scale, curve_segs, extrude_thickness)
        return
      end

      # 部分 AI 转曲文字位于普通组内，导出时没有 textGroupId/compoundKey；
      # 仍可由“同色、多闭合轮廓、且存在嵌套”稳定识别为带孔的复合字形。
      if create_faces && inferred_compound_paths?(paths)
        build_compound_path(paths, parent, scale, create_faces, curve_segs, extrude_thickness, material_mode)
        return
      end

      compound_paths = paths.select { |path| !path['compoundKey'].to_s.empty? }
      compound_paths.group_by { |path| path['compoundKey'].to_s }.each_value do |members|
        build_compound_path(members, parent, scale, create_faces, curve_segs, extrude_thickness, material_mode)
      end
      prepare_colored_paths(paths - compound_paths).each do |path|
        build_path(path, parent, scale, create_faces, curve_segs, extrude_thickness, material_mode)
      end
    end

    def build_compound_path(paths, parent, scale, create_faces, curve_segs, extrude_thickness = 0, material_mode = 'all')
      unless create_faces
        paths.each { |path| build_path(path, parent, scale, false, curve_segs, 0, material_mode) }
        return
      end

      contours = paths.map do |path|
        points = clean_curve_points(
          subdivide_path(path['verticesMM'] || [], path['curves'], true, scale, curve_segs),
          true
        )
        points.length >= 3 ? [path, points] : nil
      end.compact
      return if contours.empty?

      areas = {}
      bounds = {}
      contours.each { |entry| areas[entry.object_id] = polygon_area(entry[1]) }
      contours.each { |entry| bounds[entry.object_id] = GeometryMath.bounds(entry[1]) }
      ordered = contours.sort_by { |entry| -areas[entry.object_id] }
      outer_entries = []
      inner_entries = []
      ordered.each do |entry|
        points = entry[1]
        depth = ordered.count do |other|
          next false if other.equal?(entry)
          next false unless areas[other.object_id] > areas[entry.object_id]
          next false unless GeometryMath.bounds_contain_bounds?(bounds[other.object_id], bounds[entry.object_id])
          point_in_points_polygon(points.first, other[1])
        end
        (depth.odd? ? inner_entries : outer_entries) << entry
      end

      outer_faces = outer_entries.map do |entry|
        begin
          face = parent.entities.add_face(entry[1])
          face.reverse! if face && face.valid? && face.normal.z < 0
          face
        rescue => error
          Logger.info("Compound outer face skipped: #{error.message}")
          nil
        end
      end.compact

      inner_entries.each do |entry|
        begin
          hole_face = parent.entities.add_face(entry[1])
          if hole_face && hole_face.valid?
            # 使用 entities.erase_entities 而非 Face#erase!，确保在复杂文字
            # 轮廓中删除的是新生成的内区面，保留其边界作为孔洞边界。
            parent.entities.erase_entities(hole_face)
            Logger.info("Compound hole cut")
          else
            Logger.info("Compound hole face was not created")
          end
        rescue => error
          Logger.info("Compound hole skipped: #{error.message}")
        end
      end

      material = nil
      fill_color = paths.map { |path| path['fillColor'].to_s }.find { |color| !color.empty? }
      material = @material_manager.get_color(fill_color) if material_mode != 'default' && fill_color
      extruded_faces = []
      # 切出孔洞后 SketchUp 可能会替换原 Face 对象；重新读取当前有效面，
      # 否则封面与体块的顶面都拿不到原来的颜色。
      planar_faces = parent.entities.grep(Sketchup::Face).select(&:valid?)
      planar_faces.each do |face|
        next unless face.valid?
        face.material = material if material
        if extrude_thickness.to_f > 0
          faces_before = parent.entities.grep(Sketchup::Face).dup
          face.pushpull(extrude_thickness.to_f.mm)
          existing_faces = {}
          faces_before.each { |candidate| existing_faces[candidate] = true }
          new_faces = parent.entities.grep(Sketchup::Face).select do |candidate|
            candidate.valid? && !existing_faces[candidate]
          end
          extruded_faces.concat(new_faces)
          if material
            top_face = ([face] + new_faces).select { |candidate| candidate.valid? && candidate.normal.z > 0.9 }
                                .max_by { |candidate| candidate.bounds.max.z }
            top_face.material = material if top_face
          end
        end
      rescue => error
        Logger.info("Compound pushpull skipped: #{error.message}")
      end

      compound_faces = extrude_thickness.to_f > 0 ? extruded_faces.uniq : planar_faces.select(&:valid?)
      if extrude_thickness.to_f > 0
        orient_front_faces_if_needed(parent.entities, compound_faces)
        soften_edges_by_angle(parent.entities, 25.0, compound_faces) if @soften_enabled
        # 朝向校正会交换正反面材质；在校正完成后重新给最高的水平顶面着色。
        if material
          all_faces = parent.entities.grep(Sketchup::Face).select(&:valid?)
          top_z = all_faces.map { |face| face.bounds.max.z }.max
          all_faces.each do |face|
            next unless face.normal.z > 0.9
            face.material = material if (face.bounds.max.z - top_z).abs < 0.001
          end
        end
      end
      weld_horizontal_face_boundaries(parent.entities, compound_faces)
      Logger.info("Compound path: #{outer_entries.length} outer, #{inner_entries.length} hole(s)")
    end

    def build_image(data, parent, scale, curve_segs = 16)
      p = data['path']
      unless p && File.exist?(p)
        Logger.error("Image file missing: #{p || '(empty path)'}")
        return
      end
      pos = data['position'] || [0,0]; w = data['width'] || 100; h = data['height'] || 100
      mat = @material_manager.get_image_material(p, data['name']||"img")
      x = pos[0].to_f.mm * scale; y = pos[1].to_f.mm * scale
      rect_pts = [ Geom::Point3d.new(x, y, 0), Geom::Point3d.new(x + w.mm * scale, y, 0),
                   Geom::Point3d.new(x + w.mm * scale, y + h.mm * scale, 0), Geom::Point3d.new(x, y + h.mm * scale, 0) ]
      mask_paths = (data['maskPaths'] || []).map do |mask|
        clean_curve_points(
          subdivide_path(mask['verticesMM'] || [], mask['curves'], true, scale, curve_segs),
          true
        )
      end.select { |points| points.length >= 3 }

      if mask_paths.empty?
        face_pts = rect_pts
        inner_paths = []
      else
        face_pts = mask_paths.max_by { |points| polygon_area(points) }
        inner_paths = mask_paths.reject { |points| points.equal?(face_pts) }
      end

      f = parent.entities.add_face(face_pts)
      unless f
        Logger.error("Image face creation failed: #{data['name'] || p}")
        return
      end
      f.reverse! if f.normal.z < 0
      inner_paths.each do |inner_pts|
        begin
          hole_face = parent.entities.add_face(inner_pts)
          hole_face.erase! if hole_face && hole_face.valid?
        rescue => hole_error
          Logger.info("Image mask hole skipped: #{hole_error.message}")
        end
      end
      if mat
        f.material = mat
        begin
          crop = normalized_uv_crop(data['uvCrop'])
          uv = [
            rect_pts[0], Geom::Point3d.new(crop[0], crop[1], 0),
            rect_pts[1], Geom::Point3d.new(crop[2], crop[1], 0),
            rect_pts[3], Geom::Point3d.new(crop[0], crop[3], 0)
          ]
          f.position_material(mat, uv, true)
        rescue => ex
          Logger.info("Image UV mapping fallback: #{ex.message}")
        end
      end
    rescue => ex
      Logger.error("Image build failed: #{ex.message}")
    end

    def apply_image_to_existing_face(data, parent, scale)
      p = data['path']
      unless p && File.exist?(p)
        Logger.error("Image file missing: #{p || '(empty path)'}")
        return false
      end

      pos = data['position'] || [0, 0]
      w = (data['width'] || 100).to_f
      h = (data['height'] || 100).to_f
      x = pos[0].to_f.mm * scale
      y = pos[1].to_f.mm * scale
      target_cx = x + w.mm * scale / 2.0
      target_cy = y + h.mm * scale / 2.0

      surface_key = data['surfacePathId'].to_s
      candidates = faces_in_entities(parent.entities).select do |candidate|
        candidate.get_attribute('su_ai_sync', 'surface_key', '') == surface_key
      end
      if candidates.empty?
        Logger.error("Existing image surface not found: #{data['surfacePathId']}")
        return false
      end

      mat = @material_manager.get_image_material(p, data['name'] || "img")
      return false unless mat
      rect_pts = [
        Geom::Point3d.new(x, y, 0),
        Geom::Point3d.new(x + w.mm * scale, y, 0),
        Geom::Point3d.new(x, y + h.mm * scale, 0)
      ]
      crop = normalized_uv_crop(data['uvCrop'])
      uv = [
        rect_pts[0], Geom::Point3d.new(crop[0], crop[1], 0),
        rect_pts[1], Geom::Point3d.new(crop[2], crop[1], 0),
        rect_pts[2], Geom::Point3d.new(crop[0], crop[3], 0)
      ]
      candidates.each do |face|
        face.reverse! if face.normal.z < 0
        face.material = mat
        face.position_material(mat, uv, true)
      end
      Logger.info("Image material applied to #{candidates.length} existing face(s): #{data['surfacePathId']}")
      true
    rescue => ex
      Logger.error("Apply image to existing face failed: #{ex.message}")
      false
    end

    private

    def normalized_uv_crop(value)
      crop = value.is_a?(Array) && value.length >= 4 ? value.map(&:to_f) : [0.0, 0.0, 1.0, 1.0]
      crop[0] = [[crop[0], 0.0].max, 1.0].min
      crop[1] = [[crop[1], 0.0].max, 1.0].min
      crop[2] = [[crop[2], crop[0] + 0.0001].max, 1.0].min
      crop[3] = [[crop[3], crop[1] + 0.0001].max, 1.0].min
      crop
    end

    def prepare_colored_paths(paths)
      areas = {}
      bounds = {}
      paths.each { |path| areas[path.object_id] = raw_polygon_area(path['verticesMM'] || []) }
      paths.each { |path| bounds[path.object_id] = GeometryMath.bounds(path['verticesMM'] || []) }
      paths.sort_by { |path| -areas[path.object_id] }.map do |path|
        prepared = path.dup
        fill = path['fillColor'].to_s
        vertices = path['verticesMM'] || []
        if !fill.empty? && vertices.length >= 3
          sample = vertices[0]
          depth = paths.count do |other|
            next false if other.equal?(path)
            next false unless other['fillColor'].to_s == fill
            next false unless areas[other.object_id] > areas[path.object_id]
            next false unless GeometryMath.bounds_contain_bounds?(bounds[other.object_id], bounds[path.object_id])
            point_in_raw_polygon(sample, other['verticesMM'] || [])
          end
          prepared['fillColor'] = '' if depth.odd?
        end
        prepared
      end
    end

    def soften_edges_by_angle(entities, maximum_angle_degrees, faces = nil)
      maximum_angle = maximum_angle_degrees.to_f.degrees
      softened = 0
      edges = if faces
                faces.flat_map(&:edges).select(&:valid?).uniq
              else
                entities.grep(Sketchup::Edge)
              end
      edges.each do |edge|
        next unless edge.valid? && edge.faces.length == 2
        face_a, face_b = edge.faces
        next unless face_a.valid? && face_b.valid?
        angle = face_a.normal.angle_between(face_b.normal)
        next unless angle < maximum_angle
        edge.soft = true
        edge.smooth = true
        softened += 1
      end
      Logger.info("Softened edges (<#{maximum_angle_degrees}deg): #{softened}") if softened > 0
      softened
    rescue => error
      Logger.info("Edge softening skipped: #{error.message}")
      0
    end

    def orient_front_faces(entities, faces = nil)
      remaining = (faces || entities.grep(Sketchup::Face)).select(&:valid?)
      oriented = 0

      until remaining.empty?
        component = connected_faces(remaining.first)
        remaining -= component
        component_lookup = {}
        component.each { |face| component_lookup[face] = true }
        horizontal = component.select { |face| face.normal.z.abs > 0.9 }
        seed = horizontal.empty? ? component.first : horizontal.max_by { |face| face.bounds.center.z }
        seed.reverse! if !horizontal.empty? && seed.normal.z < 0

        visited = { seed => true }
        queue = [seed]
        until queue.empty?
          face = queue.shift
          face.edges.each do |edge|
            edge.faces.each do |neighbor|
              next if neighbor == face || !component_lookup[neighbor] || visited[neighbor]
              face_direction = face_edge_direction(face, edge)
              neighbor_direction = face_edge_direction(neighbor, edge)
              neighbor.reverse! if face_direction != 0 && face_direction == neighbor_direction
              visited[neighbor] = true
              queue << neighbor
            end
          end
        end
        oriented += visited.length
      end
      Logger.info("Front faces oriented: #{oriented}") if oriented > 0
      oriented
    rescue => error
      Logger.info("Face orientation skipped: #{error.message}")
      0
    end

    def connected_faces(seed)
      visited = { seed => true }
      queue = [seed]
      until queue.empty?
        face = queue.shift
        face.edges.each do |edge|
          edge.faces.each do |neighbor|
            next if visited[neighbor] || !neighbor.valid?
            visited[neighbor] = true
            queue << neighbor
          end
        end
      end
      visited.keys
    end

    def face_edge_direction(face, edge)
      face.loops.each do |loop|
        vertices = loop.vertices
        vertices.length.times do |index|
          current = vertices[index]
          following = vertices[(index + 1) % vertices.length]
          return 1 if current == edge.start && following == edge.end
          return -1 if current == edge.end && following == edge.start
        end
      end
      0
    end

    def raw_polygon_area(vertices)
      GeometryMath.polygon_area(vertices)
    end

    def point_in_raw_polygon(point, vertices)
      GeometryMath.point_in_polygon?(point, vertices)
    end

    def build_image_surface_from_paths(paths, parent, scale, curve_segs, extrude_thickness = 0)
      contours = paths.map do |path|
        clean_curve_points(
          subdivide_path(path['verticesMM'] || [], path['curves'], true, scale, curve_segs),
          true
        )
      end.select { |points| points.length >= 3 }
      return if contours.empty?

      areas = {}
      bounds = {}
      contours.each { |points| areas[points.object_id] = polygon_area(points) }
      contours.each { |points| bounds[points.object_id] = GeometryMath.bounds(points) }
      ordered = contours.sort_by { |points| -areas[points.object_id] }
      outer_contours = []
      inner_contours = []
      ordered.each do |points|
        depth = ordered.count do |other|
          next false if other.equal?(points)
          next false unless areas[other.object_id] > areas[points.object_id]
          next false unless GeometryMath.bounds_contain_bounds?(bounds[other.object_id], bounds[points.object_id])
          point_in_points_polygon(points.first, other)
        end
        (depth.odd? ? inner_contours : outer_contours) << points
      end

      outer_faces = []
      outer_contours.each do |outer|
        begin
          outer_face = parent.entities.add_face(outer)
          next unless outer_face && outer_face.valid?
          outer_face.reverse! if outer_face.normal.z < 0
          outer_faces << outer_face
        rescue => ex
          Logger.info("Compound image outer face skipped: #{ex.message}")
        end
      end
      if outer_faces.empty?
        Logger.error("Compound image surface creation failed")
        return
      end

      inner_contours.each do |inner|
        begin
          inner_face = parent.entities.add_face(inner)
          inner_face.erase! if inner_face && inner_face.valid?
        rescue => ex
          Logger.info("Compound image hole skipped: #{ex.message}")
        end
      end
      surface_key = paths.first['surfaceKey'].to_s
      outer_faces.each do |surface_face|
        surface_face.set_attribute('su_ai_sync', 'surface_key', surface_key)
      end

      if extrude_thickness.to_f > 0
        Logger.info("Image surface pushpull: #{extrude_thickness.to_f}mm")
        faces_before = parent.entities.grep(Sketchup::Face).dup
        planar_faces = parent.entities.grep(Sketchup::Face).select do |surface_face|
          surface_face.valid? &&
            surface_face.get_attribute('su_ai_sync', 'surface_key', '') == surface_key
        end
        planar_faces.each do |surface_face|
          begin
            surface_face.pushpull(extrude_thickness.to_f.mm) if surface_face.valid?
          rescue => push_error
            Logger.info("Image surface pushpull skipped: #{push_error.message}")
          end
        end

        existing_faces = {}
        faces_before.each { |face| existing_faces[face] = true }
        all_faces = parent.entities.grep(Sketchup::Face).select do |face|
          face.valid? && (!existing_faces[face] || planar_faces.include?(face))
        end
        orient_front_faces_if_needed(parent.entities, all_faces)
        soften_edges_by_angle(parent.entities, 25.0, all_faces) if @soften_enabled
        all_faces.each do |surface_face|
          surface_face.delete_attribute('su_ai_sync', 'surface_key') if surface_face.valid?
        end
        horizontal_faces = all_faces.select do |surface_face|
          surface_face.valid? && surface_face.normal.z.abs > 0.9
        end
        unless horizontal_faces.empty?
          top_z = horizontal_faces.map { |surface_face| surface_face.bounds.max.z }.max
          horizontal_faces.each do |surface_face|
            if (surface_face.bounds.max.z - top_z).abs < 0.001
              surface_face.set_attribute('su_ai_sync', 'surface_key', surface_key)
            end
          end
        end
      end
    end

    def faces_in_entities(entities)
      faces = entities.grep(Sketchup::Face)
      entities.grep(Sketchup::Group).each do |group|
        faces.concat(faces_in_entities(group.entities)) if group.valid?
      end
      faces
    end

    def build_hollow_frame(paths, parent, scale, curve_segs, extrude_thickness)
      segs = paths.map do |pd|
        clean_curve_points(
          subdivide_path(pd['verticesMM'], pd['curves'], pd['isClosed'], scale, curve_segs),
          pd['isClosed']
        )
      end
      areas = segs.map { |pts| polygon_area(pts) }
      outer_idx = areas[0] > areas[1] ? 0 : 1
      outer_pts = segs[outer_idx]
      inner_pts = segs[1 - outer_idx]

      outer_face = parent.entities.add_face(outer_pts)
      unless outer_face
        Logger.info("hollow frame: outer face failed")
        return
      end
      outer_face.reverse! if outer_face.normal.z < 0

      frame_color = paths[outer_idx]['fillColor'].to_s
      frame_material = @material_manager.get_color(frame_color) unless frame_color.empty?
      outer_face.material = frame_material if frame_material

      inner_face = parent.entities.add_face(inner_pts)
      # 内轮廓产生的面必须被删除，边界才会成为真正的镂空孔洞；此前这里
      # 保留了内面，导致“导入封面”把描边线框的中心也封住。
      parent.entities.erase_entities(inner_face) if inner_face && inner_face.valid?

      if extrude_thickness.to_f > 0
        Logger.info("hollow frame: pushpull #{extrude_thickness.to_f}mm")
        faces_before = parent.entities.grep(Sketchup::Face).dup
        outer_face.pushpull(extrude_thickness.mm)
        parent.entities.grep(Sketchup::Face).each do |f|
          next unless f.valid?
          next if f == outer_face
          if f.edges.all? { |e| e.faces.length >= 3 }
            Logger.info("  erasing cap face: normal.z=#{f.normal.z.round(3)}, edges=#{f.edges.length}")
            f.erase!
          end
        end
        existing_faces = {}
        faces_before.each { |face| existing_faces[face] = true }
        frame_faces = parent.entities.grep(Sketchup::Face).select do |face|
          face.valid? && (!existing_faces[face] || face == outer_face)
        end
        orient_front_faces_if_needed(parent.entities, frame_faces)
        if frame_material
          top_face = frame_faces.select { |face| face.normal.z > 0.9 }
                                .max_by { |face| face.bounds.max.z }
          top_face.material = frame_material if top_face
        end
        soften_edges_by_angle(parent.entities, 25.0, frame_faces) if @soften_enabled
      end
    end

    def hollow_frame_paths?(paths)
      return false unless paths.length == 2
      return false if paths.any? { |path| path['isClippingMask'] }
      return false unless paths.all? do |path|
        closed = path['isClosed'] == true || path['isClosed'] == 1 || path['isClosed'].to_s == '1'
        closed && (path['verticesMM'] || []).length >= 3 && (path['strokeWidthMM'] || 0).to_f < 0.01
      end

      # 展开描边的两条路径颜色相同（或均无颜色）；不同颜色的两个普通图形
      # 不能误判为线框。
      colors = paths.map { |path| path['fillColor'].to_s }.uniq
      colors.length == 1
    end

    def inferred_compound_paths?(paths)
      return false if paths.length < 3
      return false unless paths.all? do |path|
        closed = path['isClosed'] == true || path['isClosed'] == 1 || path['isClosed'].to_s == '1'
        closed && (path['verticesMM'] || []).length >= 3 && path['strokeWidthMM'].to_f < 0.01
      end
      colors = paths.map { |path| path['fillColor'].to_s }.uniq
      return false unless colors.length == 1 && !colors.first.empty?

      paths.any? do |inner|
        inner_vertices = inner['verticesMM'] || []
        inner_area = raw_polygon_area(inner_vertices)
        inner_bounds = GeometryMath.bounds(inner_vertices)
        paths.any? do |outer|
          next false if outer.equal?(inner)
          outer_vertices = outer['verticesMM'] || []
          next false unless raw_polygon_area(outer_vertices) > inner_area
          next false unless GeometryMath.bounds_contain_bounds?(GeometryMath.bounds(outer_vertices), inner_bounds)
          point_in_raw_polygon(inner_vertices.first, outer_vertices)
        end
      end
    end

    def point_in_points_polygon(point, vertices)
      GeometryMath.point_in_polygon?(point, vertices)
    end

    def polygon_area(pts)
      GeometryMath.polygon_area(pts)
    end

    def offset_outward(pts, distance)
      n = pts.length
      return pts.map { |p| Geom::Point3d.new(p.x, p.y, 0) } if n < 3

      area = 0
      n.times do |i|
        j = (i + 1) % n
        area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
      end
      winding = area > 0 ? 1 : -1

      result = []
      n.times do |i|
        prev = pts[(i - 1) % n]
        curr = pts[i]
        nxt = pts[(i + 1) % n]

        d1x = curr.x - prev.x; d1y = curr.y - prev.y
        d2x = nxt.x - curr.x; d2y = nxt.y - curr.y
        len1 = Math.sqrt(d1x * d1x + d1y * d1y)
        len2 = Math.sqrt(d2x * d2x + d2y * d2y)

        if len1 < 0.001 || len2 < 0.001
          result << Geom::Point3d.new(curr.x, curr.y, 0)
          next
        end

        n1x = winding * (-d1y / len1); n1y = winding * (d1x / len1)
        n2x = winding * (-d2y / len2); n2y = winding * (d2x / len2)

        a1x = prev.x + n1x * distance; a1y = prev.y + n1y * distance
        a2x = curr.x + n2x * distance; a2y = curr.y + n2y * distance

        cross_d = d1x * d2y - d1y * d2x
        if cross_d.abs < 0.001
          result << Geom::Point3d.new(curr.x + n1x * distance, curr.y + n1y * distance, 0)
        else
          diffx = a2x - a1x; diffy = a2y - a1y
          t1 = (diffx * d2y - diffy * d2x) / cross_d
          result << Geom::Point3d.new(a1x + t1 * d1x, a1y + t1 * d1y, 0)
        end
      end
      result
    end

    def clean_curve_points(points, closed)
      cleaned = []
      points.each do |point|
        point = Geom::Point3d.new(point.x, point.y, 0)
        cleaned << point if cleaned.empty? || cleaned.last.distance(point) > POINT_TOLERANCE
      end
      if closed && cleaned.length > 2 && cleaned.first.distance(cleaned.last) <= POINT_TOLERANCE
        cleaned.pop
      end
      cleaned
    end

    def add_welded_curve(entities, points, closed)
      clean = clean_curve_points(points, closed)
      return [] if clean.length < 2

      curve_points = clean.dup
      curve_points << clean.first if closed && clean.length >= 3
      edges = Array(entities.add_curve(curve_points)).select { |edge| edge && edge.valid? }
      if edges.length > 1 && entities.respond_to?(:weld)
        entities.weld(edges) unless edges.first.curve
      end
      edges
    rescue => error
      Logger.info("add_curve fallback: #{error.message}")
      edges = Array(entities.add_edges(clean))
      edges << entities.add_line(clean.last, clean.first) if closed && clean.length >= 3
      edges.compact!
      entities.weld(edges) if edges.length > 1 && entities.respond_to?(:weld)
      edges
    end

    def weld_horizontal_face_boundaries(entities, faces = nil)
      return unless entities.respond_to?(:weld)
      (faces || entities.grep(Sketchup::Face)).each do |face|
        next unless face.valid? && face.normal.z.abs > 0.9
        edges = face.outer_loop.edges.select(&:valid?)
        entities.weld(edges) if edges.length > 1
      rescue => error
        Logger.info("face weld skipped: #{error.message}")
      end
    end

    public

    def weld_loose_edges(entities)
      return unless entities.respond_to?(:weld)
      edges = entities.grep(Sketchup::Edge).select { |edge| edge.valid? && edge.faces.empty? }
      entities.weld(edges) if edges.length > 1
    rescue => error
      Logger.info("loose-edge weld skipped: #{error.message}")
    end

    private

    def fast_prism_eligible?(data, extrude_thickness)
      extrude_thickness.to_f > 0 &&
        !data['isImageSurface'] &&
        data['compoundKey'].to_s.empty?
    end

    def build_fast_prism(entities, points, height)
      return nil unless entities.respond_to?(:add_faces_from_mesh)
      return nil if points.length < 3 || height.to_f <= 0

      base = signed_polygon_area(points) < 0 ? points.reverse : points.dup
      triangles = Geom.tesselate(base)
      return nil if triangles.nil? || triangles.length < 3 || triangles.length % 3 != 0

      before_lookup = {}
      entities.to_a.each { |entity| before_lookup[entity] = true }
      mesh = Geom::PolygonMesh.new(base.length * 2, triangles.length / 3 * 2 + base.length)
      bottom_indices = base.map { |point| mesh.add_point(point) }
      top_indices = base.map do |point|
        mesh.add_point(Geom::Point3d.new(point.x, point.y, height))
      end
      point_lookup = {}
      base.each_with_index { |point, index| point_lookup[point_key(point)] = index }

      triangles.each_slice(3) do |triangle|
        indexes = triangle.map { |point| point_lookup[point_key(point)] }
        if indexes.any?(&:nil?)
          raise ArgumentError, 'Tessellation returned an unknown boundary point'
        end
        indexes.reverse! if signed_polygon_area(triangle) < 0
        mesh.add_polygon(indexes.map { |index| top_indices[index] })
        mesh.add_polygon(indexes.reverse.map { |index| bottom_indices[index] })
      end

      base.length.times do |index|
        following = (index + 1) % base.length
        mesh.add_polygon([
          bottom_indices[index],
          bottom_indices[following],
          top_indices[following],
          top_indices[index]
        ])
      end

      face_count = entities.add_faces_from_mesh(mesh, 0)
      created_entities = entities.to_a.reject { |entity| before_lookup[entity] }
      created_faces = created_entities.grep(Sketchup::Face).select(&:valid?)
      horizontal = created_faces.select { |face| face.normal.z.abs > 0.9 }
      side_faces = created_faces.select { |face| face.normal.z.abs <= 0.9 }
      if face_count.to_i <= 0 || horizontal.length < 2 || side_faces.empty?
        entities.erase_entities(created_entities.select(&:valid?)) unless created_entities.empty?
        Logger.info('Fast prism validation failed; falling back to pushpull')
        return nil
      end

      Logger.info("Fast prism: #{base.length} boundary points, #{created_faces.length} faces")
      created_faces
    rescue => error
      begin
        created_entities ||= []
        entities.erase_entities(created_entities.select(&:valid?)) unless created_entities.empty?
      rescue
        nil
      end
      Logger.info("Fast prism skipped: #{error.message}")
      nil
    end

    def signed_polygon_area(points)
      area = 0.0
      points.length.times do |index|
        following = (index + 1) % points.length
        area += points[index].x * points[following].y
        area -= points[following].x * points[index].y
      end
      area / 2.0
    end

    def point_key(point)
      [point.x.to_f.round(8), point.y.to_f.round(8)]
    end

    def weld_prism_boundaries(entities, faces)
      return unless entities.respond_to?(:weld)
      horizontal = Array(faces).select { |face| face.valid? && face.normal.z.abs > 0.9 }
      boundary_edges = horizontal.flat_map(&:edges).select do |edge|
        edge.valid? && edge.faces.any? { |face| face.valid? && face.normal.z.abs <= 0.9 }
      end.uniq
      boundary_edges.group_by { |edge| edge.start.position.z.round(6) }.each_value do |edges|
        entities.weld(edges) if edges.length > 1
      end
    rescue => error
      Logger.info("Fast prism weld skipped: #{error.message}")
    end

    def orient_front_faces_if_needed(entities, faces)
      valid_faces = Array(faces).select(&:valid?)
      return 0 if valid_faces.empty?

      # pushpull 与网格快速拉伸在个别文字轮廓上可能留下反向侧面；
      # 每次都从最高的水平面开始传播方向，避免只在顶面反向时才修复。
      orient_front_faces(entities, valid_faces)
    end

    def subdivide_path(anchors, curves, closed, scale, segs)
      n = anchors.length
      return anchors.map { |v| Geom::Point3d.new(v[0].to_f.mm * scale, v[1].to_f.mm * scale, 0) } if curves.nil? || curves.empty?

      result = []
      seg_count = closed ? n : n - 1
      maximum_steps = [[segs.to_i, 1].max, 128].min

      seg_count.times do |i|
        j = (i + 1) % n
        p0 = anchors[i]; p3 = anchors[j]
        pt0 = Geom::Point3d.new(p0[0].to_f.mm * scale, p0[1].to_f.mm * scale, 0)
        result << pt0

        curve = curves[i]
        if curve && curve['c1'] && curve['c2']
          c1 = curve['c1']; c2 = curve['c2']
          p1 = [c1[0].to_f, c1[1].to_f]; p2 = [c2[0].to_f, c2[1].to_f]
          segment_steps = adaptive_curve_steps(p0, p1, p2, p3, scale, maximum_steps)

          (1..segment_steps).each do |s|
            t = s.to_f / segment_steps
            u = 1.0 - t
            bx = p0[0]*u*u*u + 3*p1[0]*u*u*t + 3*p2[0]*u*t*t + p3[0]*t*t*t
            by = p0[1]*u*u*u + 3*p1[1]*u*u*t + 3*p2[1]*u*t*t + p3[1]*t*t*t
            result << Geom::Point3d.new(bx.mm * scale, by.mm * scale, 0)
          end
        end
      end

      result << Geom::Point3d.new(anchors.last[0].to_f.mm * scale, anchors.last[1].to_f.mm * scale, 0) unless closed
      result
    end

    def adaptive_curve_steps(p0, p1, p2, p3, scale, maximum_steps)
      return 1 if maximum_steps <= 1

      chord = point_distance_2d(p0, p3)
      control_length = point_distance_2d(p0, p1) +
                       point_distance_2d(p1, p2) +
                       point_distance_2d(p2, p3)
      flatness = [point_line_distance_2d(p1, p0, p3),
                  point_line_distance_2d(p2, p0, p3),
                  control_length - chord].max

      # Keep about 0.15 mm maximum deviation in the imported model.
      # The panel value remains the quality ceiling instead of being applied
      # to every tiny Bezier segment.
      source_tolerance = 0.15 / [scale.to_f.abs, 0.001].max
      estimated = (2.0 * Math.sqrt([flatness, 0.0].max / source_tolerance)).ceil
      [[estimated, 1].max, maximum_steps].min
    end

    def point_distance_2d(a, b)
      dx = b[0].to_f - a[0].to_f
      dy = b[1].to_f - a[1].to_f
      Math.sqrt(dx * dx + dy * dy)
    end

    def point_line_distance_2d(point, line_start, line_end)
      dx = line_end[0].to_f - line_start[0].to_f
      dy = line_end[1].to_f - line_start[1].to_f
      denominator = Math.sqrt(dx * dx + dy * dy)
      return point_distance_2d(point, line_start) if denominator < 1.0e-9

      numerator = (dy * point[0].to_f - dx * point[1].to_f +
                   line_end[0].to_f * line_start[1].to_f -
                   line_end[1].to_f * line_start[0].to_f).abs
      numerator / denominator
    end
  end
end
