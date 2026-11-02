# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe ValidateNotNullConstraintOnPushRulesProjectIdSelfManaged, feature_category: :source_code_management do
  let(:connection) { ApplicationRecord.connection }

  before do
    connection.execute(<<~SQL)
      ALTER TABLE push_rules DROP CONSTRAINT check_1d23f0a102;
      ALTER TABLE push_rules
        ADD CONSTRAINT check_1d23f0a102 CHECK (project_id IS NOT NULL) NOT VALID;
    SQL
  end

  after do
    connection.execute('ALTER TABLE push_rules VALIDATE CONSTRAINT check_1d23f0a102')
  end

  context 'on self-managed' do
    before do
      allow(Gitlab).to receive(:com_except_jh?).and_return(false)
    end

    it 'validates the project_id constraint' do
      expect { migrate! }.to change { constraint_validated? }.from(false).to(true)
    end

    it 'succeeds when the constraint is already validated' do
      connection.execute('ALTER TABLE push_rules VALIDATE CONSTRAINT check_1d23f0a102')

      expect { migrate! }.not_to change { constraint_validated? }.from(true)
    end
  end

  context 'on GitLab.com' do
    before do
      allow(Gitlab).to receive(:com_except_jh?).and_return(true)
    end

    it 'does not validate the constraint' do
      expect { migrate! }.not_to change { constraint_validated? }.from(false)
    end
  end

  def constraint_validated?
    connection.select_value(<<~SQL)
      SELECT convalidated FROM pg_constraint
      WHERE conrelid = 'push_rules'::regclass AND conname = 'check_1d23f0a102'
    SQL
  end
end
