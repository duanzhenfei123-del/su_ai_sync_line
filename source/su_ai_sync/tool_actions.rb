module SU_AI_Sync
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
