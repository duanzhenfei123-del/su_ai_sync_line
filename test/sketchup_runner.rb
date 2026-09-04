result_path = ENV['SU_AI_TEST_RESULT']
raise 'SU_AI_TEST_RESULT is required' if result_path.to_s.empty?

File.open(result_path, 'w') do |output|
  previous_stdout = $stdout
  $stdout = output
  begin
    load File.expand_path('../source/su_ai_sync.rb', __dir__)
    load File.expand_path('run_all.rb', __dir__)
  rescue Exception => error
    puts "#{error.class}: #{error.message}"
    puts error.backtrace
  ensure
    $stdout = previous_stdout
  end
end
