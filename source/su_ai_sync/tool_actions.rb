module SU_AI_Sync
  class ImportPlacementTool
    SNAP_RADIUS = 8

    def initialize(model, preview_edges = [], &finished)
      @model = model
      @preview_edges = preview_edges
      @finished = finished
      @point = Sketchup::InputPoint.new
    end

    def activate
      Sketchup.set_status_text('移动鼠标预览，可捕捉顶点和中点，左键确认，Esc 取消')
    end

    def onMouseMove(_flags, x, y, view)
      pick_target(view, x, y)
      view.tooltip = @tooltip
      view.invalidate
    end

    def draw(view)
      return unless @target

      view.drawing_color = 'blue'
      view.line_width = 2
      unless @preview_edges.empty?
        outline = @preview_edges.map { |point| view.screen_coords(point.transform(@target)) }
        view.draw2d(GL_LINES, outline)
      end
      view.draw_points([@target.origin], 7, 2, @snap_label ? 'green' : 'blue')
    end

    def onLButtonDown(_flags, x, y, view)
      return unless @finished

      pick_target(view, x, y)
      return unless @target

      finished = @finished
      @finished = nil
      @model.select_tool(nil)
      finished.call(@target)
    end

    def onCancel(_reason, _view)
      @model.select_tool(nil)
    end

    def deactivate(view)
      view.invalidate
      @finished&.call(nil)
      @finished = nil
    end

    private

    def pick_target(view, x, y)
      @point.pick(view, x, y)
      snapped, entity, @snap_label, snap_transform = snap_point(view, x, y)
      ray = view.pickray(x, y)
      position, path = @model.raytest(ray, true)
      face = path&.last
      if snapped
        adjacent = entity.faces.reject { |candidate| candidate.hidden? || !candidate.layer.visible? }
        face = adjacent.include?(face) ? face : adjacent.first
        @target = face ? surface_target(snapped, face, snap_transform, ray[1]) : Geom::Transformation.translation(snapped)
      elsif face.is_a?(Sketchup::Face)
        @target = surface_target(position, face, Sketchup::InstancePath.new(path).transformation, ray[1])
      else
        @target = @point.valid? ? Geom::Transformation.translation(@point.position) : nil
      end
      @tooltip = @snap_label || (face.is_a?(Sketchup::Face) ? '贴面放置' : (@point.valid? ? @point.tooltip : ''))
    end

    def snap_point(view, x, y)
      if @point.valid? && (vertex = @point.vertex)
        return [@point.position, vertex, '顶点', @point.transformation]
      end

      picker = view.pick_helper
      count = picker.do_pick(x, y, SNAP_RADIUS)
      best = nil
      nearest = SNAP_RADIUS
      count.times do |index|
        edge = picker.leaf_at(index)
        next unless edge.is_a?(Sketchup::Edge)

        transform = @model.edit_transform * picker.transformation_at(index)
        first = edge.start.position.transform(transform)
        last = edge.end.position.transform(transform)
        midpoint = Geom.linear_combination(0.5, first, 0.5, last)
        [[first, edge.start, '顶点'], [last, edge.end, '顶点'], [midpoint, edge, '中点']].each do |point, entity, label|
          screen = view.screen_coords(point)
          distance = Math.hypot(screen.x - x, screen.y - y)
          next if distance > nearest || (best && distance == nearest)

          best = [point, entity, label, transform]
          nearest = distance
        end
      end
      best
    end

    def surface_target(position, face, transform, ray_direction)
      local_x, local_y = face.normal.axes
      # Transform tangents so the normal stays correct under non-uniform scaling.
      normal = local_x.transform(transform).cross(local_y.transform(transform)).normalize
      normal.reverse! if normal.dot(ray_direction) > 0
      x_axis = normal.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS.cross(normal).normalize
      Geom::Transformation.axes(position, x_axis, normal.cross(x_axis), normal)
    end
  end

  module ToolActions
    module_function

    def drop_selection(model)
      entities = model.selection.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) ||
          entity.is_a?(Sketchup::ComponentInstance) ||
          entity.is_a?(Sketchup::Image)
      end
      return 0 if entities.empty?

      moves = entities.filter_map do |entity|
        bottom_z = entity.bounds.min.z
        hit_z = highest_support_z(model, entity.bounds)
        next unless hit_z

        delta_z = hit_z - bottom_z
        next if delta_z.abs < 1.0e-6

        [entity, delta_z]
      end
      return 0 if moves.empty?

      model.start_operation('SU+AI 坐落物体表面', true)
      begin
        moves.each do |entity, delta_z|
          entity.transform!(Geom::Transformation.translation([0, 0, delta_z]))
        end
        model.commit_operation
        model.active_view.invalidate
        moves.length
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def create_aligned_image(model, target, image_path)
      raise ArgumentError, '图片文件不存在' unless File.file?(image_path)

      bounds = target.bounds
      width = bounds.max.x - bounds.min.x
      height = bounds.max.y - bounds.min.y
      raise ArgumentError, '参考对象的水平尺寸无效' if width <= 0 || height <= 0

      point = Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.max.z + 10.mm)
      image = model.active_entities.add_image(image_path, point, width, height)
      raise '无法创建贴图图像' unless image

      image
    end

    def import_texture_aligned(model)
      target = model.selection.to_a.find do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
      unless target
        UI.messagebox('请先选中一个组或组件，作为贴图尺寸和位置参考')
        return nil
      end

      filter = '图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff||'
      path = UI.openpanel('选择贴图图片', nil, filter)
      return nil if path.to_s.empty?

      allowed = %w[.png .jpg .jpeg .bmp .tif .tiff]
      unless allowed.include?(File.extname(path).downcase)
        UI.messagebox('请选择 PNG、JPG、JPEG、BMP、TIF 或 TIFF 图片')
        return nil
      end

      model.start_operation('SU+AI 导入贴图对齐', true)
      begin
        image = create_aligned_image(model, target, path)
        model.commit_operation
        model.active_view.invalidate
        image
      rescue StandardError => error
        model.abort_operation
        Logger.error("Import texture aligned failed: #{error.message}")
        UI.messagebox("导入贴图失败: #{error.message}")
        nil
      end
    end

    def highest_support_z(model, bounds)
      xs = [bounds.min.x, (bounds.min.x + bounds.max.x) / 2.0, bounds.max.x]
      ys = [bounds.min.y, (bounds.min.y + bounds.max.y) / 2.0, bounds.max.y]
      origin_z = bounds.min.z - 0.01.mm
      direction = Geom::Vector3d.new(0, 0, -1)

      xs.product(ys).filter_map do |x, y|
        hit = model.raytest([Geom::Point3d.new(x, y, origin_z), direction], true)
        next unless hit && hit[0].is_a?(Geom::Point3d)

        hit[0].z if hit[0].z <= bounds.min.z + 1.0e-6
      end.max
    end
    private_class_method :highest_support_z
  end
end
