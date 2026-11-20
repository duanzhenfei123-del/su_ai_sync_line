require_relative 'test_helper'
require_relative '../source/su_ai_sync/tool_actions'

include TestSupport

model = Sketchup.active_model

def erase_tool_action_fixtures(model, entities)
  valid = entities.compact.select(&:valid?)
  return if valid.empty?

  model.start_operation('SU+AI tool action test cleanup', true)
  model.entities.erase_entities(valid)
  model.commit_operation
  model.selection.clear
end

base = nil
floating = nil
begin
  model.start_operation('drop test setup', true)
  base = model.entities.add_group
  base.entities.add_face(
    [0, 0, 0], [100.mm, 0, 0], [100.mm, 100.mm, 0], [0, 100.mm, 0]
  ).pushpull(10.mm)
  base.transform!(Geom::Transformation.translation([0, 0, -base.bounds.min.z]))
  floating = model.entities.add_group
  floating.entities.add_face(
    [20.mm, 20.mm, 0], [40.mm, 20.mm, 0],
    [40.mm, 40.mm, 0], [20.mm, 40.mm, 0]
  ).pushpull(5.mm)
  floating.transform!(Geom::Transformation.translation([0, 0, 30.mm]))
  model.commit_operation
  model.selection.clear
  model.selection.add(floating)

  assert_equal(1, SU_AI_Sync::ToolActions.drop_selection(model), 'one selected group moved')
  assert_equal(10.mm.to_f.round(6), floating.bounds.min.z.to_f.round(6), 'group lands on support top')
ensure
  erase_tool_action_fixtures(model, [base, floating])
end

unsupported = nil
begin
  model.start_operation('no-hit test setup', true)
  unsupported = model.entities.add_group
  unsupported.entities.add_face(
    [500.mm, 500.mm, 0], [520.mm, 500.mm, 0],
    [520.mm, 520.mm, 0], [500.mm, 520.mm, 0]
  ).pushpull(5.mm)
  unsupported.transform!(Geom::Transformation.translation([0, 0, 30.mm]))
  model.commit_operation
  before_z = unsupported.bounds.min.z
  model.selection.clear
  model.selection.add(unsupported)

  assert_equal(0, SU_AI_Sync::ToolActions.drop_selection(model), 'no support moves nothing')
  assert_equal(before_z.to_f.round(6), unsupported.bounds.min.z.to_f.round(6), 'no support keeps position')
ensure
  erase_tool_action_fixtures(model, [unsupported])
end

low_support = nil
high_support = nil
wide_floating = nil
begin
  model.start_operation('mixed-height drop test setup', true)
  low_support = model.entities.add_group
  low_support.entities.add_face(
    [0, 0, 0], [40.mm, 0, 0], [40.mm, 100.mm, 0], [0, 100.mm, 0]
  ).pushpull(10.mm)
  low_support.transform!(Geom::Transformation.translation([0, 0, -low_support.bounds.min.z]))

  high_support = model.entities.add_group
  high_support.entities.add_face(
    [45.mm, 0, 0], [100.mm, 0, 0], [100.mm, 100.mm, 0], [45.mm, 100.mm, 0]
  ).pushpull(20.mm)
  high_support.transform!(Geom::Transformation.translation([0, 0, -high_support.bounds.min.z]))

  wide_floating = model.entities.add_group
  wide_floating.entities.add_face(
    [0, 0, 0], [100.mm, 0, 0], [100.mm, 100.mm, 0], [0, 100.mm, 0]
  ).pushpull(5.mm)
  wide_floating.transform!(
    Geom::Transformation.translation([0, 0, 30.mm - wide_floating.bounds.min.z])
  )
  model.commit_operation
  model.selection.clear
  model.selection.add(wide_floating)

  assert_equal(1, SU_AI_Sync::ToolActions.drop_selection(model), 'mixed support moves one group')
  assert_equal(20.mm.to_f.round(6), wide_floating.bounds.min.z.to_f.round(6), 'mixed support chooses highest surface')
ensure
  erase_tool_action_fixtures(model, [low_support, high_support, wide_floating])
end

fixture = File.expand_path('../source/su_ai_sync/icon_import.png', __dir__)
target = nil
image = nil
image_operation_started = false
begin
  model.start_operation('aligned image test setup', true)
  target = model.entities.add_group
  target.entities.add_face(
    [0, 0, 0], [100.mm, 0, 0], [100.mm, 60.mm, 0], [0, 60.mm, 0]
  ).pushpull(20.mm)
  model.commit_operation

  model.start_operation('aligned image test', true)
  image_operation_started = true
  image = SU_AI_Sync::ToolActions.create_aligned_image(model, target, fixture)
  model.commit_operation
  image_operation_started = false

  assert_equal(100.mm.to_f.round(6), image.bounds.width.to_f.round(6), 'aligned image width')
  assert_equal(60.mm.to_f.round(6), image.bounds.height.to_f.round(6), 'aligned image height')
  assert_equal(target.bounds.min.x.to_f.round(6), image.bounds.min.x.to_f.round(6), 'aligned image min x')
  assert_equal(target.bounds.min.y.to_f.round(6), image.bounds.min.y.to_f.round(6), 'aligned image min y')
  assert_equal((target.bounds.max.z + 10.mm).to_f.round(6), image.bounds.min.z.to_f.round(6), 'aligned image z')
ensure
  model.abort_operation if image_operation_started
  erase_tool_action_fixtures(model, [target, image])
end

placement_events = []
view = model.active_view
original_camera = view.camera
target_group = nil
begin
  tool = SU_AI_Sync::ImportPlacementTool.new(model) { |point| placement_events << point }
  model.select_tool(tool)
  tool.onCancel(0, view)
  assert_equal([nil], placement_events, 'cancelling mouse placement reports one cancellation')

  placement_events.clear
  tool = SU_AI_Sync::ImportPlacementTool.new(model) { |point| placement_events << point }
  model.select_tool(tool)
  screen = view.screen_coords(ORIGIN)
  tool.onMouseMove(0, screen.x, screen.y, view)
  assert_equal([], placement_events, 'moving the cursor does not import')
  tool.onLButtonDown(0, screen.x, screen.y, view)
  assert_equal(1, placement_events.length, 'clicking confirms placement once')
  assert_equal(true, placement_events.first.is_a?(Geom::Transformation), 'free placement uses a model-space transform')

  model.start_operation('surface placement fixture', true)
  target_group = model.entities.add_group
  face = target_group.entities.add_face([0, 0, 0], [20, 0, 0], [20, 10, 6], [0, 10, 6])
  rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
  target_group.transform!(Geom::Transformation.translation([30, 20, 10]) * rotation * Geom::Transformation.scaling(1, 2, 3))
  model.commit_operation
  transform = target_group.transformation
  center = Geom::Point3d.new(10, 5, 3).transform(transform)
  normal = Geom::Vector3d.new(20, 0, 0).transform(transform).cross(Geom::Vector3d.new(0, 10, 6).transform(transform)).normalize
  camera = Sketchup::Camera.new(center.offset(normal, 70), center, Y_AXIS, false)
  camera.height = 60
  view.camera = camera
  view.refresh
  screen = view.screen_coords(center)
  hit = model.raytest(view.pickray(screen.x, screen.y), true)
  assert_equal(face, hit&.last&.last, 'test cursor targets the sloping face')

  placement_events.clear
  tool = SU_AI_Sync::ImportPlacementTool.new(model) { |target| placement_events << target }
  model.select_tool(tool)
  tool.onMouseMove(0, screen.x, screen.y, view)
  assert_equal([], placement_events, 'hovering a face does not import')
  tool.onLButtonDown(0, screen.x, screen.y, view)
  placement = placement_events.fetch(0)
  assert_equal(hit.first.to_a, placement.origin.to_a, 'placement origin is the point on the target face')
  assert_equal(true, placement.zaxis.samedirection?(normal), 'placement follows the transformed face normal')
  assert_equal(true, placement.yaxis.z > 0, 'artwork stays upright on a sloping face')

  vertex = Geom::Point3d.new(0, 0, 0).transform(transform)
  midpoint = Geom::Point3d.new(10, 0, 0).transform(transform)
  [[vertex, '顶点'], [midpoint, '中点']].each do |position, label|
    screen = view.screen_coords(position)
    placement_events.clear
    tool = SU_AI_Sync::ImportPlacementTool.new(model, [ORIGIN, Geom::Point3d.new(2, 0, 0)]) do |target|
      placement_events << target
    end
    model.select_tool(tool)
    tool.onMouseMove(0, screen.x + 2, screen.y, view)
    hovered = tool.instance_variable_get(:@target)
    assert_equal(label, tool.instance_variable_get(:@snap_label), "hover identifies the #{label} inference")
    assert_equal(true, hovered.origin.distance(position) < 0.001, "#{label} is snapped before clicking")
    assert_equal([], placement_events, "#{label} preview does not confirm placement")
    tool.onLButtonDown(0, screen.x + 2, screen.y, view)
    assert_equal(hovered.origin.to_a, placement_events.fetch(0).origin.to_a, "#{label} click matches the preview")
    assert_equal(true, placement_events.fetch(0).zaxis.samedirection?(normal), "#{label} keeps the target face orientation")
  end
ensure
  model.select_tool(nil)
  view.camera = original_camera
  erase_tool_action_fixtures(model, [target_group])
end
