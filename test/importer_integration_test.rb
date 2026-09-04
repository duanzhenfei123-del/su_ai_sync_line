require_relative 'test_helper'

include TestSupport

model = Sketchup.active_model
fixture_dir = File.expand_path('fixtures/stack', __dir__)

def imported_groups_since(model, before)
  (model.entities.to_a - before).grep(Sketchup::Group)
end

def remove_test_groups(model, groups)
  valid = groups.select(&:valid?)
  return if valid.empty?

  model.start_operation('SU+AI importer test cleanup', true)
  model.entities.erase_entities(valid)
  model.commit_operation
end

stacked_groups = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 0, true, 10.0)
  stacked_groups = imported_groups_since(model, before)
  final_group = stacked_groups.find { |group| group.name.start_with?('AI导入') }

  assert_equal(true, result[:success], 'stacked import succeeds')
  assert_equal(1, stacked_groups.length, 'stacked import preserves one final group')
  assert_equal(2, final_group.entities.grep(Sketchup::Group).length, 'stacked import keeps layer subgroups')
  layer_z = final_group.entities.grep(Sketchup::Group)
                       .map { |group| group.bounds.min.z.to_f.round(6) }
                       .sort
  assert_equal([0.0, 10.mm.to_f.round(6)], layer_z, 'stacked import uses 10mm gap')
  assert_equal(0.0, final_group.bounds.min.x.to_f.round(6), 'stacked group aligns min x')
  assert_equal(0.0, final_group.bounds.min.y.to_f.round(6), 'stacked group aligns min y')
ensure
  remove_test_groups(model, stacked_groups)
end

flat_groups = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 0, false, 10.0)
  flat_groups = imported_groups_since(model, before)
  final_group = flat_groups.find { |group| group.name.start_with?('AI导入') }

  assert_equal(true, result[:success], 'flat import succeeds')
  assert_equal(1, flat_groups.length, 'flat import preserves one final group')
  path_z = final_group.entities.grep(Sketchup::Group)
                    .map { |group| group.bounds.min.z.to_f.round(6) }
                    .uniq
  assert_equal([0.0], path_z, 'flat import keeps paths at original z')
ensure
  remove_test_groups(model, flat_groups)
end

stacked_solid_groups = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 5.0, true, 25.0)
  stacked_solid_groups = imported_groups_since(model, before)
  final_group = stacked_solid_groups.find { |group| group.name.start_with?('AI导入') }
  layer_z = final_group.entities.grep(Sketchup::Group)
                       .map { |group| group.bounds.min.z.to_f }
                       .sort
  gap = (layer_z.last - layer_z.first).round(6)

  assert_equal(true, result[:success], 'stacked extrusion succeeds')
  assert_equal(25.mm.to_f.round(6), gap, 'stacked extrusion uses non-default gap')
ensure
  remove_test_groups(model, stacked_solid_groups)
end
