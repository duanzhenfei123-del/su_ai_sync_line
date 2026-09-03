require_relative 'test_helper'

include TestSupport

manager = SU_AI_Sync::UI_Manager.new
html = manager.send(:html_content)

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
