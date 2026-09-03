module SU_AI_Sync
  module LayerLayout
    module_function

    def normalize_gap(value)
      gap = value.to_f
      gap > 0 ? gap : 10.0
    end

    def order(items)
      indexes = items.map { |item| numeric_z_index(item['zIndex']) }
      return items.dup if indexes.any?(&:nil?) || indexes.uniq.length <= 1

      items.each_with_index
           .sort_by { |item, original| [numeric_z_index(item['zIndex']), original] }
           .map { |item, _original| item }
    end

    def offset_mm(index, count, gap)
      (count - 1 - index) * normalize_gap(gap)
    end

    def numeric_z_index(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :numeric_z_index
  end
end
