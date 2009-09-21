require 'rubygems'
require 'rake'
require 'rake/clean'
require 'fileutils'
require 'echoe'

version = YAML.load_file(File.join(File.dirname(__FILE__), 'VERSION.yml')).join('.') rescue nil

echoe = Echoe.new('in_threads', version) do |p|
  p.author = 'toy'
  p.summary = 'Execute ruby code in parallel.'
  p.project = 'toytoy'
end

desc "Replace system gem with symlink to this folder"
task :ghost do
  path = Gem.searcher.find(echoe.name).full_gem_path
  system 'sudo', 'rm', '-r', path
  symlink File.expand_path('.'), path
end
