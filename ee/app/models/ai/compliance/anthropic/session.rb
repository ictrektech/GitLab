# frozen_string_literal: true

module Ai
  module Compliance
    module Anthropic
      class Session < ApplicationRecord
        self.table_name = 'ai_compliance_anthropic_sessions'

        belongs_to :namespace, class_name: '::Group', optional: false
        belongs_to :anthropic_integration, class_name: '::Ai::Compliance::Anthropic::Integration',
          optional: false
        belongs_to :ai_governance_session, class_name: '::Ai::Governance::Session', optional: false

        validates :ai_governance_session_id, uniqueness: true
        validates :session_xid, presence: true, length: { maximum: 255 }
        validates :message_watermark, length: { maximum: 255 }
        validate :namespace_matches_integration
        validate :namespace_matches_governance_session

        populate_sharding_key :namespace_id, source: :anthropic_integration, field: :namespace_id

        private

        # @return [void]
        def namespace_matches_integration
          return if anthropic_integration.nil? || namespace_id == anthropic_integration.namespace_id

          errors.add(:namespace, _('must match the Anthropic Compliance integration namespace'))

          nil
        end

        # @return [void]
        def namespace_matches_governance_session
          return if ai_governance_session.nil? || namespace_id == ai_governance_session.namespace_id

          errors.add(:namespace, _('must match the AI governance session namespace'))

          nil
        end
      end
    end
  end
end
