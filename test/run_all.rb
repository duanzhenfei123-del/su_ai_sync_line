Dir[File.join(__dir__, '*_test.rb')].sort.each { |file| load file }
puts 'ALL TESTS PASSED'
