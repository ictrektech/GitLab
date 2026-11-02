# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::SchemaValidation::InconsistencyFilter, feature_category: :database do
  subject(:filter) { described_class.new }

  let(:validators) { Gitlab::Schema::Validation::Validators }

  def inconsistency(validator, object_name: 'object')
    instance_double(Gitlab::Schema::Validation::Inconsistency, type: validator.name, object_name: object_name)
  end

  describe 'ignored inconsistencies' do
    where(validator: %i[ExtraTriggers MissingTriggers])

    with_them do
      it 'drops the inconsistency' do
        ignored = inconsistency(validators.const_get(validator, false),
          object_name: 'gitlab_schema_write_trigger_for_users')

        expect(filter.to_proc.call(ignored)).to be_nil
      end
    end
  end

  it 'keeps other inconsistencies' do
    kept = [
      inconsistency(validators::ExtraTables),
      inconsistency(validators::MissingTriggers),
      inconsistency(validators::MissingIndexes, object_name: 'gitlab_schema_write_trigger_for_users')
    ]

    expect(kept.filter_map(&filter)).to eq(kept)
  end
end
