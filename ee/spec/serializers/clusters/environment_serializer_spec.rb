# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Clusters::EnvironmentSerializer do
  include KubernetesHelpers

  let_it_be(:cluster) { create(:cluster) }

  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, namespace: build_stubbed(:user_namespace, owner: user)) }
  let(:resource) { build_stubbed(:environment, project: project) }

  let(:json_entity) do
    described_class.new(cluster: cluster, current_user: user)
      .represent(resource)
      .with_indifferent_access
  end

  it 'matches clusters/environment json schema' do
    expect(json_entity.to_json).to match_schema('clusters/environment', dir: 'ee')
  end
end
