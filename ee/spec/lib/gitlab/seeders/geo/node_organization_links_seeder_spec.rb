# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Seeders::Geo::NodeOrganizationLinksSeeder, feature_category: :geo_replication do
  subject(:seeder) { described_class.new }

  before do
    allow(seeder).to receive(:print)
    allow(seeder).to receive(:warn)
  end

  describe '#seed!' do
    context 'when a Geo site and organizations exist' do
      let_it_be(:geo_node) { create(:geo_node) }
      let_it_be(:organizations) { create_list(:organization, 3) }

      it 'links the first Geo site to the first organizations', :aggregate_failures do
        seeder.seed!

        links = Geo::GeoNodeOrganizationLink.where(geo_node_id: geo_node.id)
        expect(links.count).to eq(3)
        expect(links.pluck(:organization_id)).to match_array(
          Organizations::Organization.order(:id).limit(3).ids
        )
      end

      it 'changes nothing when run twice' do
        seeder.seed!

        expect { seeder.seed! }.not_to change { Geo::GeoNodeOrganizationLink.count }
      end

      it 'inserts only the missing links' do
        create(:geo_node_organization_link, geo_node: geo_node,
          organization: Organizations::Organization.order(:id).first)

        expect { seeder.seed! }.to change { Geo::GeoNodeOrganizationLink.count }.by(2)
      end
    end

    context 'when no Geo site exists' do
      it 'skips with a printed message and creates no geo_nodes row', :aggregate_failures do
        expect { seeder.seed! }
          .to not_change { GeoNode.count }
          .and not_change { Geo::GeoNodeOrganizationLink.count }

        expect(seeder).to have_received(:warn).with(a_string_including('no geo_nodes records'))
      end
    end
  end
end
