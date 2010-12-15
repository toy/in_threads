require 'rake'
require 'jeweler'
require 'rake/gem_ghost_task'
require 'rspec/core/rake_task'

name = 'in_threads'

Jeweler::Tasks.new do |gem|
  gem.name = name
  gem.summary = %Q{Execute ruby blocks in parallel}
  gem.homepage = "http://github.com/toy/#{name}"
  gem.license = 'MIT'
  gem.authors = ['Ivan Kuchin']
  gem.add_development_dependency 'jeweler', '~> 1.5.1'
  gem.add_development_dependency 'rake-gem-ghost'
  gem.add_development_dependency 'rspec'
end
Jeweler::RubygemsDotOrgTasks.new
Rake::GemGhostTask.new

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.rspec_opts = ['--colour --format progress']
  spec.pattern = 'spec/**/*_spec.rb'
end
task :default => :spec
