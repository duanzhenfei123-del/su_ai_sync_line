require_relative 'test_helper'

include TestSupport

model = Sketchup.active_model
fixture_dir = File.expand_path('fixtures/stack', __dir__)
history_marker = 'HISTORY_MARKER_MUST_BE_REMOVED'
SU_AI_Sync::Logger.info(history_marker)
created = []

begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 0, false, 10.0)
  created = (model.entities.to_a - before).grep(Sketchup::Group)
  log_content = File.read(SU_AI_Sync::LOG_FILE, encoding: 'UTF-8')

  assert_equal(true, result[:success], 'log reset import succeeds')
  assert_equal(false, log_content.include?(history_marker), 'new import removes historical log content')
  assert_equal(false, File.exist?(SU_AI_Sync::LOG_FILE.sub(/\.log\z/i, '.log.bak')), 'log backup is not retained')
  assert_equal(false, File.exist?(SU_AI_Sync::LOG_FILE.sub(/\.log\z/i, '.old.log')), 'old log is not retained')
ensure
  valid = created.select(&:valid?)
  unless valid.empty?
    model.start_operation('SU+AI logger test cleanup', true)
    model.entities.erase_entities(valid)
    model.commit_operation
  end
end
