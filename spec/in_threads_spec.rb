require File.dirname(__FILE__) + '/spec_helper.rb'

describe InThreads do
  before :each do
    srand 1
    @a = (1..30).map{ |i| mock(:"e#{i}", :hello => nil, :value => i, :rand => rand * 0.01) }
    @sleepy_prock = proc{ |e| sleep(e.rand); e.hello; e.value }
    @sleepy_prock_a = proc{ |e| sleep(e.inject{ |sum, e| e.rand }); e.hash }
  end

  def measure
    start = Time.now
    yield
    Time.now - start
  end

  it "should execute block for each element" do
    @a.each{ |e| e.should_receive(:hello) }
    @a.in_threads.each(&:hello)
  end

  it "should run faster than without threads" do
    (measure{ @a.in_threads.each(&@sleepy_prock) } * 2).should be < measure{ @a.each(&@sleepy_prock) }
  end

  it "should run not much slower than max of block running times if ran simultaneously" do
    measure{ (1..95).in_threads(100).each{ |i| sleep(i * 0.01) } }.should be < 1.0
  end

  it "should run faster when ran with more threads" do
    (measure{ @a.in_threads(20).each(&@sleepy_prock) } * 2).should be < measure{ @a.in_threads(2).each(&@sleepy_prock) }
  end

  %w(each map any? all? none?).each do |method|
    it "should return same as without thread for #{method}" do
      @a.in_threads.send(method, &@sleepy_prock).should == @a.send(method, &@sleepy_prock)
    end
  end

  it "should return same as without thread for .each_slice" do
    @a.in_threads.each_slice(2, &@sleepy_prock_a).should == @a.each_slice(2, &@sleepy_prock_a)
  end
end
