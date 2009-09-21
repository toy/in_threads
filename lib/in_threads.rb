require 'thread'
require 'thwait'

module Enumerable
  def in_threads(max_threads = 10)
    InThreads.new(self, max_threads)
  end
end

class InThreads
  def initialize(object, max_threads)
    @threads = []
    @object = object
    @max_threads = max_threads
  end

  def map(*args, &block)
    run_in_threads(:map, *args, &block)
    @threads.map(&:value)
  end

  def method_missing(method, *args, &block)
    run_in_threads(method, *args, &block)
  end

private

  def run_in_threads(method, *args, &block)
    @object.send(method, *args) do |*args|
      if @threads.count(&:alive?) >= @max_threads
        ThreadsWait.new(*@threads).next_wait
      end
      @threads << Thread.new(*args, &block)
    end
  ensure
    @threads.map(&:join)
  end
end
