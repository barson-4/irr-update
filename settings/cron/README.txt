This directory is for cron/systemd-timer related settings or wrapper configs.

Recommended:
- Put environment variables or fixed arguments here for scheduled runs.
- Keep credentials in each registry's credential.conf (not here).

Examples:
  - annual_route_update.env   : variables for annual update
  - cron.sample               : sample crontab entry

Batch cron runner:
  - scripts/cron_runner.sh    : run per-registry cron jobs (read-only ini, 1 mail per INI/object)
                               escape hatch: --chunk-size N splits INI into N-section chunks
  - logs are written under: logs/cron/YYYYMMDD-HHMMSS/
