require_relative 'test_helper'

include TestSupport

manager = SU_AI_Sync::UI_Manager.new
html = manager.send(:html_content)

assert_equal('3.8.0', SU_AI_Sync::VERSION, 'plugin version')
assert_equal(true, html.include?('DTT 同步导入 · 段土土 · v3.8.0'), 'panel shows signed release title')
assert_equal(true, html.include?('>打赏</button>'), 'panel offers donation dialog')
donation_image = File.binread(File.expand_path('../source/su_ai_sync/assets/wechat_pay.png', __dir__))
assert_equal(true, html.include?("data:image/png;base64,#{Base64.strict_encode64(donation_image)}"), 'panel embeds the bundled donation image')
assert_equal(true, html.include?('id="zStackToggle"'), 'panel contains layer stack toggle')
assert_equal(true, html.include?('id="layerGapInput"'), 'panel contains layer gap input')
assert_equal(true, html.include?('sketchup.drop_to_surface()'), 'panel contains surface drop action')
assert_equal(true, html.include?('sketchup.import_texture_aligned()'), 'panel contains aligned texture action')
assert_equal(['origin', 'mouse'], html.scan(/name="placement" value="([^"]+)"/).flatten, 'panel offers automatic origin and mouse placement')
controls = %w[folder_input placement importBtn status]
assert_equal(true, controls.map { |id| html.index("id=\"#{id}\"") }.each_cons(2).all? { |first, second| first < second }, 'panel follows folder, placement, import, status order')
assert_equal(true, html[/<details id="advancedOptions"[^>]*>.*?<\/details>/m].to_s.include?('id="zStackToggle"'), 'layer stack is inside advanced options')
assert_equal(true, html[/<details class="settings"[^>]*>.*?<\/details>/m].to_s.include?('id="debugChk"'), 'maintenance options are grouped in settings')

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
