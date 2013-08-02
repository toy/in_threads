require 'thread'

class InThreads
  class Filler
    class Extractor
      include Enumerable

      def initialize(filler)
        @filler = filler
        @queue = []
      end

      def push(o)
        @queue.push(o)
      end

      def each
        begin
          loop do
            while @filler.synchronize{ @queue.empty? }
              @filler.run
            end
            yield @filler.synchronize{ @queue.shift }
          end
        rescue ThreadError => e
        end
        nil # non reusable
      end
    end

    attr_reader :extractors
    def initialize(enum, extractor_count)
      @extractors = Array.new(extractor_count){ Extractor.new(self) }
      @mutex = Mutex.new
      @filler = Thread.new do
        enum.each do |o|
          synchronize do
            @extractors.each do |extractor|
              extractor.push(o)
            end
          end
        end
      end
    end

    def run
      @filler.run
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end
  end
end
