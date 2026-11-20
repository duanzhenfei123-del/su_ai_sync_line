require_relative 'test_helper'

include TestSupport

model = Sketchup.active_model
fixture_dir = File.expand_path('fixtures/stack', __dir__)
negative_origin_fixture_dir = File.expand_path('fixtures/negative_origin', __dir__)

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

negative_origin_groups = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(
    1.0, true, 4, negative_origin_fixture_dir, 0, false, 10.0
  )
  negative_origin_groups = imported_groups_since(model, before)
  final_group = negative_origin_groups.find { |group| group.name.start_with?('AI导入') }

  assert_equal(true, result[:success], 'negative-coordinate import succeeds')
  assert_equal(0.0, final_group.bounds.min.x.to_mm.round(6), 'negative-coordinate group aligns min x')
  assert_equal(0.0, final_group.bounds.min.y.to_mm.round(6), 'negative-coordinate group aligns min y')
ensure
  remove_test_groups(model, negative_origin_groups)
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

require 'tmpdir'
Dir.mktmpdir('suai-placement') do |folder|
  groups = []
  begin
    data = JSON.parse(File.read(File.join(negative_origin_fixture_dir, 'latest_sync.json')))
    data['document'] = { 'artboardOriginMM' => [-50.0, -60.0] }
    path = File.join(folder, 'latest_sync.json')
    [0, 80].each do |shift|
      data['paths'][0]['verticesMM'] = [[-20 + shift, -30], [20 + shift, -30], [20 + shift, 10], [-20 + shift, 10]]
      File.write(path, JSON.generate(data))
      before = model.entities.to_a
      result = SU_AI_Sync::Importer.new(model).import(2.0, true, 4, folder)
      groups.concat(imported_groups_since(model, before))
      assert_equal(true, result[:success], 'relative import succeeds')
    end
    minima = groups.map { |group| [group.bounds.min.x.to_mm.round(5), group.bounds.min.y.to_mm.round(5)] }
    assert_equal([[60.0, 60.0], [220.0, 60.0]], minima, 'batches share the artboard origin and scale')

    data['document']['artboardOriginMM'] = nil
    second = JSON.parse(JSON.generate(data['paths'].first))
    second['id'] = 'outside_second'
    second['verticesMM'].each { |point| point[0] += 80 }
    data['paths'] << second
    File.write(path, JSON.generate(data))
    before = model.entities.to_a
    result = SU_AI_Sync::Importer.new(model).import(2.0, true, 4, folder)
    groups.concat(imported_groups_since(model, before))
    assert_equal(true, result[:success], 'off-artboard import succeeds')
    bounds = groups.last.bounds
    assert_equal([0, 0], [bounds.min.x.to_mm.round, bounds.min.y.to_mm.round], 'off-artboard batch aligns its bottom-left')
    assert_equal(240, bounds.width.to_mm.round, 'off-artboard batch keeps the spacing between objects')

    data['document']['artboardOriginMM'] = [-50.0, -60.0]
    File.write(path, JSON.generate(data))
    target = Geom::Point3d.new(110.mm, 220.mm, 30.mm)
    before = model.entities.to_a
    result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, folder, target: Geom::Transformation.translation(target))
    groups.concat(imported_groups_since(model, before))
    assert_equal(true, result[:success], 'point placement succeeds')
    assert_equal([110, 220, 30], groups.last.bounds.min.to_a.map { |axis| axis.to_mm.round }, 'group bottom-left uses picked point')

    wall = Geom::Transformation.axes(target, Y_AXIS, Z_AXIS, X_AXIS)
    before = model.entities.to_a
    result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, folder, target: wall)
    groups.concat(imported_groups_since(model, before))
    assert_equal(true, result[:success], 'surface placement succeeds')
    bounds = groups.last.bounds
    assert_equal([110, 220, 30], bounds.min.to_a.map { |axis| axis.to_mm.round }, 'wall placement anchors the original bottom-left')
    assert_equal([0, 120, 40], [bounds.width, bounds.height, bounds.depth].map { |axis| axis.to_mm.round }, 'import geometry lies in the wall plane')

    before = model.entities.to_a
    preview = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, folder, preview: true)
    assert_equal(true, preview[:success], 'mouse preview is prepared before placement')
    assert_equal(before, model.entities.to_a, 'preparing the preview leaves no geometry')
    preview_bounds = Geom::BoundingBox.new
    preview[:edges].each { |point| preview_bounds.add(point.transform(wall)) }
    assert_equal(bounds.min.to_a, preview_bounds.min.to_a, 'preview starts at the final anchor')
    assert_equal(bounds.max.to_a, preview_bounds.max.to_a, 'preview has the final dimensions')
    data['paths'].pop
    File.write(path, JSON.generate(data))
    result = preview[:confirm].call(wall)
    groups.concat(imported_groups_since(model, before))
    assert_equal(2, result[:paths], 'confirmation uses the previewed export even if JSON changes')
    assert_equal(bounds.max.to_a, groups.last.bounds.max.to_a, 'confirmed geometry matches the preview')
  ensure
    remove_test_groups(model, groups)
  end
end
