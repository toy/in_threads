begin
  require 'jeweler'

  name = 'in_threads'
  summary = 'Execute ruby blocks in parallel'

  jewel = Jeweler::Tasks.new do |j|
    j.name = name
    j.summary = summary
    j.homepage = "http://github.com/toy/#{name}"
    j.authors = ['Ivan Kuchin']
  end

  Jeweler::GemcutterTasks.new

  require 'pathname'
  desc "Replace system gem with symlink to this folder"
  task 'ghost' do
    gem_path = Pathname(Gem.searcher.find(name).full_gem_path)
    current_path = Pathname('.').expand_path
    system('rm', '-r', gem_path)
    system('ln', '-s', current_path, gem_path)
  end

rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'spec/rake/spectask'
Spec::Rake::SpecTask.new(:spec) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.spec_files = FileList['spec/**/*_spec.rb']
end
task :default => :spec
