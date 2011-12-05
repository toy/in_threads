require 'thread'
require 'thwait'

module Enumerable
  # Run enumerable method blocks in threads
  def in_threads(thread_count = 10, &block)
    InThreads.new(self, thread_count, &block)
  end
end

# TODO: create my own ThreadsWait with blackjack and hookers

class InThreads
  (
    instance_methods.map(&:to_s) -
    %w[__id__ __send__ class inspect instance_of? is_a? kind_of? nil? object_id respond_to? send]
  ).each{ |name| undef_method name }
  (private_instance_methods.map(&:to_s) - %w[initialize]).each{ |name| undef_method name }

  attr_reader :enumerable, :thread_count
  def initialize(enumerable, thread_count = 10, &block)
    @enumerable, @thread_count = enumerable, thread_count
    each(&block) if block
  end

  def in_threads(thread_count = 10, &block)
    self.class.new(@enumerable, thread_count, &block)
  end

  %w[each_with_index enum_with_index].each do |name|
    class_eval <<-RUBY
      def #{name}(*args, &block)
        @enumerable.#{name}(*args, &block)
      end
    RUBY
  end

  def reverse_each(*args, &block)
    @enumerable.reverse_each(*args, &block)
  end

  %w[
    each_cons each_slice enum_cons enum_slice
    zip
    cycle
  ].each do |name|
    class_eval <<-RUBY
      def #{name}(*args, &block)
        run_in_threads_block_result_irrelevant(:#{name}, *args, &block)
      end
    RUBY
  end

  def grep(*args, &block)
    @enumerable.grep(*args, &block)
  end

  %w[
    inject reduce
    max min minmax sort
    entries to_a
    drop take
    first
    include? member?
  ].each do |name|
    class_eval <<-RUBY
      def #{name}(*args, &block)
        @enumerable.#{name}(*args, &block)
      end
    RUBY
  end

  def method_missing(method, *args, &block)
    if block
      run_in_threads_consecutive(method, *args, &block)
    else
      @enumerable.send(method, *args)
    end
  end

private

  def run_in_threads_block_result_irrelevant(method, *args, &block)
    if block
      waiter = ThreadsWait.new
      begin
        @enumerable.send(method, *args) do |object|
          waiter.next_wait if waiter.threads.length >= thread_count
          waiter.join_nowait([Thread.new(object, &block)])
        end
      ensure
        waiter.all_waits
      end
    else
      @enumerable.send(method, *args)
    end
  end

  def run_in_threads_consecutive(method, *args, &block)
    queue = Queue.new
    runner = Thread.new do
      threads = []
      begin
        @enumerable.each do |object|
          if threads.length >= thread_count
            threads = threads.select(&:alive?)
            if threads.length >= thread_count
              ThreadsWait.new(*threads).next_wait
            end
          end
          break if Thread.current[:stop]
          thread = Thread.new(object, &block)
          threads << thread
          queue << thread
        end
      ensure
        threads.map(&:join)
      end
    end
    @enumerable.send(method, *args) do |*block_args|
      queue.pop.value
    end
  ensure
    runner[:stop] = true
    runner.join
  end
end
