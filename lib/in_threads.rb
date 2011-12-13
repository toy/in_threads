require 'thread'

module Enumerable
  # Run enumerable method blocks in threads
  #
  #   urls.in_threads.map do |url|
  #     url.fetch
  #   end
  #
  # Specify number of threads to use:
  #
  #   files.in_threads(4).all? do |file|
  #     file.valid?
  #   end
  #
  # Passing block runs it against <tt>each</tt>
  #
  #   urls.in_threads.each{ … }
  #
  # is same as
  #
  #   urls.in_threads{ … }
  def in_threads(thread_count = 10, &block)
    InThreads.new(self, thread_count, &block)
  end
end

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

  # Creates new instance using underlying enumerable and new thread_count
  def in_threads(thread_count = 10, &block)
    self.class.new(enumerable, thread_count, &block)
  end

  class << self
    # Specify runner to use
    #
    #   use :run_in_threads_consecutive, :for => %w[all? any? none? one?]
    #
    # <tt>:for</tt> is required
    # <tt>:ignore_undefined</tt> ignores methods which are not present in <tt>Enumerable.instance_methods</tt>
    def use(runner, options)
      methods = Array(options[:for])
      raise 'no methods provided using :for option' if methods.empty?
      ignore_undefined = options[:ignore_undefined]
      enumerable_methods = Enumerable.instance_methods.map(&:to_s)
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

  use :run_in_threads_return_original_enum, :for => %w[each]
  use :run_in_threads_return_original_enum, :for => %w[
    reverse_each
    each_with_index enum_with_index
    each_cons each_slice enum_cons enum_slice
    zip
    cycle
    each_entry
  ], :ignore_undefined => true
  use :run_in_threads_consecutive, :for => %w[
    all? any? none? one?
    detect find find_index drop_while take_while
    partition find_all select reject count
    collect map group_by max_by min_by minmax_by sort_by
    flat_map collect_concat
  ], :ignore_undefined => true
  use :run_without_threads, :for => %w[
    inject reduce
    max min minmax sort
    entries to_a
    drop take
    first
    include? member?
    each_with_object
    chunk slice_before
  ], :ignore_undefined => true

  # Special case method, works by applying <tt>run_in_threads_consecutive</tt> with map on enumerable returned by blockless run
  def grep(*args, &block)
    if block
      run_in_threads_consecutive(enumerable.grep(*args), :map, &block)
    else
      enumerable.grep(*args)
    end
  end

protected

  autoload :ThreadLimiter, 'in_threads/thread_limiter'
  autoload :Filler, 'in_threads/filler'

  # Use for methods which don't use block result
  def run_in_threads_return_original_enum(enumerable, method, *args, &block)
    if block
      ThreadLimiter.limit(thread_count) do |limiter|
        enumerable.send(method, *args) do |*block_args|
          limiter << Thread.new(*block_args, &block)
        end
      end
    else
      enumerable.send(method, *args)
    end
  end

  # Use for methods which do use block result and fire objects in same way as <tt>each</tt>
  def run_in_threads_consecutive(enumerable, method, *args, &block)
    if block
      begin
        enum_a, enum_b = Filler.new(enumerable, 2).extractors
        results = Queue.new
        runner = Thread.new do
          Thread.current.priority = -1
          ThreadLimiter.limit(thread_count) do |limiter|
            enum_a.each do |object|
              break if Thread.current[:stop]
              thread = Thread.new(object, &block)
              results << thread
              limiter << thread
            end
          end
        end
        enum_b.send(method, *args) do |object|
          results.pop.value
        end
      ensure
        runner[:stop] = true
        runner.join
      end
    else
      enumerable.send(method, *args)
    end
  end

  # Use for methods which don't use blocks or can not use threads
  def run_without_threads(enumerable, method, *args, &block)
    enumerable.send(method, *args, &block)
  end
end
