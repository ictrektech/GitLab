# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      module RecommendReviewers
        class Context
          include Gitlab::Utils::StrongMemoize

          # The rules share one approver budget so the reviewer data stays under the
          # 128 KiB limit of the CI variable. The per-rule floor means that more than
          # 40 rules can still go over MAX_TOTAL_APPROVERS.
          MAX_APPROVERS_PER_RULE = 50
          MIN_APPROVERS_PER_RULE = 10
          MAX_TOTAL_APPROVERS = 400
          # Reviews the user has already responded to still need follow-up, so they count for half.
          RESPONDED_REVIEW_STATES = %w[reviewed approved requested_changes].freeze
          RESPONDED_REVIEW_WEIGHT = 0.5
          # The count is slow for reviewers with a long history. Generate and Refresh build this
          # context inside the API request, so only Sidekiq runs it, and a bounded number of times.
          MAX_UNCACHED_RESPONDED_COUNTS = 10
          RESPONDED_COUNT_CACHE_TTL = 1.hour
          RESPONDED_COUNT_RACE_CONDITION_TTL = 30.seconds

          def self.call(resource:)
            new(resource).build
          end

          def initialize(merge_request)
            @merge_request = merge_request
            @responded_counts = {}
            @uncached_responded_counts = 0
          end

          def build
            {
              "current_reviewers" => current_reviewers_data,
              "approval_rules" => approval_rules_data
            }
          end

          private

          attr_reader :merge_request

          def current_reviewers_data
            merge_request.reviewers.map { |r| { "id" => r.id } }
          end

          def approval_rules_data
            grouped_approval_rules.map do |rule|
              {
                "id" => rule.id,
                "type" => rule.approval_rule.is_a?(ApprovalProjectRule) ? "project_rule" : "merge_request_rule",
                "name" => rule.name,
                "section" => rule.section,
                "approvals_required" => rule.approvals_required,
                "eligible_approvers" => eligible_approvers_for(rule)
              }
            end
          end

          def eligible_approvers_for(rule)
            approvers = approvers_for(rule).filter_map { |u| preloaded_user_data[u.id] }

            by_load = approvers.sort_by { |u| [u['busy'] ? 1 : 0, u['pending_reviews']] }
            kept = by_load.first(approvers_limit)
            approvers = kept if approvers.size > approvers_limit

            # Counted after truncation so only the approvers that are sent pay for the second query,
            # least loaded first so they get the uncached budget.
            weights = responded_reviews_weights(kept.map { |u| u['id'] }) # rubocop:disable Rails/Pluck -- kept is an Array of Hashes
            approvers.map { |u| u.merge('pending_reviews' => u['pending_reviews'] + weights[u['id']]) }
          end

          def approvers_limit
            (MAX_TOTAL_APPROVERS / [grouped_approval_rules.size, 1].max)
              .clamp(MIN_APPROVERS_PER_RULE, MAX_APPROVERS_PER_RULE)
          end
          strong_memoize_attr :approvers_limit

          # `any_approver` rules ("All Members") store no approvers, so left
          # unexpanded the flow gets zero candidates and assigns nobody.
          # https://gitlab.com/gitlab-org/gitlab/-/issues/604144
          def approvers_for(rule)
            return any_approver_candidates if rule.any_approver?

            rule.approvers
          end

          def any_approver_candidates
            merge_request.approval_state.any_approver_candidates(limit: approvers_limit).to_a
          end
          strong_memoize_attr :any_approver_candidates

          def unique_approvers
            grouped_approval_rules.flat_map { |rule| approvers_for(rule) }.uniq(&:id)
          end
          strong_memoize_attr :unique_approvers

          def preloaded_user_data
            ActiveRecord::Associations::Preloader.new(
              records: unique_approvers,
              associations: [:status, :user_preference]
            ).call

            unique_approvers.to_h { |user| [user.id, serialize_user(user)] }
          end
          strong_memoize_attr :preloaded_user_data

          def serialize_user(user)
            {
              "id" => user.id,
              "busy" => user.status&.busy? == true,
              "status_emoji" => user.status&.emoji,
              "status_message" => user.status&.message,
              "pending_reviews" => user.review_requested_open_merge_requests_count,
              "local_time" => user_local_time(user),
              "last_activity_on" => user.last_activity_on&.iso8601
            }.compact
          end

          def responded_reviews_weights(user_ids)
            cache_keys = (user_ids - @responded_counts.keys)
              .index_with { |id| ['recommend_reviewers', id, 'responded_reviews_count'] }

            if cache_keys.any?
              cached = Rails.cache.read_multi(*cache_keys.values)
              cache_keys.each do |id, key|
                @responded_counts[id] = cached.fetch(key) { uncached_responded_reviews_count(id, key) }
              end
            end

            user_ids.index_with { |id| (@responded_counts[id].to_i * RESPONDED_REVIEW_WEIGHT).round }
          end

          def uncached_responded_reviews_count(user_id, cache_key)
            return unless Gitlab::Runtime.sidekiq?

            @uncached_responded_counts += 1
            return if @uncached_responded_counts > MAX_UNCACHED_RESPONDED_COUNTS

            # fetch, not write: concurrent jobs get an entry that just expired while this one recounts.
            Rails.cache.fetch(cache_key, expires_in: RESPONDED_COUNT_CACHE_TTL,
              race_condition_ttl: RESPONDED_COUNT_RACE_CONDITION_TTL) do
              MergeRequestsFinder.new(
                unique_approvers_by_id[user_id],
                reviewer_id: user_id, state: 'opened', non_archived: true, review_states: RESPONDED_REVIEW_STATES
              ).execute.count
            end
          end

          def unique_approvers_by_id
            unique_approvers.index_by(&:id)
          end
          strong_memoize_attr :unique_approvers_by_id

          def user_local_time(user)
            tz_name = user.user_preference.timezone
            return unless tz_name.present?

            zone = ActiveSupport::TimeZone[tz_name]
            return unless zone

            Time.current.in_time_zone(zone).strftime('%H:%M')
          end

          # Grouped so that code owner rules sharing a section and an approver set
          # collapse into one. Ungrouped, a merge request that matches many
          # CODEOWNERS patterns repeats the same approvers once per pattern.
          def grouped_approval_rules
            merge_request.approval_state.grouped_approval_rules.select do |rule|
              rule.approvals_required > 0 || rule.regular? || rule.code_owner?
            end
          end
          strong_memoize_attr :grouped_approval_rules
        end
      end
    end
  end
end
