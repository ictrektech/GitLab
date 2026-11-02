# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Group::NamespaceFilterPolicy, feature_category: :audit_events do
  it { expect(described_class).to delegate_to(GroupPolicy) }
end
