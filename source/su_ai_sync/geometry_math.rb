module SU_AI_Sync
  module GeometryMath
    TOLERANCE = 1.0e-6
    DENOMINATOR_EPSILON = 1.0e-12

    module_function

    def polygon_area(vertices)
      return 0.0 if vertices.length < 3
      area = 0.0
      vertices.length.times do |index|
        following = (index + 1) % vertices.length
        area += x(vertices[index]) * y(vertices[following])
        area -= x(vertices[following]) * y(vertices[index])
      end
      area.abs / 2.0
    end

    def bounds(vertices)
      return nil if vertices.empty?
      xs = vertices.map { |vertex| x(vertex) }
      ys = vertices.map { |vertex| y(vertex) }
      [xs.min, ys.min, xs.max, ys.max]
    end

    def bounds_contain_bounds?(outer, inner, tolerance = TOLERANCE)
      return false unless outer && inner
      inner[0] >= outer[0] - tolerance && inner[2] <= outer[2] + tolerance &&
        inner[1] >= outer[1] - tolerance && inner[3] <= outer[3] + tolerance
    end

    def point_in_polygon?(point, vertices)
      return false if vertices.length < 3
      point_x = x(point); point_y = y(point); inside = false; previous = vertices.length - 1
      vertices.length.times do |current|
        current_x = x(vertices[current]); current_y = y(vertices[current])
        previous_x = x(vertices[previous]); previous_y = y(vertices[previous])
        denominator = previous_y - current_y
        denominator = DENOMINATOR_EPSILON if denominator.abs < DENOMINATOR_EPSILON
        crosses = ((current_y > point_y) != (previous_y > point_y)) &&
                  (point_x < (previous_x - current_x) * (point_y - current_y) / denominator + current_x)
        inside = !inside if crosses
        previous = current
      end
      inside
    end

    def x(point); point.respond_to?(:x) ? point.x.to_f : point[0].to_f; end
    def y(point); point.respond_to?(:y) ? point.y.to_f : point[1].to_f; end
  end
end
