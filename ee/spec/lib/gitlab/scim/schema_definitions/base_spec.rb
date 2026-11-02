# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::SchemaDefinitions::Base, feature_category: :system_access do
  it 'requires subclasses to define the schema', :aggregate_failures do
    expect { described_class.schema_id }.to raise_error(NotImplementedError)
    expect { described_class.schema_name }.to raise_error(NotImplementedError)
    expect { described_class.description }.to raise_error(NotImplementedError)
    expect { described_class.attributes(context: :group) }.to raise_error(NotImplementedError)
  end
end
