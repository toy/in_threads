require 'thread'
require 'thwait'

module Enumerable
  # Run enumerable method blocks in threads
  def in_threads(thread_count = 10, &block)
    InThreads.new(self, thread_count, &block)
  end
end

# TODO: create my own ThreadsWait with blackjack and hookers?
# TODO: run_in_threads_inconsecutive for `all?`, `any?`, `none?` and `one?`
# TODO: all ruby1.9.3 methods
# TODO: better way of handling grep?
# TODO: documentation

class InThreads
  (
    instance_methods.map(&:to_s) -
    %w[__id__ __send__ class inspect instance_of? is_a? kind_of? nil? object_id respond_to? send]
  ).each{ |name| undef_method name }
  (private_instance_methods.map(&:to_s) - %w[initialize raise]).each{ |name| undef_method name }

  attr_reader :enumerable, :thread_count
  def initialize(enumerable, thread_count = 10, &block)
    @enumerable, @thread_count = enumerable, thread_count.to_i
    unless enumerable.class.include?(Enumerable)
      raise ArgumentError.new('`enumerable` should include Enumerable.')
    end
    if thread_count < 2
      raise ArgumentError.new('`thread_count` can\'t be less than 2.')
    end
    each(&block) if block
  end

  def in_threads(thread_count = 10, &block)
    self.class.new(enumerable, thread_count, &block)
  end

  class << self
    def enumerable_methods
      Enumerable.instance_methods.map(&:to_s)
    end

    def use(runner, options)
      methods = Array(options[:for])
      raise 'no methods provided using :for option' if methods.empty?
      ignore_undefined = options[:ignore_undefined]
      enumerable_methods = self.enumerable_methods
      methods.each do |method|
        unless ignore_undefined && !enumerable_methods.include?(method)
          class_eval <<-RUBY
            def #{method}(*args, &block)
              #{runner}(enumerable, :#{method}, *args, &block)
            end
          RUBY
        end
      end
    end
  end

  use :run_in_threads_block_result_irrelevant, :for => %w[each]
  use :run_in_threads_consecutive, :for => %w[
    all? any? none? one?
    detect find find_index drop_while take_while
    partition find_all select reject count
    collect map group_by max_by min_by minmax_by sort_by
  ], :ignore_undefined => true
  use :run_in_threads_block_result_irrelevant, :for => %w[
    reverse_each
    each_with_index enum_with_index
    each_cons each_slice enum_cons enum_slice
    zip
    cycle
  ], :ignore_undefined => true
  use :run_without_threads, :for => %w[
    inject reduce
    max min minmax sort
    entries to_a
    drop take
    first
    include? member?
  ], :ignore_undefined => true

  def grep(*args, &block)
    if block
      run_in_threads_consecutive(enumerable.grep(*args), :map, &block)
    else
      enumerable.grep(*args)
    end
  end

private

  class ThreadLimiter
    def initialize(count)
      @count = count
      @waiter = ThreadsWait.new
    end

    def self.limit(count, &block)
      limiter = new(count)
      if block
        begin
          yield limiter
        ensure
          limiter.finalize
        end
      else
        limiter
      end
    end

    def add(thread)
      if @waiter.threads.length + 1 >= @count
        @waiter.join(thread)
      else
        @waiter.join_nowait(thread)
      end
    end

    def finalize
      @waiter.all_waits
    end
  end

  def run_in_threads_block_result_irrelevant(enumerable, method, *args, &block)
    if block
      ThreadLimiter.limit(thread_count) do |limiter|
        enumerable.send(method, *args) do |*block_args|
          limiter.add(Thread.new(*block_args, &block))
        end
      end
    else
      enumerable.send(method, *args)
    end
  end

  def run_in_threads_consecutive(enumerable, method, *args, &block)
    if block
      begin
        queue = Queue.new
        runner = Thread.new do
          ThreadLimiter.limit(thread_count) do |limiter|
            enumerable.each do |object|
              break if Thread.current[:stop]
              thread = Thread.new(object, &block)
              queue << thread
              limiter.add(thread)
            end
          end
        end
        enumerable.send(method, *args) do |object|
          queue.pop.value
        end
      ensure
        runner[:stop] = true
        runner.join
      end
    else
      enumerable.send(method, *args)
    end
  end

  def run_without_threads(enumerable, method, *args, &block)
    enumerable.send(method, *args, &block)
  end
end
