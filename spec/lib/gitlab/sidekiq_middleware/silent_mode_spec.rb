# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SidekiqMiddleware::SilentMode, feature_category: :geo_replication do
  subject(:middleware) { described_class.new }

  let(:worker) { Object.new }
  let(:job) { { 'jid' => 'job-id', 'args' => ['private argument'] } }
  let(:logger) { instance_double(Sidekiq::Logger, warn: nil) }
  let(:blocked_error) { Gitlab::HTTP_V2::SilentModeBlockedError.new('blocked') }
  let(:wrapped_error) { wrap_error(blocked_error) }

  before do
    allow(Sidekiq).to receive(:logger).and_return(logger)
  end

  describe '#call' do
    it 'returns the result of the job' do
      expect(middleware.call(worker, job, 'test') { :result }).to eq(:result)
      expect(logger).not_to have_received(:warn)
    end

    context 'in production' do
      before do
        stub_rails_env('production')
      end

      it 'logs a warning with job context and suppresses a Silent Mode error' do
        expect(logger).to receive(:warn).with(
          hash_including(
            message: 'Job blocked by Silent Mode',
            class: 'Object',
            jid: 'job-id',
            queue: 'test',
            'exception.class' => 'Gitlab::HTTP_V2::SilentModeBlockedError'
          )
        )

        expect do
          middleware.call(worker, job, 'test') { raise Gitlab::HTTP_V2::SilentModeBlockedError }
        end.not_to raise_error
      end

      it 'does not suppress other errors' do
        expect do
          middleware.call(worker, job, 'test') { raise StandardError, 'unexpected failure' }
        end.to raise_error(StandardError, 'unexpected failure')

        expect(logger).not_to have_received(:warn)
      end

      it 'suppresses an error caused by a Silent Mode block' do
        expect do
          middleware.call(worker, job, 'test') { raise wrapped_error }
        end.not_to raise_error

        expect(logger).to have_received(:warn).with(
          hash_including(
            class: 'Object',
            'exception.class' => 'StandardError',
            'exception.cause_class' => 'Gitlab::HTTP_V2::SilentModeBlockedError'
          )
        ).once
      end

      it 'suppresses a Silent Mode block nested in the cause chain' do
        expect do
          middleware.call(worker, job, 'test') { raise wrap_error(wrapped_error) }
        end.not_to raise_error

        expect(logger).to have_received(:warn).with(
          hash_including('exception.class' => 'StandardError', 'exception.cause_class' => 'StandardError')
        ).once
      end

      it 'does not suppress an error with an unrelated cause' do
        error = wrap_error(ArgumentError.new('unrelated'))

        expect do
          middleware.call(worker, job, 'test') { raise error }
        end.to raise_error(StandardError, 'wrapped') { |raised| expect(raised).to equal(error) }

        expect(logger).not_to have_received(:warn)
      end
    end

    %w[development test].each do |environment|
      context "in #{environment}" do
        before do
          stub_rails_env(environment)
        end

        it 'propagates a Silent Mode error' do
          expect do
            middleware.call(worker, job, 'test') { raise Gitlab::HTTP_V2::SilentModeBlockedError }
          end.to raise_error(Gitlab::HTTP_V2::SilentModeBlockedError)

          expect(logger).not_to have_received(:warn)
        end

        it 'preserves a wrapped error and its Silent Mode cause' do
          expect do
            middleware.call(worker, job, 'test') { raise wrapped_error }
          end.to raise_error(StandardError, 'wrapped') { |error| expect(error).to equal(wrapped_error) }

          expect(wrapped_error.cause).to equal(blocked_error)
          expect(logger).not_to have_received(:warn)
        end
      end
    end
  end

  def wrap_error(cause)
    raise StandardError, 'wrapped', cause: cause
  rescue StandardError => error
    error
  end
end
