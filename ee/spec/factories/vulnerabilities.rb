# frozen_string_literal: true

FactoryBot.define do
  factory :vulnerability do
    vulnerability_finding { association(:vulnerabilities_finding, project: project) }
    project
    author
    title { generate(:title) }
    title_html { "<h2>#{title}</h2>" }
    severity { :high }
    report_type { :sast }
    description { "Description of #{title}" }
    present_on_default_branch { true }
    cvss { [{ vendor: "GitLab", vector: "CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:N" }] }
    detected_at { Time.current }

    trait :detected do
      state { :detected }
    end

    trait :resolved do
      state { :resolved }
      resolved_at { Time.current }
    end

    trait :dismissed do
      state { :dismissed }
      dismissed_at { Time.current }
    end

    trait :confirmed do
      state { :confirmed }
      confirmed_at { Time.current }
    end

    trait :critical_severity do
      severity { :critical }
    end

    trait :high_severity do
      severity { :high }
    end

    trait :medium_severity do
      severity { :medium }
    end

    trait :low_severity do
      severity { :low }
    end

    ::Enums::Vulnerability.severity_levels.each_key do |severity_level|
      trait severity_level do
        severity { severity_level }
      end
    end

    ::Enums::Vulnerability.report_types.each_key do |report_type|
      trait report_type do
        report_type { report_type }
      end
    end

    trait :with_read do
      transient do
        scanner { nil }
        tracked_context { nil }
      end

      after(:create) do |vulnerability, evaluator|
        args = {
          vulnerability: vulnerability,
          vulnerability_occurrence: vulnerability.finding,
          project: vulnerability.project,
          report_type: vulnerability.report_type,
          severity: vulnerability.severity,
          state: vulnerability.state,
          traversal_ids: vulnerability.project&.namespace&.traversal_ids
        }
        args[:scanner] = evaluator.scanner if evaluator.scanner
        args[:tracked_context] = evaluator.tracked_context if evaluator.tracked_context
        create(
          :vulnerability_read,
          **args
        )
      end
    end

    trait :with_user_mention do
      transient do
        note { nil }
      end

      user_mentions do
        [association(:vulnerability_user_mention, strategy: :build, vulnerability: instance, note: note)]
      end
    end

    trait :with_state_transition do
      transient do
        from_state { ::Enums::Vulnerability.vulnerability_states[:detected] }
        to_state { ::Enums::Vulnerability.vulnerability_states[:confirmed] }
      end

      after(:create) do |vulnerability, evaluator|
        create(
          :vulnerability_state_transition,
          vulnerability: vulnerability,
          from_state: evaluator.from_state,
          to_state: evaluator.to_state,
          created_at: evaluator.created_at
        )
      end
    end

    trait :with_scanner do
      transient do
        scanner { nil }
      end

      findings do
        [
          association(
            :vulnerabilities_finding,
            :identifier,
            strategy: :build,
            description: description,
            vulnerability: instance,
            report_type: report_type,
            project: project,
            scanner: scanner
          )
        ]
      end
    end

    trait :with_notes do
      transient do
        notes_count { 3 }
      end

      after(:create) do |vulnerability, evaluator|
        create_list(
          :note_on_vulnerability,
          evaluator.notes_count,
          noteable: vulnerability,
          project: vulnerability.project)
      end
    end

    trait :with_finding do
      transient do
        tracked_context { nil }
      end

      findings do
        args = {
          description: description,
          vulnerability: instance,
          report_type: report_type,
          project: project
        }
        args[:project_tracked_context] = tracked_context if tracked_context

        [association(:vulnerabilities_finding, :identifier, strategy: :build, **args)]
      end
    end

    trait :with_finding_risk_score do
      after(:build) do |vulnerability|
        finding = create(
          :vulnerabilities_finding,
          :identifier,
          :with_finding_risk_score,
          severity: vulnerability.severity,
          description: vulnerability.description,
          vulnerability: vulnerability,
          report_type: vulnerability.report_type,
          project: vulnerability.project
        )

        vulnerability.findings = [finding]
      end
    end

    trait :with_cluster_image_scanning_finding do
      transient do
        agent_id { '46357' }
      end

      findings do
        [
          association(
            :vulnerabilities_finding,
            :identifier,
            :with_cluster_image_scanning_scanning_metadata,
            strategy: :build,
            agent_id: agent_id,
            vulnerability: instance,
            report_type: :cluster_image_scanning,
            project: project
          )
        ]
      end
    end

    trait :with_remediation do
      findings do
        [
          association(
            :vulnerabilities_finding,
            :identifier,
            :with_remediation,
            strategy: :build,
            vulnerability: instance,
            report_type: report_type,
            project: project
          )
        ]
      end
    end

    trait :with_pipeline do
      findings do
        [
          association(
            :vulnerabilities_finding,
            :identifier,
            :with_pipeline,
            strategy: :build,
            vulnerability: instance,
            report_type: report_type,
            project: project
          )
        ]
      end
    end

    trait :with_findings do
      findings do
        findings_with_solution = Array.new(2) do
          association(
            :vulnerabilities_finding, :identifier,
            strategy: :build, vulnerability: instance, report_type: report_type, project: project
          )
        end
        findings_with_remediation = Array.new(2) do
          association(
            :vulnerabilities_finding, :identifier, :with_remediation,
            strategy: :build, vulnerability: instance, report_type: report_type, project: project
          )
        end

        findings_with_solution + findings_with_remediation
      end
    end

    trait :with_issue_links do
      after(:create) do |vulnerability|
        create_list(:issue, 2, project: vulnerability.project).each do |issue|
          create(:vulnerabilities_issue_link, vulnerability: vulnerability, issue: issue)
        end
      end
    end

    trait :with_representation_information do
      representation_information do
        association(
          :vulnerability_representation_information,
          strategy: :build,
          vulnerability: instance,
          project: project,
          resolved_in_commit_sha: 'a692c30b357d792384734f44415448e0'
        )
      end
    end

    trait :with_merge_request_links do
      after(:create) do |vulnerability|
        merge_request = create(:merge_request, source_project: vulnerability.project)
        create(:vulnerabilities_merge_request_link, vulnerability: vulnerability, merge_request: merge_request)
      end
    end
  end

  trait :with_severity_override do
    severity_overrides do
      [
        association(
          :vulnerability_severity_override,
          strategy: :build,
          vulnerability: instance,
          project: project,
          original_severity: severity,
          new_severity: :medium
        )
      ]
    end
  end

  trait :skip_false_positive_detection do
    after(:build) do |_vulnerability|
      allow(::Vulnerabilities::TriggerFalsePositiveDetectionWorkflowWorker).to receive(:perform_async)
    end
  end
end
