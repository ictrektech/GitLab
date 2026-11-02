# frozen_string_literal: true

# Drives a Limiter with a complete fact set: every fact false or absent except the
# overrides, so each example states exactly the facts its request carries.
RSpec.shared_context 'with labkit rate limit classification facts' do
  # Keys come from the classifier, so a renamed fact surfaces here too.
  def facts(**overrides)
    request = Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest.new(Rack::MockRequest.env_for('/'))
    identity = request.send(:identity_facts).keys
    # Identity facts are Strings or nil in production and must not default to
    # false: labkit's regex matcher stringifies, so /./ would match "false".
    # Everything else is a boolean predicate, so false is the right default.
    request.labkit_facts.keys.excluding(*identity).index_with { false }
      .merge(identity.index_with(nil))
      .merge(ip: '1.2.3.4', path: '/', method: 'GET', **overrides)
  end

  # The rule that terminated evaluation. An enforced throttle terminates on its
  # claim skip (the counting rule itself never terminates under labkit's
  # evaluate-all semantics), so the claim suffix is stripped: the selection under
  # test is the throttle, not the mechanism. Synthetic skips (bypass, skip_*,
  # runner_jobs) and dry-run bypasses keep their own names.
  def selected_in(limiter, **overrides)
    result = limiter.check(facts(**overrides))
    result.rule.name.delete_suffix('_claim') if result.matched?
  end
end
