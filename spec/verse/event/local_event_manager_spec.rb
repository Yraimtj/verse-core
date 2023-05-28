# frozen_string_literal: true

require "spec_helper"

RSpec.describe Verse::Event::Manager::Local do
  around(:each) do |example|
    Timeout.timeout(5) do
      example.run
    end
  end

  before(:each) do
    @test_manager = Verse::Event::Manager::Local.new("test_service", {})
    @test_manager.start
  end

  after(:each) do
    @test_manager.stop
  end

  it "can subscribe to events" do
    @queue = Queue.new

    @test_manager.subscribe("test_event.?") do |_message, subject|
      expect(subject).to match(/^test_event\./)
      @queue.push 0 # 2 times
    end

    # Double the subscription to ensure multi-subscribe on same subject works.
    @test_manager.subscribe("test_event.?") do |_message, subject|
      expect(subject).to match(/^test_event\./)
      @queue.push 0 # 2 times
    end

    @test_manager.subscribe("test_event.another_thread") do |message, subject|
      expect(subject).to eq("test_event.another_thread")
      expect(message.content).to eq("example2")
      @queue.push 0 # 1 time
    end

    @test_manager.subscribe("*") do
      @queue.push 0 # 3 times
    end

    @test_manager.publish("test_event.example", "example")
    @test_manager.publish("test_event.another_thread", "example2")
    @test_manager.publish("another_subject.example", "example3")
    8.times{ @queue.pop } # First subscription will be called twice x2.
    expect(@queue.size).to eq(0)
  end

  context "#request" do
    it "can request" do
      @test_manager.subscribe("hello.world") do |message, _subject|
        message.reply("YES")
      end

      expect(@test_manager.request("hello.world", {}).content).to eq("YES")
    end

    it "can timeout" do
      expect{ @test_manager.request("nobody.reply", {}) }.to raise_error(
        Timeout::Error
      )
    end
  end
end
