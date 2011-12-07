require File.dirname(__FILE__) + '/spec_helper.rb'

class Item
  def initialize(i)
    @i, @rand = i, rand
  end

  class MiddleMatcher
    def ===(item)
      raise "#{item.inspect} is not an Item" unless item.is_a?(Item)
      (0.25..0.75) === item.instance_variable_get(:@rand)
    end
  end

  def work
    sleep @rand * 0.008
  end

  def work_more
    sleep @rand * 0.1
  end

  def value
    work; @rand
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
end

class ValueItem < Item
  def initialize(i, value)
    super(i)
    @value = value
  end

  def value
    work; @value
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

  # it "should define all Enumerable methods" do
  #   (Enumerable.instance_methods - 10.times.in_threads.class.instance_methods).should == []
  # end

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

  describe "each" do
    it "should return same enum after running" do
      enum.in_threads.each(&:value).should == enum
    end

    it "should execute block for each element" do
      enum.each{ |o| o.should_receive(:touch).once }
      enum.in_threads.each(&:touch_n_value)
    end

    it "should run faster with threads" do
      measure{ enum.in_threads.each(&:work) }.should < measure{ enum.each(&:work) } * speed_coef
    end

    it "should run faster with more threads" do
      measure{ enum.in_threads(10).each(&:work) }.should < measure{ enum.in_threads(2).each(&:work) } * speed_coef
    end

    it "should return same enum without block" do
      enum.in_threads.each.to_a.should == enum.each.to_a
    end

    it "should run in specified number of threads" do
      enum = 100.times.map{ |i| Item.new(i) }

      @thread_count = 0
      @max_thread_count = 0
      @mutex = Mutex.new
      enum.in_threads(13).each do |o|
        @mutex.synchronize do
          @thread_count += 1
          @max_thread_count = [@max_thread_count, @thread_count].max
        end
        o.work_more
        @mutex.synchronize do
          @thread_count -= 1
        end
      end
      @thread_count.should == 0
      @max_thread_count.should == 13
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
        @a.length.should <= enum.length / 2
      end

      it "should run faster with threads" do
        value = %w[all? drop_while take_while].include?(method)
        enum = 30.times.map{ |i| ValueItem.new(i, value) }
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
      measure{ enum.in_threads.cycle(3, &:work) }.should < measure{ enum.cycle(3, &:work) } * speed_coef
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
  end
end
