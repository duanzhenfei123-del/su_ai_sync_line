require_relative 'test_helper'

include TestSupport

manager = SU_AI_Sync::UI_Manager.new
html = manager.send(:html_content)

assert_equal('3.7.3', SU_AI_Sync::VERSION, 'plugin version')
assert_equal(true, html.include?('SU+AI 同步 v3.7.3'), 'panel shows release version')
assert_equal(true, html.include?('id="zStackBtn"'), 'panel contains layer stack toggle')
assert_equal(true, html.include?('id="layerGapInput"'), 'panel contains layer gap input')
assert_equal(true, html.include?('sketchup.drop_to_surface()'), 'panel contains surface drop action')
assert_equal(true, html.include?('sketchup.import_texture_aligned()'), 'panel contains aligned texture action')
assert_equal(true, html.include?('作者：段土土'), 'panel preserves author label')

dialog = nil
begin
  dialog = manager.send(:create_dialog)
  assert_equal(true, dialog.is_a?(UI::HtmlDialog), 'panel dialog registers callbacks')
ensure
  dialog.close if dialog
end

original_messagebox = UI.method(:messagebox)
UI.define_singleton_method(:messagebox) { |_message, *_args| 0 }
begin
  SU_AI_Sync.instance_variable_set(:@ui_manager, manager)
  reload_result = SU_AI_Sync::HotReloader.new.reload!
  retained_manager = SU_AI_Sync.instance_variable_get(:@ui_manager)
ensure
  SU_AI_Sync.instance_variable_set(:@ui_manager, nil)
  UI.define_singleton_method(:messagebox, original_messagebox)
end

assert_equal(true, reload_result, 'hot reload succeeds')
assert_equal(nil, retained_manager, 'hot reload discards stale panel instance')
