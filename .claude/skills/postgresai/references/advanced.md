# JSON output, explicit clones, and plan links

## JSON

`scripts/joe.sh` is text-only and exits 2 on `--json`. For JSON, run the raw CLI with `--json`
and poll `postgresai joe result <id> --json` (exit 1 and `"status":"pending"` while running).

## Explicit clones

`postgresai dblab clone create|list|status|reset|destroy` is rarely needed; `joe` manages its
own session clone. Never pass `--protected`. Destroy clones you created if your role allows
it (it needs Admin or AllFeaturesUser); otherwise let auto-deletion handle it.

## Console plan links

The CLI can't build console links: `command <id>` is an API handle, not the console's command
ID, and the API key can't read command history
([postgresai#266](https://gitlab.com/postgres-ai/postgresai/-/work_items/266)). To share a plan,
open `https://console.postgres.ai/gitlab/sessions/?author=<your name>`, open the matching
command (same query and time, `created_at` in `result --json`), and copy its URL
(`…/projects/<project>/sessions/<session>/commands/<commandId>`). HTTP status can't verify a link.
