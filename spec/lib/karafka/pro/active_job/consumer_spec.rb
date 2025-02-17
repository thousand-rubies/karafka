# frozen_string_literal: true

require 'karafka/pro/base_consumer'
require 'karafka/pro/active_job/consumer'
require 'karafka/pro/routing/topic_extensions'
require 'karafka/pro/processing/coordinator'

RSpec.describe_current do
  subject(:consumer) do
    topic.singleton_class.prepend Karafka::Pro::Routing::TopicExtensions

    described_class.new.tap do |instance|
      instance.client = client
      instance.coordinator = coordinator
      instance.topic = topic
    end
  end

  let(:client) { instance_double(Karafka::Connection::Client, pause: true) }
  let(:topic) { build(:routing_topic) }
  let(:coordinator) { build(:processing_coordinator_pro) }
  let(:messages) { [message1, message2] }
  let(:message1) { build(:messages_message, raw_payload: payload1.to_json) }
  let(:message2) { build(:messages_message, raw_payload: payload2.to_json) }
  let(:payload1) { { '1' => '2' } }
  let(:payload2) { { '3' => '4' } }

  before do
    coordinator.start(messages)
    coordinator.increment
  end

  it { expect(described_class).to be < Karafka::Pro::BaseConsumer }

  describe '#on_before_enqueue behaviour' do
    before { allow(consumer).to receive(:pause) }

    context 'when it is not a lrj' do
      it 'expect not to pause' do
        consumer.on_before_enqueue

        expect(consumer).not_to have_received(:pause)
      end
    end

    context 'when it is a lrj' do
      before do
        consumer.messages = messages
        topic.long_running_job = true
      end

      it 'expect to pause forever on our first message' do
        consumer.on_before_enqueue

        expect(consumer).to have_received(:pause).with(message1.offset, 1_000_000_000_000)
      end
    end
  end

  describe '#consume' do
    context 'when messages are available to the consumer and it is not a lrj' do
      before do
        consumer.messages = messages

        allow(client).to receive(:mark_as_consumed).with(messages.first).and_return(true)
        allow(client).to receive(:mark_as_consumed).with(messages.last).and_return(true)

        allow(ActiveJob::Base).to receive(:execute).with(payload1)
        allow(ActiveJob::Base).to receive(:execute).with(payload2)
      end

      it 'expect to decode them and run active job executor' do
        consumer.consume

        expect(ActiveJob::Base).to have_received(:execute).with(payload1)
        expect(ActiveJob::Base).to have_received(:execute).with(payload2)
      end

      it 'expect to mark as consumed on each message' do
        consumer.consume

        expect(client).to have_received(:mark_as_consumed).with(messages.first)
        expect(client).to have_received(:mark_as_consumed).with(messages.last)
      end
    end

    context 'when messages are available to the consumer and it is virtual partition' do
      before do
        consumer.messages = messages

        allow(client).to receive(:mark_as_consumed)

        allow(ActiveJob::Base).to receive(:execute).with(payload1)
        allow(ActiveJob::Base).to receive(:execute).with(payload2)

        topic.virtual_partitions(partitioner: ->(_) {})
      end

      it 'expect to decode them and run active job executor' do
        consumer.consume

        expect(ActiveJob::Base).to have_received(:execute).with(payload1)
        expect(ActiveJob::Base).to have_received(:execute).with(payload2)
      end

      it 'expect not to mark each message during consumption' do
        consumer.consume

        expect(client).not_to have_received(:mark_as_consumed)
      end
    end

    context 'when messages are available but partition got revoked prior to processing' do
      before do
        consumer.messages = messages
        consumer.on_revoked

        allow(client).to receive(:mark_as_consumed).with(messages.first).and_return(true)
        allow(client).to receive(:mark_as_consumed).with(messages.last).and_return(true)

        allow(ActiveJob::Base).to receive(:execute).with(payload1)
        allow(ActiveJob::Base).to receive(:execute).with(payload2)
      end

      it 'expect not to run anything' do
        consumer.consume

        expect(ActiveJob::Base).not_to have_received(:execute).with(payload1)
        expect(ActiveJob::Base).not_to have_received(:execute).with(payload2)
      end
    end
  end
end
