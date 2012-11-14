require "rspec/core/rake_task"

RSpec::Core::RakeTask.new("test") do |test|
  test.rspec_opts = ["--format", "documentation", "--colour"]
  test.pattern = "spec/**/*_spec.rb"
end
