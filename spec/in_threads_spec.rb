$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'rspec'
require 'in_threads'

class Item
  def initialize(i)
    @i, @value = i, Kernel.rand
  end

  def ==(other)
    self.id == other.id
  end

  class HalfMatcher
    def ===(item)
      raise "#{item.inspect} is not an Item" unless item.is_a?(Item)
      (0.25..0.75) === item.instance_variable_get(:@value)
    end
  end

  def value
    sleep; @value
  end

  def check?
    value < 0.5
  end

  def touch_n_value(*args)
    touch(*args); value
  end

  def touch_n_check?(*args)
    touch(*args); check?
  end

protected

  def id
    [self.class, @i, @value]
  end

private

  def sleep
    Kernel.sleep 0.01
  end
end

class ValueItem < Item
  def initialize(i, value)
    @i, @value = i, value
  end

  def value
    sleep; @value
  end

  def check?
    !!value
  end
end

def describe_enum_method(method, &block)
  @enum_methods ||= Enumerable.instance_methods.map(&:to_s)
  if @enum_methods.include?(method)
    describe(method, &block)
  else
    it "should not be defined" do
      exception_regexp = /^undefined method `#{Regexp.escape(method)}' .*\bInThreads\b/
      expect{ enum.in_threads.send(method) }.to raise_error(NoMethodError, exception_regexp)
    end
  end
end

describe "in_threads" do
  let(:enum){ 30.times.map{ |i| Item.new(i) } }
  let(:speed_coef){ 0.666 } # small coefficient, should be more if sleep time coefficient is bigger

  def measure
    start = Time.now
    yield
    Time.now - start
  end

  describe "consistency" do
    describe "verifying params" do
      it "should complain about using with non enumerable" do
        expect{ InThreads.new(1) }.to raise_error(ArgumentError)
      end

      [1..10, 10.times, {}, []].each do |o|
        it "should complain about using with #{o.class}" do
          expect{ InThreads.new(o) }.not_to raise_error
        end
      end

      it "should complain about using less than 2 threads" do
        expect{ 10.times.in_threads(1) }.to raise_error(ArgumentError)
      end

      it "should not complain about using 2 or more threads" do
        expect{ 10.times.in_threads(2) }.not_to raise_error
      end
    end

    describe "in_threads method" do
      it "should not change existing instance" do
        threaded = enum.in_threads(10)
        expect{ threaded.in_threads(20) }.not_to change(threaded, :thread_count)
      end

      it "should create new instance with different title when called on WithProgress" do
        threaded = enum.in_threads(10)
        tthreaded = threaded.in_threads(20)
        expect(threaded.thread_count).to eq(10)
        expect(tthreaded.thread_count).to eq(20)
        expect(tthreaded.class).to eq(threaded.class)
        expect(tthreaded.object_id).not_to eq(threaded.object_id)
        expect(tthreaded.enumerable).to eq(threaded.enumerable)
      end
    end

    describe "thread count" do
      let(:enum){ 100.times.map{ |i| ValueItem.new(i, i < 50) } }

      %w[each map all?].each do |method|
        it "should run in specified number of threads for #{method}" do
          @thread_count = 0
          @max_thread_count = 0
          @mutex = Mutex.new
          enum.in_threads(4).send(method) do |o|
            @mutex.synchronize do
              @thread_count += 1
              @max_thread_count = [@max_thread_count, @thread_count].max
            end
            res = o.check?
            @mutex.synchronize do
              @thread_count -= 1
            end
            res
          end
          expect(@thread_count).to eq(0)
          expect(@max_thread_count).to eq(4)
        end
      end
    end

    describe "underlying enumerable usage" do
      class CheckEachCalls
        include Enumerable

        def each
          each_started
          100.times.each do |i|
            yield ValueItem.new(i, i < 50)
          end
        end
      end
      let(:enum){ CheckEachCalls.new }

      %w[each map all?].each do |method|
        it "should call underlying enumerable.each only once for #{method}" do
          expect(enum).to receive(:each_started).once
          enum.in_threads(13).send(method, &:check?)
        end
      end
    end
  end

  describe "methods" do
    (Enumerable.instance_methods - 10.times.in_threads.class.instance_methods).each do |method|
      pending method
    end

    class TestException < StandardError; end

    def check_test_exception(enum, &block)
      expect{ block[enum.in_threads] }.to raise_exception(TestException)
      expect{ block[enum.in_threads(1000)] }.to raise_exception(TestException)
    end

    describe "each" do
      it "should return same enum after running" do
        expect(enum.in_threads.each(&:value)).to eq(enum)
      end

      it "should execute block for each element" do
        enum.each{ |o| expect(o).to receive(:touch).once }
        enum.in_threads.each(&:touch_n_value)
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.each(&:value) }).to be < measure{ enum.each(&:value) } * speed_coef
      end

      it "should run faster with more threads" do
        expect(measure{ enum.in_threads(10).each(&:value) }).to be < measure{ enum.in_threads(2).each(&:value) } * speed_coef
      end

      it "should return same enum without block" do
        expect(enum.in_threads.each.to_a).to eq(enum.each.to_a)
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.each{ raise TestException }
        end
      end
    end

    %w[each_with_index enum_with_index].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |o, i| o.value } }

        it "should return same result with threads" do
          expect(enum.in_threads.send(method, &runner)).to eq(enum.send(method, &runner))
        end

        it "should fire same objects" do
          enum.send(method){ |o, i| expect(o).to receive(:touch).with(i).once }
          enum.in_threads.send(method){ |o, i| o.touch_n_value(i) }
        end

        it "should run faster with threads" do
          expect(measure{ enum.in_threads.send(method, &runner) }).to be < measure{ enum.send(method, &runner) } * speed_coef
        end

        it "should return same enum without block" do
          expect(enum.in_threads.send(method).to_a).to eq(enum.send(method).to_a)
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ raise TestException }
          end
        end
      end
    end

    describe "reverse_each" do
      it "should return same result with threads" do
        expect(enum.in_threads.reverse_each(&:value)).to eq(enum.reverse_each(&:value))
      end

      it "should fire same objects in reverse order" do
        @order = double('order', :notify => nil)
        expect(@order).to receive(:notify).with(enum.last).ordered
        expect(@order).to receive(:notify).with(enum[enum.length / 2]).ordered
        expect(@order).to receive(:notify).with(enum.first).ordered
        enum.reverse_each{ |o| expect(o).to receive(:touch).once }
        @mutex = Mutex.new
        enum.in_threads.reverse_each do |o|
          @mutex.synchronize{ @order.notify(o) }
          o.touch_n_value
        end
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.reverse_each(&:value) }).to be < measure{ enum.reverse_each(&:value) } * speed_coef
      end

      it "should return same enum without block" do
        expect(enum.in_threads.reverse_each.to_a).to eq(enum.reverse_each.to_a)
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.reverse_each{ raise TestException }
        end
      end
    end

    %w[
      all? any? none? one?
      detect find find_index drop_while take_while
    ].each do |method|
      describe method do
        let(:enum){ 100.times.map{ |i| ValueItem.new(i, i % 2 == 1) } }

        it "should return same result with threads" do
          expect(enum.in_threads.send(method, &:check?)).to eq(enum.send(method, &:check?))
        end

        it "should fire same objects but not all" do
          a = []
          enum.send(method) do |o|
            a << o
            o.check?
          end

          @a = []
          @mutex = Mutex.new
          enum.in_threads.send(method){ |o| @mutex.synchronize{ @a << o }; o.check? }

          expect(@a.length).to be >= a.length
          expect(@a.length).to be <= enum.length * 0.5
        end

        it "should run faster with threads" do
          boolean = %w[all? drop_while take_while].include?(method)
          enum = 30.times.map{ |i| ValueItem.new(i, boolean) }
          expect(measure{ enum.in_threads.send(method, &:check?) }).to be < measure{ enum.send(method, &:check?) } * speed_coef
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ raise TestException }
          end
        end
      end
    end

    %w[partition find_all select reject count].each do |method|
      describe method do
        it "should return same result with threads" do
          expect(enum.in_threads.send(method, &:check?)).to eq(enum.send(method, &:check?))
        end

        it "should fire same objects" do
          enum.send(method){ |o| expect(o).to receive(:touch).once }
          enum.in_threads.send(method, &:touch_n_check?)
        end

        it "should run faster with threads" do
          expect(measure{ enum.in_threads.send(method, &:check?) }).to be < measure{ enum.send(method, &:check?) } * speed_coef
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ raise TestException }
          end
        end
      end
    end

    %w[collect map group_by max_by min_by minmax_by sort_by].each do |method|
      describe method do
        it "should return same result with threads" do
          expect(enum.in_threads.send(method, &:value)).to eq(enum.send(method, &:value))
        end

        it "should fire same objects" do
          enum.send(method){ |o| expect(o).to receive(:touch).once; 0 }
          enum.in_threads.send(method, &:touch_n_value)
        end

        it "should run faster with threads" do
          expect(measure{ enum.in_threads.send(method, &:value) }).to be < measure{ enum.send(method, &:value) } * speed_coef
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ raise TestException }
          end
        end
      end
    end

    %w[each_cons each_slice enum_slice enum_cons].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |a| a.each(&:value) } }

        it "should fire same objects" do
          enum.send(method, 3){ |a| expect(a.first).to receive(:touch).with(a).once }
          enum.in_threads.send(method, 3){ |a| a.first.touch_n_value(a) }
        end

        it "should return same with block" do
          expect(enum.in_threads.send(method, 3, &runner)).to eq(enum.send(method, 3, &runner))
        end

        it "should run faster with threads" do
          expect(measure{ enum.in_threads.send(method, 3, &runner) }).to be < measure{ enum.send(method, 3, &runner) } * speed_coef
        end

        it "should return same without block" do
          expect(enum.in_threads.send(method, 3).to_a).to eq(enum.send(method, 3).to_a)
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method, 3){ raise TestException }
          end
        end
      end
    end

    describe "zip" do
      let(:runner){ proc{ |a| a.each(&:value) } }

      it "should fire same objects" do
        enum.zip(enum, enum){ |a| expect(a.first).to receive(:touch).with(a).once }
        enum.in_threads.zip(enum, enum){ |a| a.first.touch_n_value(a) }
      end

      it "should return same with block" do
        expect(enum.in_threads.zip(enum, enum, &runner)).to eq(enum.zip(enum, enum, &runner))
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.zip(enum, enum, &runner) }).to be < measure{ enum.zip(enum, enum, &runner) } * speed_coef
      end

      it "should return same without block" do
        expect(enum.in_threads.zip(enum, enum)).to eq(enum.zip(enum, enum))
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.zip(enum, enum){ raise TestException }
        end
      end
    end

    describe "cycle" do
      it "should fire same objects" do
        enum.cycle(1){ |o| expect(o).to receive(:touch).exactly(3).times }
        enum.in_threads.cycle(3, &:touch_n_value)
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.cycle(3, &:value) }).to be < measure{ enum.cycle(3, &:value) } * speed_coef
      end

      it "should return same enum without block" do
        expect(enum.in_threads.cycle(3).to_a).to eq(enum.cycle(3).to_a)
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.cycle{ raise TestException }
        end
      end
    end

    describe "grep" do
      let(:matcher){ Item::HalfMatcher.new }

      it "should fire same objects" do
        enum.each{ |o| expect(o).to receive(:touch).exactly(matcher === o ? 1 : 0).times }
        enum.in_threads.grep(matcher, &:touch_n_value)
      end

      it "should return same with block" do
        expect(enum.in_threads.grep(matcher, &:value)).to eq(enum.grep(matcher, &:value))
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.grep(matcher, &:value) }).to be < measure{ enum.grep(matcher, &:value) } * speed_coef
      end

      it "should return same without block" do
        expect(enum.in_threads.grep(matcher)).to eq(enum.grep(matcher))
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.grep(matcher){ raise TestException }
        end
      end
    end

    describe_enum_method "each_entry" do
      class EachEntryYielder
        include Enumerable
        def each
          10.times{ yield 1 }
          10.times{ yield 2, 3 }
          10.times{ yield 4, 5, 6 }
        end
      end

      let(:enum){ EachEntryYielder.new }
      let(:runner){ proc{ |o| ValueItem.new(0, o).value } }

      it "should return same result with threads" do
        expect(enum.in_threads.each_entry(&runner)).to eq(enum.each_entry(&runner))
      end

      it "should execute block for each element" do
        @order = double('order')
        expect(@order).to receive(:notify).with(1).exactly(10).times.ordered
        expect(@order).to receive(:notify).with([2, 3]).exactly(10).times.ordered
        expect(@order).to receive(:notify).with([4, 5, 6]).exactly(10).times.ordered
        @mutex = Mutex.new
        enum.in_threads.each_entry do |o|
          @mutex.synchronize{ @order.notify(o) }
          runner[]
        end
      end

      it "should run faster with threads" do
        expect(measure{ enum.in_threads.each_entry(&runner) }).to be < measure{ enum.each_entry(&runner) } * speed_coef
      end

      it "should return same enum without block" do
        expect(enum.in_threads.each_entry.to_a).to eq(enum.each_entry.to_a)
      end

      it "should raise exception in outer thread" do
        check_test_exception(enum) do |threaded|
          threaded.each_entry{ raise TestException }
        end
      end
    end

    %w[flat_map collect_concat].each do |method|
      describe_enum_method method do
        let(:enum){ 20.times.map{ |i| Item.new(i) }.each_slice(3) }
        let(:runner){ proc{ |a| a.map(&:value) } }

        it "should return same result with threads" do
          expect(enum.in_threads.send(method, &runner)).to eq(enum.send(method, &runner))
        end

        it "should fire same objects" do
          enum.send(method){ |a| a.each{ |o| expect(o).to receive(:touch).with(a).once } }
          enum.in_threads.send(method){ |a| a.each{ |o| o.touch_n_value(a) } }
        end

        it "should run faster with threads" do
          expect(measure{ enum.in_threads.send(method, &runner) }).to be < measure{ enum.send(method, &runner) } * speed_coef
        end

        it "should return same enum without block" do
          expect(enum.in_threads.send(method).to_a).to eq(enum.send(method).to_a)
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ raise TestException }
          end
        end
      end
    end

    context "unthreaded" do
      %w[inject reduce].each do |method|
        describe method do
          it "should return same result" do
            combiner = proc{ |memo, o| memo + o.value }
            expect(enum.in_threads.send(method, 0, &combiner)).to eq(enum.send(method, 0, &combiner))
          end

          it "should raise exception in outer thread" do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ raise TestException }
            end
          end
        end
      end

      %w[max min minmax sort].each do |method|
        describe method do
          it "should return same result" do
            comparer = proc{ |a, b| a.value <=> b.value }
            expect(enum.in_threads.send(method, &comparer)).to eq(enum.send(method, &comparer))
          end

          it "should raise exception in outer thread" do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ raise TestException }
            end
          end
        end
      end

      %w[to_a entries].each do |method|
        describe method do
          it "should return same result" do
            expect(enum.in_threads.send(method)).to eq(enum.send(method))
          end
        end
      end

      %w[drop take].each do |method|
        describe method do
          it "should return same result" do
            expect(enum.in_threads.send(method, 2)).to eq(enum.send(method, 2))
          end
        end
      end

      %w[first].each do |method|
        describe method do
          it "should return same result" do
            expect(enum.in_threads.send(method)).to eq(enum.send(method))
            expect(enum.in_threads.send(method, 3)).to eq(enum.send(method, 3))
          end
        end
      end

      %w[include? member?].each do |method|
        describe method do
          it "should return same result" do
            expect(enum.in_threads.send(method, enum[10])).to eq(enum.send(method, enum[10]))
          end
        end
      end

      describe_enum_method "each_with_object" do
        let(:runner){ proc{ |o, h| h[o.value] = true } }

        it "should return same result" do
          expect(enum.in_threads.each_with_object({}, &runner)).to eq(enum.each_with_object({}, &runner))
        end

        it "should raise exception in outer thread" do
          check_test_exception(enum) do |threaded|
            threaded.each_with_object({}){ raise TestException }
          end
        end
      end

      %w[chunk slice_before].each do |method|
        describe_enum_method method do
          it "should return same result" do
            expect(enum.in_threads.send(method, &:check?).to_a).to eq(enum.send(method, &:check?).to_a)
          end

          it "should raise exception in outer thread" do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ raise TestException }.to_a
            end
          end
        end
      end
    end
  end
end
