# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::WorkItems::Features::Iteration, feature_category: :team_planning do
  it_behaves_like 'work item widget entity parity',
    described_class,
    Types::WorkItems::Widgets::IterationType

  describe '#as_json' do
    let_it_be(:reader) { create(:user) }
    let_it_be(:public_group) { create(:group, :public) }
    let_it_be(:private_group) { create(:group, :private) }
    let_it_be(:public_cadence) { create(:iterations_cadence, group: public_group) }
    let_it_be(:private_cadence) { create(:iterations_cadence, group: private_group) }
    let_it_be(:public_iteration) { create(:iteration, iterations_cadence: public_cadence) }
    let_it_be(:private_iteration) { create(:iteration, iterations_cadence: private_cadence) }

    let(:iteration) { public_iteration }
    let(:widget) { instance_double(WorkItems::Widgets::Iteration, iteration: iteration) }

    subject(:representation) { described_class.new(widget, current_user: reader).as_json }

    before do
      stub_licensed_features(iterations: true)
    end

    it 'exposes the iteration' do
      expect(representation[:iteration]).to include(id: iteration.id, title: iteration.title)
    end

    context 'when the user cannot read the iteration' do
      let(:iteration) { private_iteration }

      it 'exposes nil' do
        expect(representation[:iteration]).to be_nil
      end
    end

    context 'when the user is a member of the iteration group' do
      let(:iteration) { private_iteration }

      before_all do
        private_group.add_guest(reader)
      end

      it 'exposes the iteration' do
        expect(representation[:iteration]).to include(id: iteration.id, title: iteration.title)
      end
    end

    context 'when iteration is nil' do
      let(:iteration) { nil }

      it 'exposes nil' do
        expect(representation[:iteration]).to be_nil
      end
    end
  end
end
