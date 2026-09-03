module TestSupport
  def assert_equal(expected, actual, name)
    raise "#{name}: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
    puts "PASS #{name}"
  end
end
