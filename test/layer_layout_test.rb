require_relative 'test_helper'
require_relative '../source/su_ai_sync/layer_layout'

include TestSupport

assert_equal(10.0, SU_AI_Sync::LayerLayout.normalize_gap(nil), 'nil gap defaults')
assert_equal(10.0, SU_AI_Sync::LayerLayout.normalize_gap(0), 'zero gap defaults')
assert_equal(12.5, SU_AI_Sync::LayerLayout.normalize_gap('12.5'), 'positive gap accepted')

items = [{ 'name' => 'back', 'zIndex' => 2 }, { 'name' => 'front', 'zIndex' => 1 }]
assert_equal(%w[front back], SU_AI_Sync::LayerLayout.order(items).map { |item| item['name'] }, 'zIndex sorts')

duplicates = [{ 'name' => 'first', 'zIndex' => 1 }, { 'name' => 'second', 'zIndex' => 1 }]
assert_equal(%w[first second], SU_AI_Sync::LayerLayout.order(duplicates).map { |item| item['name'] }, 'duplicate zIndex preserves order')

without_indexes = [{ 'name' => 'alpha' }, { 'name' => 'beta' }]
assert_equal(%w[alpha beta], SU_AI_Sync::LayerLayout.order(without_indexes).map { |item| item['name'] }, 'missing zIndex preserves order')

assert_equal(20.0, SU_AI_Sync::LayerLayout.offset_mm(0, 3, 10), 'first item is highest')
assert_equal(0.0, SU_AI_Sync::LayerLayout.offset_mm(2, 3, 10), 'last item is lowest')

paths = [
  { 'id' => 't1a', 'isTextOutline' => true, 'textGroupId' => 'text_1', 'zIndex' => 1 },
  { 'id' => 't1b', 'isTextOutline' => true, 'textGroupId' => 'text_1', 'zIndex' => 1 },
  { 'id' => 'c1a', 'compoundKey' => 'compound_1', 'zIndex' => 2 },
  { 'id' => 'c1b', 'compoundKey' => 'compound_1', 'zIndex' => 2 },
  { 'id' => 'plain', 'zIndex' => 3 }
]
units = SU_AI_Sync::LayerLayout.path_units(paths)
assert_equal(3, units.length, 'text and compound contours remain grouped')
assert_equal(%w[text compound path], units.map { |unit| unit['unitType'] }, 'unit types')
