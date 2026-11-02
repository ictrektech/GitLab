# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ActionCatalog, feature_category: :security_policy_management do
  describe '.known?' do
    it 'knows the dispatched action type' do
      expect(described_class).to be_known('log_audit_trail')
    end

    it 'knows block, which the fence consumes: a block decision is not an unhandled action' do
      expect(described_class).to be_known('block')
    end

    it 'does not know set_setting until its executor ships' do
      expect(described_class).not_to be_known('set_setting')
    end
  end

  describe '.executor_for' do
    it 'runs the audit trail in every mode, because an audit-mode policy exists for it' do
      [true, false].each do |enforce|
        expect(described_class.executor_for('log_audit_trail', enforce: enforce))
          .to eq('Govern::PolicyEngine::LogAuditTrailExecutor')
      end
    end

    it 'dispatches block nowhere: the fence consumes its decisions at the save point' do
      expect(described_class.executor_for('block', enforce: true)).to be_nil
    end

    it 'returns nothing for an action type it does not know' do
      expect(described_class.executor_for('set_setting', enforce: true)).to be_nil
    end

    context 'with a state-changing entry' do
      before do
        stub_const("#{described_class}::ENTRIES", {
          'write_action' => { enforce_only: true, executor: 'WriteExecutor' }
        })
      end

      it 'runs it in enforce mode only' do
        expect(described_class.executor_for('write_action', enforce: true)).to eq('WriteExecutor')
        expect(described_class.executor_for('write_action', enforce: false)).to be_nil
      end
    end
  end
end
