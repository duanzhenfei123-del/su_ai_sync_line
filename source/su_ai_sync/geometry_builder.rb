module SU_AI_Sync
  class GeometryBuilder
    def initialize(model, material_manager)
      @model = model; @material_manager = material_manager
    end

    def build_path(data, parent, scale, create_faces, curve_segs, extrude_thickness = 0)
      vs = data['verticesMM']; return if vs.nil? || vs.length < 2
      curves = data['curves']
      pts = subdivide_path(vs, curves, data['isClosed'], scale, curve_segs)
      closed = data['isClosed'] && pts.length >= 3

      face_created = false
      if create_faces && closed
        clean_pts = []
        pts.each do |pt|
          if clean_pts.empty? || (pt.x - clean_pts.last.x).abs > 0.001 || (pt.y - clean_pts.last.y).abs > 0.001
            clean_pts << Geom::Point3d.new(pt.x, pt.y, 0)
          end
        end
        clean_pts.pop if clean_pts.length > 3 && clean_pts.first.distance(clean_pts.last) < 0.001
        if clean_pts.length >= 3
          begin
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
              if extrude_thickness.to_f > 0
                Logger.info("pushpull: #{extrude_thickness.to_f}mm")
                f.pushpull(-extrude_thickness.mm)
                reset_non_top_materials(parent.entities)
              end
              fc = data['fillColor']
              if fc && !fc.empty?
                if extrude_thickness.to_f > 0
                  top_face = parent.entities.grep(Sketchup::Face).select { |sf| sf.valid? && sf.normal.z > 0.9 }.max_by { |sf| sf.bounds.max.z }
                else
                  top_face = f
                end
                if top_face
                  top_face.material = @material_manager.get_color(fc)
                  top_face.set_attribute('su_ai_sync', 'fillColor', fc)
                end
              end
            end
          rescue => ex
            Logger.info("add_face failed: #{ex.message}")
          end
        end
      end

      parent.entities.add_edges(pts) unless face_created
      parent.entities.add_line(pts.last, pts.first) if closed && !face_created

      sw = data['strokeWidthMM'] || 0
      if sw >= 0.01 && closed
        sp = data['sp'] || 'center'
        case sp
        when 'inside'
          ops = offset_outward(pts, -(sw * scale).mm)
        when 'outside'
          ops = offset_outward(pts, (sw * scale).mm)
        else
          ops = offset_outward(pts, ((sw * scale) / 2.0).mm)
        end
        parent.entities.add_edges(ops)
        parent.entities.add_line(ops.last, ops.first)
      end
    end

    def build_group(data, parent, scale, create_faces, curve_segs, extrude_thickness = 0)
      g = parent.entities.add_group
      g.name = data['name'] || "AI_Group"
      paths = data['paths'] || []
      text_paths = paths.select { |path| path['isTextOutline'] }
      unless text_paths.empty?
        text_paths.group_by { |path| path['textGroupId'] || 'text' }.each_value do |outline_paths|
          build_text_outlines(outline_paths, g, scale, create_faces, curve_segs, extrude_thickness)
        end
        paths = paths.reject { |path| path['isTextOutline'] }
      end

      if paths.empty?
        (data['groups'] || []).each { |group_data| build_group(group_data, g, scale, create_faces, curve_segs, extrude_thickness) }
        return
      end

      if create_faces && paths.any? { |p| p['isImageSurface'] }
        build_image_surface_from_paths(paths, g, scale, curve_segs, extrude_thickness)
      elsif create_faces && paths.length == 2 && paths.all? { |p| p['isClosed'] && (p['strokeWidthMM'] || 0) < 0.01 }
        build_hollow_frame(paths, g, scale, curve_segs, extrude_thickness)
      else
        if extrude_thickness.to_f > 0
          paths.each do |path_data|
            path_group = g.entities.add_group
            build_path(path_data, path_group, scale, create_faces, curve_segs, extrude_thickness)
          end
        else
          paths.each { |pd| build_path(pd, g, scale, create_faces, curve_segs, extrude_thickness) }
          if create_faces
            faces = g.entities.grep(Sketchup::Face).select(&:valid?)
            if faces.length == 2
              a = faces[0]; b = faces[1]
              if a.valid? && b.valid? && a.bounds.contains?(b.bounds)
                b.erase!
              elsif a.valid? && b.valid? && b.bounds.contains?(a.bounds)
                a.erase!
              end
            end
          end
        end
      end
      (data['groups'] || []).each { |gd| build_group(gd, g, scale, create_faces, curve_segs, extrude_thickness) }
    end

    def build_text_outlines(paths, parent, scale, create_faces, curve_segs, extrude_thickness = 0)
      contours = paths.map do |path|
        points = subdivide_path(path['verticesMM'], path['curves'], true, scale, curve_segs)
        next if points.length < 3
        { path: path, points: points, area: polygon_area(points), depth: 0 }
      end.compact
      return if contours.empty?

      contours.each do |contour|
        contour[:depth] = contours.count do |candidate|
          candidate != contour && candidate[:area] > contour[:area] &&
            point_in_polygon?(contour[:points].first, candidate[:points])
        end
      end

      unless create_faces
        contours.each do |contour|
          parent.entities.add_edges(contour[:points])
          parent.entities.add_line(contour[:points].last, contour[:points].first)
        end
        return
      end

      contours.select { |contour| contour[:depth].even? }.each do |outer|
        solid_group = parent.entities.add_group
        solid_group.name = "文字轮廓"
        face = solid_group.entities.add_face(outer[:points])
        next unless face
        face.reverse! if face.normal.z < 0

        contours.select do |hole|
          hole[:depth] == outer[:depth] + 1 && point_in_polygon?(hole[:points].first, outer[:points])
        end.each do |hole|
          hole_face = solid_group.entities.add_face(hole[:points])
          hole_face.erase! if hole_face && hole_face.valid? && hole_face != face
        end

        face = solid_group.entities.grep(Sketchup::Face).select(&:valid?).max_by(&:area)
        next unless face
        fill_color = outer[:path]['fillColor']
        face.material = @material_manager.get_color(fill_color) if fill_color && !fill_color.empty?
        if extrude_thickness.to_f > 0
          face.reverse! if face.normal.z < 0
          face.pushpull(-extrude_thickness.to_f.mm)
          reset_non_top_materials(solid_group.entities)
          if fill_color && !fill_color.empty?
            top_face = solid_group.entities.grep(Sketchup::Face).select { |candidate| candidate.valid? && candidate.normal.z > 0.9 }.max_by { |candidate| candidate.bounds.max.z }
            top_face.material = @material_manager.get_color(fill_color) if top_face
          end
        end
      end
    end

    def soften_edges(entities, angle_degrees = 20)
      threshold = angle_degrees.to_f.degrees
      entities.grep(Sketchup::Edge).each do |edge|
        next unless edge.valid? && edge.faces.length == 2
        next if edge.faces[0].normal.angle_between(edge.faces[1].normal) > threshold
        edge.soft = true
        edge.smooth = true
      end
      entities.grep(Sketchup::Group).each do |group|
        soften_edges(group.entities, angle_degrees) if group.valid?
      end
    end

    def build_image(data, parent, scale, curve_segs = 16)
      p = data['path']; return unless p && File.exist?(p)
      pos = data['position'] || [0,0]; w = data['width'] || 100; h = data['height'] || 100
      mat = @material_manager.get_image_material(p, data['name']||"img")
      x = pos[0].to_f.mm * scale; y = pos[1].to_f.mm * scale
      rect_pts = [ Geom::Point3d.new(x, y, 0), Geom::Point3d.new(x + w.mm * scale, y, 0),
                   Geom::Point3d.new(x + w.mm * scale, y + h.mm * scale, 0), Geom::Point3d.new(x, y + h.mm * scale, 0) ]
      mask_paths = (data['maskPaths'] || []).map do |mask|
        subdivide_path(mask['verticesMM'] || [], mask['curves'], true, scale, curve_segs)
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
      f.set_attribute("su_ai_sync", "imagePath", p)
      f.set_attribute("su_ai_sync", "imageName", data["name"] || "img")
      surface_id = data['surfacePathId'] || data['id'] || ''
      f.set_attribute("su_ai_sync", "surface_key", surface_id) unless surface_id.empty?
      if mat
        f.material = mat
        begin
          uv = [
            rect_pts[0], Geom::Point3d.new(0, 0, 0),
            rect_pts[1], Geom::Point3d.new(1, 0, 0),
            rect_pts[3], Geom::Point3d.new(0, 1, 0)
          ]
          f.position_material(mat, uv, true)
        rescue => ex
          Logger.info("Image UV mapping fallback: #{ex.message}")
        end
      end
    rescue => ex
      Logger.error("Image build failed: #{ex.message}")
    end


    def build_image_surface_from_paths(paths, parent, scale, curve_segs, extrude_thickness = 0)
      contours = paths.map do |path|
        subdivide_path(path['verticesMM'] || [], path['curves'], true, scale, curve_segs)
      end.select { |points| points.length >= 3 }
      return if contours.empty?

      outer = contours.max_by { |points| polygon_area(points) }
      outer_face = parent.entities.add_face(outer)
      unless outer_face
        Logger.error("Compound image surface creation failed")
        return
      end
      outer_face.reverse! if outer_face.normal.z < 0

      contours.reject { |points| points.equal?(outer) }.each do |inner|
        begin
          inner_face = parent.entities.add_face(inner)
          inner_face.erase! if inner_face && inner_face.valid? && inner_face != outer_face
        rescue => ex
          Logger.info("Compound image inner face skipped: #{ex.message}")
        end
      end
      outer_face = parent.entities.grep(Sketchup::Face).select(&:valid?).max_by(&:area)
      return unless outer_face
      surface_key = paths.first['surfaceKey'].to_s
      parent.entities.grep(Sketchup::Face).each do |sf|
        sf.set_attribute('su_ai_sync', 'surface_key', surface_key)
      end

      if extrude_thickness.to_f > 0
        Logger.info("Image surface pushpull: #{extrude_thickness.to_f}mm")
        begin
          outer_face.reverse! if outer_face.normal.z < 0
          outer_face.pushpull(-extrude_thickness.to_f.mm)
        rescue => push_error
          Logger.info("Image surface pushpull skipped: #{push_error.message}")
        end
        reset_non_top_materials(parent.entities)
        all_faces = parent.entities.grep(Sketchup::Face)
        all_faces.each { |sf| sf.delete_attribute('su_ai_sync', 'surface_key') if sf.valid? }
        horizontal_faces = all_faces.select { |sf| sf.valid? && sf.normal.z.abs > 0.9 }
        unless horizontal_faces.empty?
          top_z = horizontal_faces.map { |sf| sf.bounds.max.z }.max
          horizontal_faces.each do |sf|
            sf.set_attribute('su_ai_sync', 'surface_key', surface_key) if (sf.bounds.max.z - top_z).abs < 0.001
          end
        end
      end
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
      uv = [
        rect_pts[0], Geom::Point3d.new(0, 0, 0),
        rect_pts[1], Geom::Point3d.new(1, 0, 0),
        rect_pts[2], Geom::Point3d.new(0, 1, 0)
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

    def faces_in_entities(entities)
      faces = entities.grep(Sketchup::Face)
      entities.grep(Sketchup::Group).each do |group|
        faces.concat(faces_in_entities(group.entities)) if group.valid?
      end
      faces
    end

    def reset_non_top_materials(entities)
      entities.grep(Sketchup::Face).each do |face|
        next unless face.valid?
        next if face.normal.z > 0.9
        face.material = nil
        face.back_material = nil
      end
    end

    private

    def build_hollow_frame(paths, parent, scale, curve_segs, extrude_thickness)
      outlines = paths.map { |path| subdivide_path(path['verticesMM'], path['curves'], path['isClosed'], scale, curve_segs) }
      areas = outlines.map { |points| polygon_area(points) }
      outer_idx = areas[0] > areas[1] ? 0 : 1
      outer_pts = outlines[outer_idx]
      inner_pts = outlines[1 - outer_idx]

      unless point_in_polygon?(inner_pts.first, outer_pts)
        Logger.warn("hollow frame: outlines are not nested, using regular paths")
        paths.each { |path| build_path(path, parent, scale, true, curve_segs, extrude_thickness) }
        return
      end

      outer_face = parent.entities.add_face(outer_pts)
      unless outer_face
        Logger.info("hollow frame: outer face failed")
        return
      end
      outer_face.reverse! if outer_face.normal.z < 0
      outer_face.set_attribute("su_ai_sync", "fillColor", "hollow_frame")
      outer_face.set_attribute("su_ai_sync", "isHollowFrame", true)

      inner_face = parent.entities.add_face(inner_pts)
      inner_face.erase! if inner_face && inner_face.valid? && inner_face != outer_face

      ring_face = parent.entities.grep(Sketchup::Face).select(&:valid?).max_by(&:area)
      unless ring_face
        Logger.warn("hollow frame: ring face missing after inner face removal")
        return
      end
      ring_face.reverse! if ring_face.normal.z < 0

      frame_color = paths.map { |path| path['fillColor'] }.find { |color| color && !color.empty? }
      if frame_color
        ring_face.material = @material_manager.get_color(frame_color)
        ring_face.set_attribute("su_ai_sync", "fillColor", frame_color)
      end

      if extrude_thickness.to_f > 0
        Logger.info("hollow frame: pushpull #{extrude_thickness.to_f}mm")
        ring_face.pushpull(-extrude_thickness.mm)
        reset_non_top_materials(parent.entities)
        if frame_color
          top_face = parent.entities.grep(Sketchup::Face).select { |face| face.valid? && face.normal.z > 0.9 }.max_by { |face| face.bounds.max.z }
          top_face.material = @material_manager.get_color(frame_color) if top_face
        end
      end
    end

    def point_in_polygon?(point, polygon)
      inside = false
      previous = polygon.length - 1
      polygon.each_with_index do |current_point, current|
        previous_point = polygon[previous]
        crosses = (current_point.y > point.y) != (previous_point.y > point.y)
        if crosses
          x_intersection = (previous_point.x - current_point.x) * (point.y - current_point.y) /
                           (previous_point.y - current_point.y) + current_point.x
          inside = !inside if point.x < x_intersection
        end
        previous = current
      end
      inside
    end

    def polygon_area(pts)
      n = pts.length
      return 0 if n < 3
      area = 0
      n.times do |i|
        j = (i + 1) % n
        area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
      end
      area.abs / 2.0
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

    def subdivide_path(anchors, curves, closed, scale, detail)
      return [] unless anchors && anchors.length >= 2

      points = [[anchors[0][0].to_f, anchors[0][1].to_f]]
      segment_count = closed ? anchors.length : anchors.length - 1
      tolerance = [[0.5 / [detail.to_i, 4].max, 0.01].max, 0.15].min

      segment_count.times do |index|
        next_index = (index + 1) % anchors.length
        start_point = [anchors[index][0].to_f, anchors[index][1].to_f]
        end_point = [anchors[next_index][0].to_f, anchors[next_index][1].to_f]
        curve = curves && curves[index]
        control_1 = curve && (curve['c1'] || curve[0])
        control_2 = curve && (curve['c2'] || curve[1])

        if control_1 && control_2
          flatten_cubic(start_point, control_1.map(&:to_f), control_2.map(&:to_f), end_point, tolerance, 0, points)
        else
          points << end_point
        end
      end

      points.pop if closed && points.length > 1 && points.first == points.last
      points.each_with_object([]) do |point, result|
        model_point = Geom::Point3d.new(point[0].mm * scale, point[1].mm * scale, 0)
        result << model_point if result.empty? || result.last.distance(model_point) > 0.000001
      end
    end

    def flatten_cubic(start_point, control_1, control_2, end_point, tolerance, depth, result)
      if depth >= 10 || (point_line_distance(control_1, start_point, end_point) <= tolerance &&
                         point_line_distance(control_2, start_point, end_point) <= tolerance)
        result << end_point
        return
      end

      p01 = midpoint(start_point, control_1)
      p12 = midpoint(control_1, control_2)
      p23 = midpoint(control_2, end_point)
      p012 = midpoint(p01, p12)
      p123 = midpoint(p12, p23)
      center = midpoint(p012, p123)
      flatten_cubic(start_point, p01, p012, center, tolerance, depth + 1, result)
      flatten_cubic(center, p123, p23, end_point, tolerance, depth + 1, result)
    end

    def midpoint(first, second)
      [(first[0] + second[0]) / 2.0, (first[1] + second[1]) / 2.0]
    end

    def point_line_distance(point, line_start, line_end)
      delta_x = line_end[0] - line_start[0]
      delta_y = line_end[1] - line_start[1]
      length = Math.sqrt(delta_x * delta_x + delta_y * delta_y)
      return Math.hypot(point[0] - line_start[0], point[1] - line_start[1]) if length < 0.000001

      ((delta_y * point[0] - delta_x * point[1] + line_end[0] * line_start[1] -
        line_end[1] * line_start[0]).abs / length)
    end
  end
end
