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
