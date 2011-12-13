require File.dirname(__FILE__) + '/spec_helper.rb'

class Item
  attr_reader :rand
  def initialize(i)
    @i = i
    @rand = Kernel.rand
    @sleep = Kernel.rand
  end

  class MiddleMatcher
    def ===(item)
      raise "#{item.inspect} is not an Item" unless item.is_a?(Item)
      (0.25..0.75) === item.rand
    end
  end

  def value
    sleep; rand
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

private

  def sleep
    Kernel.sleep @sleep * 0.01
  end
end

class ValueItem < Item
  def initialize(i, value)
    super(i)
    @value = value
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
      exception_regexp = /^undefined method `#{Regexp.escape(method)}' for #<InThreads:0x[0-9a-f]+>$/
      proc{ enum.in_threads.send(method) }.should raise_error(NoMethodError, exception_regexp)
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
        proc{ InThreads.new(1) }.should raise_error(ArgumentError)
      end

      [1..10, 10.times, {}, []].each do |o|
        it "should complain about using with #{o.class}" do
          proc{ InThreads.new(o) }.should_not raise_error
        end
      end

      it "should complain about using less than 2 threads" do
        proc{ 10.times.in_threads(1) }.should raise_error(ArgumentError)
      end

      it "should not complain about using 2 or more threads" do
        proc{ 10.times.in_threads(2) }.should_not raise_error
      end
    end

    describe "in_threads" do
      it "should not change existing instance" do
        threaded = enum.in_threads(10)
        proc{ threaded.in_threads(20) }.should_not change(threaded, :thread_count)
      end

      it "should create new instance with different title when called on WithProgress" do
        threaded = enum.in_threads(10)
        tthreaded = threaded.in_threads(20)
        threaded.thread_count.should == 10
        tthreaded.thread_count.should == 20
        tthreaded.class.should == threaded.class
        tthreaded.object_id.should_not == threaded.object_id
        tthreaded.enumerable.should == threaded.enumerable
      end
    end

    describe "thread count" do
      let(:enum){ 100.times.map{ |i| ValueItem.new(i, i < 50) } }

      %w[each map all?].each do |method|
        it "should run in specified number of threads for #{method}" do
          @thread_count = 0
          @max_thread_count = 0
          @mutex = Mutex.new
          enum.in_threads(13).send(method) do |o|
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
          @thread_count.should == 0
          @max_thread_count.should == 13
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
          enum.should_receive(:each_started).once
          enum.in_threads(13).send(method, &:check?)
        end
      end
    end
  end

  describe "methods" do
    (Enumerable.instance_methods - 10.times.in_threads.class.instance_methods).each do |method|
      pending method
    end

    describe "each" do
      it "should return same enum after running" do
        enum.in_threads.each(&:value).should == enum
      end

      it "should execute block for each element" do
        enum.each{ |o| o.should_receive(:touch).once }
        enum.in_threads.each(&:touch_n_value)
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.each(&:value) }.should < measure{ enum.each(&:value) } * speed_coef
      end

      it "should run faster with more threads" do
        measure{ enum.in_threads(10).each(&:value) }.should < measure{ enum.in_threads(2).each(&:value) } * speed_coef
      end

      it "should return same enum without block" do
        enum.in_threads.each.to_a.should == enum.each.to_a
      end
    end

    %w[each_with_index enum_with_index].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |o, i| o.value } }

        it "should return same result with threads" do
          enum.in_threads.send(method, &runner).should == enum.send(method, &runner)
        end

        it "should fire same objects" do
          enum.send(method){ |o, i| o.should_receive(:touch).with(i).once }
          enum.in_threads.send(method){ |o, i| o.touch_n_value(i) }
        end

        it "should run faster with threads" do
          measure{ enum.in_threads.send(method, &runner) }.should < measure{ enum.send(method, &runner) } * speed_coef
        end

        it "should return same enum without block" do
          enum.in_threads.send(method).to_a.should == enum.send(method).to_a
        end
      end
    end

    describe "reverse_each" do
      it "should return same result with threads" do
        enum.in_threads.reverse_each(&:value).should == enum.reverse_each(&:value)
      end

      it "should fire same objects in reverse order" do
        @order = mock('order', :notify => nil)
        @order.should_receive(:notify).with(enum.last).ordered
        @order.should_receive(:notify).with(enum[enum.length / 2]).ordered
        @order.should_receive(:notify).with(enum.first).ordered
        enum.reverse_each{ |o| o.should_receive(:touch).once }
        @mutex = Mutex.new
        enum.in_threads.reverse_each do |o|
          @mutex.synchronize{ @order.notify(o) }
          o.touch_n_value
        end
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.reverse_each(&:value) }.should < measure{ enum.reverse_each(&:value) } * speed_coef
      end

      it "should return same enum without block" do
        enum.in_threads.reverse_each.to_a.should == enum.reverse_each.to_a
      end
    end

    %w[
      all? any? none? one?
      detect find find_index drop_while take_while
    ].each do |method|
      describe method do
        let(:enum){ 100.times.map{ |i| ValueItem.new(i, i % 2 == 1) } }

        it "should return same result with threads" do
          enum.in_threads.send(method, &:check?).should == enum.send(method, &:check?)
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

          @a.length.should >= a.length
          @a.length.should <= enum.length * 0.5
        end

        it "should run faster with threads" do
          boolean = %w[all? drop_while take_while].include?(method)
          enum = 30.times.map{ |i| ValueItem.new(i, boolean) }
          measure{ enum.in_threads.send(method, &:check?) }.should < measure{ enum.send(method, &:check?) } * speed_coef
        end
      end
    end

    %w[partition find_all select reject count].each do |method|
      describe method do
        it "should return same result with threads" do
          enum.in_threads.send(method, &:check?).should == enum.send(method, &:check?)
        end

        it "should fire same objects" do
          enum.send(method){ |o| o.should_receive(:touch).once }
          enum.in_threads.send(method, &:touch_n_check?)
        end

        it "should run faster with threads" do
          measure{ enum.in_threads.send(method, &:check?) }.should < measure{ enum.send(method, &:check?) } * speed_coef
        end
      end
    end

    %w[collect map group_by max_by min_by minmax_by sort_by].each do |method|
      describe method do
        it "should return same result with threads" do
          enum.in_threads.send(method, &:value).should == enum.send(method, &:value)
        end

        it "should fire same objects" do
          enum.send(method){ |o| o.should_receive(:touch).once; 0 }
          enum.in_threads.send(method, &:touch_n_value)
        end

        it "should run faster with threads" do
          measure{ enum.in_threads.send(method, &:value) }.should < measure{ enum.send(method, &:value) } * speed_coef
        end
      end
    end

    %w[each_cons each_slice enum_slice enum_cons].each do |method|
      describe_enum_method method do
        let(:runner){ proc{ |a| a.each(&:value) } }

        it "should fire same objects" do
          enum.send(method, 3){ |a| a.first.should_receive(:touch).with(a).once }
          enum.in_threads.send(method, 3){ |a| a.first.touch_n_value(a) }
        end

        it "should return same with block" do
          enum.in_threads.send(method, 3, &runner).should == enum.send(method, 3, &runner)
        end

        it "should run faster with threads" do
          measure{ enum.in_threads.send(method, 3, &runner) }.should < measure{ enum.send(method, 3, &runner) } * speed_coef
        end

        it "should return same without block" do
          enum.in_threads.send(method, 3).to_a.should == enum.send(method, 3).to_a
        end
      end
    end

    describe "zip" do
      let(:runner){ proc{ |a| a.each(&:value) } }

      it "should fire same objects" do
        enum.zip(enum, enum){ |a| a.first.should_receive(:touch).with(a).once }
        enum.in_threads.zip(enum, enum){ |a| a.first.touch_n_value(a) }
      end

      it "should return same with block" do
        enum.in_threads.zip(enum, enum, &runner).should == enum.zip(enum, enum, &runner)
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.zip(enum, enum, &runner) }.should < measure{ enum.zip(enum, enum, &runner) } * speed_coef
      end

      it "should return same without block" do
        enum.in_threads.zip(enum, enum).should == enum.zip(enum, enum)
      end
    end

    describe "cycle" do
      it "should fire same objects" do
        enum.cycle(1){ |o| o.should_receive(:touch).exactly(3).times }
        enum.in_threads.cycle(3, &:touch_n_value)
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.cycle(3, &:value) }.should < measure{ enum.cycle(3, &:value) } * speed_coef
      end

      it "should return same enum without block" do
        enum.in_threads.cycle(3).to_a.should == enum.cycle(3).to_a
      end
    end

    describe "grep" do
      let(:matcher){ Item::MiddleMatcher.new }

      it "should fire same objects" do
        enum.each{ |o| o.should_receive(:touch).exactly(matcher === o ? 1 : 0).times }
        enum.in_threads.grep(matcher, &:touch_n_value)
      end

      it "should return same with block" do
        enum.in_threads.grep(matcher, &:value).should == enum.grep(matcher, &:value)
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.grep(matcher, &:value) }.should < measure{ enum.grep(matcher, &:value) } * speed_coef
      end

      it "should return same without block" do
        enum.in_threads.grep(matcher).should == enum.grep(matcher)
      end
    end

    describe_enum_method "each_entry" do
      class EachEntryYielder
        include Enumerable
        def each
          10.times{ yield 1 }
          10.times{ yield 2, 3 }
          10.times{ yield }
        end
      end

      let(:enum){ EachEntryYielder.new }
      let(:runner){ proc{ |o| ValueItem.new(0, o).value } }

      it "should return same result with threads" do
        enum.in_threads.each_entry(&runner).should == enum.each_entry(&runner)
      end

      it "should execute block for each element" do
        @order = mock('order')
        @order.should_receive(:notify).with(1).exactly(10).times.ordered
        @order.should_receive(:notify).with([2, 3]).exactly(10).times.ordered
        @order.should_receive(:notify).with(nil).exactly(10).times.ordered
        @mutex = Mutex.new
        enum.in_threads.each_entry do |o|
          @mutex.synchronize{ @order.notify(o) }
          runner[]
        end
      end

      it "should run faster with threads" do
        measure{ enum.in_threads.each_entry(&runner) }.should < measure{ enum.each_entry(&runner) } * speed_coef
      end

      it "should return same enum without block" do
        enum.in_threads.each_entry.to_a.should == enum.each_entry.to_a
      end
    end

    %w[flat_map collect_concat].each do |method|
      describe_enum_method method do
        let(:enum){ 20.times.map{ |i| Item.new(i) }.each_slice(3) }
        let(:runner){ proc{ |a| a.map(&:value) } }

        it "should return same result with threads" do
          enum.in_threads.send(method, &runner).should == enum.send(method, &runner)
        end

        it "should fire same objects" do
          enum.send(method){ |a| a.each{ |o| o.should_receive(:touch).with(a).once } }
          enum.in_threads.send(method){ |a| a.each{ |o| o.touch_n_value(a) } }
        end

        it "should run faster with threads" do
          measure{ enum.in_threads.send(method, &runner) }.should < measure{ enum.send(method, &runner) } * speed_coef
        end

        it "should return same enum without block" do
          enum.in_threads.send(method).to_a.should == enum.send(method).to_a
        end
      end
    end

    context "unthreaded" do
      %w[inject reduce].each do |method|
        describe method do
          it "should return same result" do
            combiner = proc{ |memo, o| memo + o.value }
            enum.in_threads.send(method, 0, &combiner).should == enum.send(method, 0, &combiner)
          end
        end
      end

      %w[max min minmax sort].each do |method|
        describe method do
          it "should return same result" do
            comparer = proc{ |a, b| a.value <=> b.value }
            enum.in_threads.send(method, &comparer).should == enum.send(method, &comparer)
          end
        end
      end

      %w[to_a entries].each do |method|
        describe method do
          it "should return same result" do
            enum.in_threads.send(method).should == enum.send(method)
          end
        end
      end

      %w[drop take].each do |method|
        describe method do
          it "should return same result" do
            enum.in_threads.send(method, 2).should == enum.send(method, 2)
          end
        end
      end

      %w[first].each do |method|
        describe method do
          it "should return same result" do
            enum.in_threads.send(method).should == enum.send(method)
            enum.in_threads.send(method, 3).should == enum.send(method, 3)
          end
        end
      end

      %w[include? member?].each do |method|
        describe method do
          it "should return same result" do
            enum.in_threads.send(method, enum[10]).should == enum.send(method, enum[10])
          end
        end
      end

      describe_enum_method "each_with_object" do
        let(:runner){ proc{ |o, h| h[o.value] = true } }

        it "should return same result" do
          enum.in_threads.each_with_object({}, &runner).should == enum.each_with_object({}, &runner)
        end
      end

      %w[chunk slice_before].each do |method|
        describe_enum_method method do
          it "should return same result" do
            enum.in_threads.send(method, &:check?).to_a.should == enum.send(method, &:check?).to_a
          end
        end
      end
    end
  end
end
