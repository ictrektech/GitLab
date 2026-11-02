# Before requesting a database review

To prepare a GitLab MR for database review, use the `gitlab-query-plans` skill
([`.claude/skills/gitlab-query-plans/SKILL.md`](https://gitlab.com/gitlab-org/gitlab/-/blob/master/.claude/skills/gitlab-query-plans/SKILL.md)). It covers
capturing the final Rails SQL, choosing IDs, checking plans against reviewer expectations, and
drafting the MR section.

For the requirements, see the
[database review guidelines](https://docs.gitlab.com/development/database_review/). To iterate
on slow plans, see [plan-analysis.md](plan-analysis.md). For shareable plan links,
see [Console plan links](advanced.md#console-plan-links).
