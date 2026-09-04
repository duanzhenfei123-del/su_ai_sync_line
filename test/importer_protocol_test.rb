require 'tmpdir'
require_relative 'test_helper'

include TestSupport

importer = SU_AI_Sync::Importer.allocate

assert_equal(1, importer.send(:validate_data!, { 'paths' => [] }), 'legacy protocol defaults to schema 1')
assert_equal(2, importer.send(:validate_data!, { 'schemaVersion' => 2, 'groups' => [] }), 'schema 2 accepted')
assert_raises(ArgumentError, 'future protocol rejected') do
  importer.send(:validate_data!, { 'schemaVersion' => 3 })
end
assert_raises(ArgumentError, 'non-object root rejected') do
  importer.send(:validate_data!, [])
end
assert_raises(ArgumentError, 'invalid collection rejected') do
  importer.send(:validate_data!, { 'schemaVersion' => 2, 'paths' => {} })
end

compact_group = {
  'name' => 'outer',
  'paths' => [{
    'g' => {
      'p' => [{ 'a' => [0, 0] }, { 'a' => [10, 0] }, { 'a' => [10, 10] }],
      'c' => 1,
      'cv' => 0
    },
    'f' => [255, 0, 0]
  }],
  'groups' => [{
    'name' => 'inner',
    'paths' => [{
      'g' => {
        'p' => [{ 'a' => [1, 1] }, { 'a' => [2, 1] }, { 'a' => [2, 2] }],
        'c' => 1,
        'cv' => 0
      }
    }]
  }]
}
normalized_group = importer.send(:normalize_group, compact_group)
assert_equal([[0, 0], [10, 0], [10, 10]], normalized_group['paths'].first['verticesMM'], 'group paths normalized')
assert_equal([[1, 1], [2, 1], [2, 2]], normalized_group['groups'].first['paths'].first['verticesMM'], 'nested group paths normalized')
assert_raises(ArgumentError, 'non-object group rejected') do
  importer.send(:normalize_group, [])
end

builder = SU_AI_Sync::GeometryBuilder.allocate
assert_equal(true, builder.send(:text_path?, { 'textGroupId' => 'text_1' }), 'legacy text group recognized')
assert_equal('text_1', builder.send(:text_group_key, { 'textGroupId' => 'text_1' }), 'legacy text key retained')
assert_equal('text_1', builder.send(:text_group_key, { 'textGroupKey' => '', 'textGroupId' => 'text_1' }), 'blank new text key falls back')

Dir.mktmpdir('su_ai_protocol') do |directory|
  customer = File.join(directory, 'customer.json')
  older = File.join(directory, 'sync_old.json')
  newer = File.join(directory, 'sync_new.json')
  latest = File.join(directory, 'latest_sync.json')
  File.write(customer, '{}')
  File.write(older, '{}')
  File.write(newer, '{}')
  File.utime(Time.at(1), Time.at(1), older)
  File.utime(Time.at(2), Time.at(2), newer)

  assert_equal(newer, importer.send(:locate_json, directory), 'newest legacy sync selected')
  File.write(latest, '{}')
  assert_equal(latest, importer.send(:locate_json, directory), 'fixed sync file has priority')
end
