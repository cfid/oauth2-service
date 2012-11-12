require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new("test") do |test|
  test.rspec_opts = ["--format", "documentation", "--colour"]
  test.pattern = "**/*_spec.rb"
end
