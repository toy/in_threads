require 'in_threads'

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
