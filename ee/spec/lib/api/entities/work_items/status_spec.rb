# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::WorkItems::Status, feature_category: :portfolio_management do
  describe '#as_json' do
    let(:status) do
      instance_double(
        WorkItems::Statuses::SystemDefined::Status,
        id: 1,
        name: 'To do',
        icon_name: 'status-waiting',
        color: '#737278',
        position: 0,
        description: nil,
        category: :to_do
      )
    end

    subject(:representation) { described_class.represent(status).as_json }

    it 'exposes the status fields' do
      expect(representation).to include(
        id: 1,
        name: 'To do',
        icon_name: 'status-waiting',
        color: '#737278',
        position: 0,
        description: nil,
        category: 'to_do'
      )
    end

    context 'when category is nil' do
      let(:status) do
        instance_double(
          WorkItems::Statuses::SystemDefined::Status,
          id: 1,
          name: 'To do',
          icon_name: 'status-waiting',
          color: '#737278',
          position: 0,
          description: nil,
          category: nil
        )
      end

      it 'exposes nil category' do
        expect(representation[:category]).to be_nil
      end
    end
  end
end
