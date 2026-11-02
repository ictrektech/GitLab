# frozen_string_literal: true

module Authn
  module IamReplication
    # Outcomes a replicator returns. The values are logged, so changing one breaks log queries.
    module Results
      DELIVERED = :delivered
      SKIPPED = :skipped
      ERROR = :error
    end
  end
end
