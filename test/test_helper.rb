module TestSupport
  def assert_equal(expected, actual, name)
    raise "#{name}: expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
    puts "PASS #{name}"
  end

  def assert_raises(error_class, name)
    yield
  rescue error_class
    puts "PASS #{name}"
  else
    raise "#{name}: expected #{error_class}, nothing was raised"
  end
end
