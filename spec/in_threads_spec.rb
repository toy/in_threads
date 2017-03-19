require 'spec_helper'
require 'in_threads'

# Test item with value
class ValueItem
  # Use fast_check? for matching
  module FastCheckMatcher
    def self.===(item)
      unless item.respond_to?(:fast_check?)
        fail "#{item.inspect} doesn't respont to fast_check?"
      end
      item.fast_check?
    end
  end

  def initialize(i, value)
    @i, @value = i, value
  end

  def ==(other)
    id == other.id if other.is_a?(self.class)
  end

  def value
    sleep
    @value
  end

  def check?
    sleep
    fast_check?
  end

  def fast_check?
    !!@value
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

# Test item with random value
class RandItem < ValueItem
  def initialize(i)
    super(i, Kernel.rand)
  end

  def fast_check?
    @value < 0.5
  end
end

# Pure class with Enumerable instead of Array
class TestEnum
  include Enumerable

  def initialize(count, &block)
    @items = Array.new(count){ |i| block[i] }
  end

  def each(&block)
    @items.each(&block)
    self
  end
end

class TestException < StandardError; end

ENUM_METHODS = Enumerable.instance_methods.map(&:to_s)
def describe_enum_method(method, &block)
  if ENUM_METHODS.include?(method)
    describe "##{method}", &block
  else
    describe "##{method}" do
      it 'is not defined' do
        exception_regexp =
          /^undefined method `#{Regexp.escape(method)}' .*\bInThreads\b/
        expect{ enum.in_threads.send(method) }.
          to raise_error(NoMethodError, exception_regexp)
      end
    end
  end
end

describe 'in_threads' do
  let(:items){ Array.new(30){ |i| RandItem.new(i) } }
  let(:enum){ TestEnum.new(items) }

  # small coefficient, should be more if sleep time coefficient is bigger
  let(:speed_coef){ 0.666 }

  def measure
    start = Time.now
    yield
    Time.now - start
  end

  describe 'consistency' do
    describe 'verifying params' do
      it 'complains about using with non enumerable' do
        expect{ InThreads.new(1) }.to raise_error(ArgumentError)
      end

      [1..10, 10.times, {}, []].each do |o|
        it "does not complain about using with #{o.class}" do
          expect{ InThreads.new(o) }.not_to raise_error
        end
      end

      it 'complains about using less than 2 threads' do
        expect{ 10.times.in_threads(1) }.to raise_error(ArgumentError)
      end

      it 'does not complain about using 2 or more threads' do
        expect{ 10.times.in_threads(2) }.not_to raise_error
      end
    end

    describe 'in_threads method' do
      it 'does not change existing instance' do
        threaded = enum.in_threads(10)
        expect{ threaded.in_threads(20) }.not_to change(threaded, :thread_count)
      end

      it 'creates new instance with different title when called on '\
          'WithProgress' do
        threaded = enum.in_threads(10)
        tthreaded = threaded.in_threads(20)
        expect(threaded.thread_count).to eq(10)
        expect(tthreaded.thread_count).to eq(20)
        expect(tthreaded.class).to eq(threaded.class)
        expect(tthreaded.object_id).not_to eq(threaded.object_id)
        expect(tthreaded.enumerable).to eq(threaded.enumerable)
      end
    end

    describe 'thread count' do
      let(:items){ Array.new(100){ |i| ValueItem.new(i, i < 50) } }

      %w[each map all?].each do |method|
        it "runs in specified number of threads for #{method}" do
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

    describe 'underlying enumerable usage' do
      %w[each map all?].each do |method|
        it "calls underlying enumerable.each only once for #{method}" do
          enum = Array.new(100){ |i| ValueItem.new(i, i < 50) }

          expect(enum).to receive(:each).once.and_call_original
          enum.in_threads(13).send(method, &:check?)
        end
      end

      it 'does not yield all elements when not needed' do
        enum = []
        def enum.each
          100.times{ yield 1 }
          fail
        end

        enum.in_threads(13).all?{ false }
      end
    end

    describe 'block arguments' do
      before do
        def enum.each
          yield
          yield 1
          yield 2, 3
          yield 4, 5, 6
        end
      end

      it 'passes all to methods ignoring block result' do
        o = double
        enum.each do |*args|
          expect(o).to receive(:notify).with(args)
        end
        enum.in_threads.each do |*args|
          o.notify(args)
        end
      end

      it 'passes all to methods using block result' do
        o = double
        enum.each do |*args|
          expect(o).to receive(:notify).with(args)
        end
        enum.in_threads.map do |*args|
          o.notify(args)
        end
      end
    end
  end

  describe 'methods' do
    missing_methods =
      (Enumerable.instance_methods - InThreads.instance_methods).map(&:to_sym)
    (missing_methods - InThreads::INCOMPATIBLE_METHODS).each do |method|
      pending method
    end

    def check_test_exception(enum, &block)
      expect{ block[enum.in_threads] }.to raise_exception(TestException)
      expect{ block[enum.in_threads(1000)] }.to raise_exception(TestException)
    end

    describe '#each' do
      it 'returns same enum after running' do
        expect(enum.in_threads.each(&:value)).to eq(enum)
      end

      it 'executes block for each element' do
        enum.each{ |o| expect(o).to receive(:touch).once }
        enum.in_threads.each(&:touch_n_value)
      end

      it 'runs faster with threads', :retry => 3 do
        expect(measure{ enum.in_threads.each(&:value) }).
          to be < measure{ enum.each(&:value) } * speed_coef
      end

      it 'runs faster with more threads', :retry => 3 do
        expect(measure{ enum.in_threads(10).each(&:value) }).
          to be < measure{ enum.in_threads(2).each(&:value) } * speed_coef
      end

      it 'returns same enum without block' do
        expect(enum.in_threads.each.to_a).to eq(enum.each.to_a)
      end

      it 'raises exception in outer thread' do
        check_test_exception(enum) do |threaded|
          threaded.each{ fail TestException }
        end
      end
    end

    %w[each_with_index enum_with_index].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |o, _i| o.value } }

        it 'returns same result with threads' do
          expect(enum.in_threads.send(method, &runner)).
            to eq(enum.send(method, &runner))
        end

        it 'fires same objects' do
          enum.send(method){ |o, i| expect(o).to receive(:touch).with(i).once }
          enum.in_threads.send(method){ |o, i| o.touch_n_value(i) }
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, &runner) }).
            to be < measure{ enum.send(method, &runner) } * speed_coef
        end

        it 'returns same enum without block' do
          expect(enum.in_threads.send(method).to_a).
            to eq(enum.send(method).to_a)
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ fail TestException }
          end
        end
      end
    end

    describe '#reverse_each' do
      it 'returns same result with threads' do
        expect(enum.in_threads.reverse_each(&:value)).
          to eq(enum.reverse_each(&:value))
      end

      it 'fires same objects in reverse order' do
        @order = double('order', :notify => nil)
        expect(@order).to receive(:notify).with(items.last).ordered
        expect(@order).to receive(:notify).with(items[items.length / 2]).ordered
        expect(@order).to receive(:notify).with(items.first).ordered
        enum.each{ |o| expect(o).to receive(:touch).once }
        @mutex = Mutex.new
        enum.in_threads.reverse_each do |o|
          @mutex.synchronize{ @order.notify(o) }
          o.touch_n_value
        end
      end

      it 'runs faster with threads', :retry => 3 do
        expect(measure{ enum.in_threads.reverse_each(&:value) }).
          to be < measure{ enum.reverse_each(&:value) } * speed_coef
      end

      it 'returns same enum without block' do
        expect(enum.in_threads.reverse_each.to_a).to eq(enum.reverse_each.to_a)
      end

      it 'raises exception in outer thread' do
        check_test_exception(enum) do |threaded|
          threaded.reverse_each{ fail TestException }
        end
      end
    end

    %w[
      all? any? none? one?
      detect find find_index drop_while take_while
    ].each do |method|
      describe "##{method}" do
        let(:items){ Array.new(100){ |i| ValueItem.new(i, i.odd?) } }

        it 'returns same result with threads' do
          expect(enum.in_threads.send(method, &:check?)).
            to eq(enum.send(method, &:check?))
        end

        it 'fires same objects but not all' do
          a = []
          enum.send(method) do |o|
            a << o
            o.check?
          end

          @a = []
          @mutex = Mutex.new
          enum.in_threads.send(method) do |o|
            @mutex.synchronize{ @a << o }
            o.check?
          end

          expect(@a.length).to be >= a.length
          expect(@a.length).to be <= items.length * 0.5
        end

        it 'runs faster with threads', :retry => 3 do
          boolean = %w[all? drop_while take_while].include?(method)
          enum = Array.new(30){ |i| ValueItem.new(i, boolean) }
          expect(measure{ enum.in_threads.send(method, &:check?) }).
            to be < measure{ enum.send(method, &:check?) } * speed_coef
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ fail TestException }
          end
        end
      end
    end

    %w[partition find_all select reject count].each do |method|
      describe "##{method}" do
        it 'returns same result with threads' do
          expect(enum.in_threads.send(method, &:check?)).
            to eq(enum.send(method, &:check?))
        end

        it 'fires same objects' do
          enum.send(method){ |o| expect(o).to receive(:touch).once }
          enum.in_threads.send(method, &:touch_n_check?)
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, &:check?) }).
            to be < measure{ enum.send(method, &:check?) } * speed_coef
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ fail TestException }
          end
        end
      end
    end

    %w[
      collect map
      group_by max_by min_by minmax_by sort_by
      sum uniq
    ].each do |method|
      describe_enum_method method do
        it 'returns same result with threads' do
          expect(enum.in_threads.send(method, &:value)).
            to eq(enum.send(method, &:value))
        end

        it 'fires same objects' do
          enum.send(method){ |o| expect(o).to receive(:touch).once; 0 }
          enum.in_threads.send(method, &:touch_n_value)
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, &:value) }).
            to be < measure{ enum.send(method, &:value) } * speed_coef
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ fail TestException }
          end
        end
      end
    end

    %w[each_cons each_slice enum_slice enum_cons].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |a| a.each(&:value) } }

        it 'fires same objects' do
          enum.send(method, 3) do |a|
            expect(a.first).to receive(:touch).with(a).once
          end
          enum.in_threads.send(method, 3){ |a| a.first.touch_n_value(a) }
        end

        it 'returns same with block' do
          expect(enum.in_threads.send(method, 3, &runner)).
            to eq(enum.send(method, 3, &runner))
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, 3, &runner) }).
            to be < measure{ enum.send(method, 3, &runner) } * speed_coef
        end

        it 'returns same without block' do
          expect(enum.in_threads.send(method, 3).to_a).
            to eq(enum.send(method, 3).to_a)
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method, 3){ fail TestException }
          end
        end
      end
    end

    describe '#zip' do
      let(:runner){ proc{ |a| a.each(&:value) } }

      it 'fires same objects' do
        enum.zip(enum, enum) do |a|
          expect(a.first).to receive(:touch).with(a).once
        end

        enum.in_threads.zip(enum, enum) do |a|
          a.first.touch_n_value(a)
        end
      end

      it 'returns same with block' do
        expect(enum.in_threads.zip(enum, enum, &runner)).
          to eq(enum.zip(enum, enum, &runner))
      end

      it 'runs faster with threads', :retry => 3 do
        expect(measure{ enum.in_threads.zip(enum, enum, &runner) }).
          to be < measure{ enum.zip(enum, enum, &runner) } * speed_coef
      end

      it 'returns same without block' do
        expect(enum.in_threads.zip(enum, enum)).to eq(enum.zip(enum, enum))
      end

      it 'raises exception in outer thread' do
        check_test_exception(enum) do |threaded|
          threaded.zip(enum, enum){ fail TestException }
        end
      end
    end

    describe '#cycle' do
      it 'fires same objects' do
        enum.cycle(1){ |o| expect(o).to receive(:touch).exactly(3).times }
        enum.in_threads.cycle(3, &:touch_n_value)
      end

      it 'runs faster with threads', :retry => 3 do
        expect(measure{ enum.in_threads.cycle(3, &:value) }).
          to be < measure{ enum.cycle(3, &:value) } * speed_coef
      end

      it 'returns same enum without block' do
        expect(enum.in_threads.cycle(3).to_a).to eq(enum.cycle(3).to_a)
      end

      it 'raises exception in outer thread' do
        check_test_exception(enum) do |threaded|
          threaded.cycle{ fail TestException }
        end
      end
    end

    %w[grep grep_v].each do |method|
      describe_enum_method method do
        let(:matcher){ ValueItem::FastCheckMatcher }

        it 'fires same objects' do
          enum.each do |o|
            if o.fast_check? == (method == 'grep')
              expect(o).to receive(:touch)
            else
              expect(o).not_to receive(:touch)
            end
          end
          enum.in_threads.send(method, matcher, &:touch_n_value)
        end

        it 'returns same with block' do
          expect(enum.in_threads.send(method, matcher, &:value)).
            to eq(enum.send(method, matcher, &:value))
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, matcher, &:value) }).
            to be < measure{ enum.send(method, matcher, &:value) } * speed_coef
        end

        it 'returns same without block' do
          expect(enum.in_threads.send(method, matcher)).
            to eq(enum.send(method, matcher))
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method, matcher){ fail TestException }
          end
        end
      end
    end

    describe_enum_method 'each_entry' do
      before do
        def enum.each
          10.times{ yield }
          10.times{ yield 1 }
          10.times{ yield 2, 3 }
          10.times{ yield 4, 5, 6 }
        end
      end
      let(:runner){ proc{ |o| ValueItem.new(0, o).value } }

      it 'returns same result with threads' do
        expect(enum.in_threads.each_entry(&runner)).
          to eq(enum.each_entry(&runner))
      end

      it 'executes block for each element' do
        @o = double('order')
        enum.each_entry do |*o|
          expect(@o).to receive(:notify).with(o)
        end
        @mutex = Mutex.new
        enum.in_threads.each_entry do |*o|
          @mutex.synchronize{ @o.notify(o) }
          runner[]
        end
      end

      it 'runs faster with threads', :retry => 3 do
        expect(measure{ enum.in_threads.each_entry(&runner) }).
          to be < measure{ enum.each_entry(&runner) } * speed_coef
      end

      it 'returns same enum without block' do
        expect(enum.in_threads.each_entry.to_a).to eq(enum.each_entry.to_a)
      end

      it 'raises exception in outer thread' do
        check_test_exception(enum) do |threaded|
          threaded.each_entry{ fail TestException }
        end
      end
    end

    %w[flat_map collect_concat].each do |method|
      describe_enum_method method do
        let(:items){ Array.new(20){ |i| RandItem.new(i) }.each_slice(3).to_a }
        let(:runner){ proc{ |a| a.map(&:value) } }

        it 'returns same result with threads' do
          expect(enum.in_threads.send(method, &runner)).
            to eq(enum.send(method, &runner))
        end

        it 'fires same objects' do
          enum.send(method) do |a|
            a.each do |o|
              expect(o).to receive(:touch).with(a).once
            end
          end

          enum.in_threads.send(method) do |a|
            a.each do |o|
              o.touch_n_value(a)
            end
          end
        end

        it 'runs faster with threads', :retry => 3 do
          expect(measure{ enum.in_threads.send(method, &runner) }).
            to be < measure{ enum.send(method, &runner) } * speed_coef
        end

        it 'returns same enum without block' do
          expect(enum.in_threads.send(method).to_a).
            to eq(enum.send(method).to_a)
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.send(method){ fail TestException }
          end
        end
      end
    end

    context 'unthreaded' do
      %w[inject reduce].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            combiner = proc{ |memo, o| memo + o.value }
            expect(enum.in_threads.send(method, 0, &combiner)).
              to eq(enum.send(method, 0, &combiner))
          end

          it 'raises exception in outer thread' do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ fail TestException }
            end
          end
        end
      end

      %w[max min minmax sort].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            comparer = proc{ |a, b| a.value <=> b.value }
            expect(enum.in_threads.send(method, &comparer)).
              to eq(enum.send(method, &comparer))
          end

          it 'raises exception in outer thread' do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ fail TestException }
            end
          end
        end
      end

      %w[to_a entries].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            expect(enum.in_threads.send(method)).to eq(enum.send(method))
          end
        end
      end

      %w[drop take].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            expect(enum.in_threads.send(method, 2)).to eq(enum.send(method, 2))
          end
        end
      end

      %w[first].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            expect(enum.in_threads.send(method)).to eq(enum.send(method))
            expect(enum.in_threads.send(method, 3)).to eq(enum.send(method, 3))
          end
        end
      end

      %w[include? member?].each do |method|
        describe "##{method}" do
          it 'returns same result' do
            expect(enum.in_threads.send(method, items[10])).
              to eq(enum.send(method, items[10]))
          end
        end
      end

      describe_enum_method 'each_with_object' do
        let(:runner){ proc{ |o, h| h[o.value] = true } }

        it 'returns same result' do
          expect(enum.in_threads.each_with_object({}, &runner)).
            to eq(enum.each_with_object({}, &runner))
        end

        it 'raises exception in outer thread' do
          check_test_exception(enum) do |threaded|
            threaded.each_with_object({}){ fail TestException }
          end
        end
      end

      %w[chunk slice_before slice_after].each do |method|
        describe_enum_method method do
          it 'returns same result' do
            expect(enum.in_threads.send(method, &:check?).to_a).
              to eq(enum.send(method, &:check?).to_a)
          end

          it 'raises exception in outer thread' do
            check_test_exception(enum) do |threaded|
              threaded.send(method){ fail TestException }.to_a
            end
          end
        end
      end
    end
  end
end
