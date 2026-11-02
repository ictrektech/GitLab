# Deriving the maintained versions

The three maintained minors are the three highest released minors. Use the same source Danger uses (`tooling/danger/stable_branch.rb`). The releases API is disabled on `gitlab-org/gitlab` (403), and the endpoint returns versions unsorted, so sort before taking three:

```bash
curl -s "https://version.gitlab.com/api/v1/versions?per_page=20" | jq -r '.[].version' \
  | sort -t. -k1,1nr -k2,2nr | awk -F. '!seen[$1"."$2]++ {print $1"."$2}' | head -3
```

The output is three `MAJOR.MINOR` lines, newest first. The branches are `MAJOR-MINOR-stable-ee`. Cross-check against the [maintained versions](https://docs.gitlab.com/policy/maintenance/#maintained-versions) table.

Do not list `*-stable-ee` branches: the canonical repo keeps every historical stable branch plus internal canary refs such as `99-4-stable-ee`, so sorting them gives wrong answers. Local clones may also be stale.
