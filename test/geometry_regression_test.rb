require_relative 'test_helper'

include TestSupport

def regression_faces(entities)
  faces = entities.grep(Sketchup::Face)
  entities.grep(Sketchup::Group).each do |group|
    faces.concat(regression_faces(group.entities)) if group.valid?
  end
  faces
end

def regression_cleanup(model, entities)
  valid = entities.compact.select(&:valid?)
  return if valid.empty?

  model.start_operation('SU+AI geometry regression cleanup', true)
  model.entities.erase_entities(valid)
  model.commit_operation
end

def near_mm?(value, expected)
  (value.to_mm - expected).abs < 0.01
end

def outward_side_normal?(face)
  center = face.bounds.center
  normal = face.normal
  return normal.x < -0.9 if near_mm?(center.x, 0)
  return normal.x > 0.9 if near_mm?(center.x, 40)
  return normal.y < -0.9 if near_mm?(center.y, 0)
  return normal.y > 0.9 if near_mm?(center.y, 40)
  return normal.x > 0.9 if near_mm?(center.x, 15)
  return normal.x < -0.9 if near_mm?(center.x, 25)
  return normal.y > 0.9 if near_mm?(center.y, 15)
  return normal.y < -0.9 if near_mm?(center.y, 25)

  false
end

model = Sketchup.active_model
fixture_dir = File.expand_path('fixtures/compound', __dir__)

created = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 0, false, 10.0)
  created = (model.entities.to_a - before).grep(Sketchup::Group)
  faces = regression_faces(created.first.entities)
  ring_face = faces.find { |face| face.loops.length == 2 }

  assert_equal(true, result[:success], 'compound face import succeeds')
  assert_equal(true, !ring_face.nil?, 'compound face preserves text hole')
  color = ring_face.material && ring_face.material.color
  rgb = color ? [color.red, color.green, color.blue] : nil
  assert_equal([255, 0, 0], rgb, 'compound face preserves fill color')
ensure
  regression_cleanup(model, created)
end

created = []
begin
  before = model.entities.to_a
  result = SU_AI_Sync::Importer.new(model).import(1.0, true, 4, fixture_dir, 10.0, false, 10.0)
  created = (model.entities.to_a - before).grep(Sketchup::Group)
  faces = regression_faces(created.first.entities)
  top_z = faces.map { |face| face.bounds.max.z }.max
  top_face = faces.find do |face|
    face.normal.z > 0.9 && (face.bounds.max.z - top_z).abs < 1.0e-6
  end
  side_faces = faces.select { |face| face.normal.z.abs < 0.1 }

  assert_equal(true, result[:success], 'compound extrusion succeeds')
  assert_equal(true, top_face && top_face.loops.length == 2, 'extruded text top preserves hole')
  color = top_face && top_face.material && top_face.material.color
  rgb = color ? [color.red, color.green, color.blue] : nil
  assert_equal([255, 0, 0], rgb, 'extruded text top preserves fill color')
  assert_equal(8, side_faces.length, 'extruded text creates outer and inner side faces')
  assert_equal(true, side_faces.all? { |face| outward_side_normal?(face) }, 'extruded text side normals face outward')
ensure
  regression_cleanup(model, created)
end
