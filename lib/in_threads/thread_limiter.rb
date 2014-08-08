require 'thwait'

class InThreads
  # Use ThreadsWait to limit number of threads
  class ThreadLimiter
    # Initialize with limit
    def initialize(count)
      @count = count
      @waiter = ThreadsWait.new
    end

    # Without block behaves as <tt>new</tt>
    # With block yields it with <tt>self</tt> and ensures running of <tt>finalize</tt>
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

    # Add thread to <tt>ThreadsWait</tt>, wait for finishing of one thread if limit reached
    def <<(thread)
      if @waiter.threads.length + 1 >= @count
        @waiter.join(thread).join
      else
        @waiter.join_nowait(thread)
      end
    end

    # Wait for waiting threads
    def finalize
      @waiter.all_waits(&:join)
    end
  end
end
