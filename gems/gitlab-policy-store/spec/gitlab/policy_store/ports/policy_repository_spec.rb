# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gitlab::PolicyStore::Ports::PolicyRepository do
  describe "MAX_COMPILED_RULES_BYTES" do
    # The examples that stub this constant live in shared examples only ee/spec runs now,
    # so without an assertion here, changing it leaves this suite green while
    # doc/api/policy_store.md keeps promising 65536.
    it "holds the figure the API documentation promises callers" do
      expect(described_class::MAX_COMPILED_RULES_BYTES).to eq(65_536)
    end
  end

  describe "MAX_OFFSET" do
    it "holds the figure that bounds the query, independent of MAX_PAGE at the service layer" do
      expect(described_class::MAX_OFFSET).to eq(100_000)
    end
  end
end
