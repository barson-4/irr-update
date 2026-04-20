# irr_update

IRR object mail automation tool for route / route6 / mntner / aut-num / as-set.

## Features
- Multi-registry support
- Supported objects: mntner / aut-num / as-set / route / route6
- Modes: check / dry-run / production
- objects/*.ini is the single source of truth
- SMTP send uses nc (netcat)
- Registry-scoped whois verification

## Registry
Registry names are dynamically resolved from:
  settings/registries/

Any registry defined under this directory can be used.
Lowercase is recommended.

## Directory Structure
/opt/irrv2/
  scripts/
  objects/
  settings/
  logs/
  docs/

## Modes

check:
  Generate mail body only

dry-run:
  Send test mail to sender
  Performs SMTP authentication

production:
  Send mail to actual registry
  Requires confirmation

## Options

--registry <registry>
--object <object>
--mode <mode>
--name <name>
--mail-sender <email>
--smtp-user <user>

--objects <list>
  (cron_runner.sh only)
  Comma-separated object list

## Objects

aut-num / as-set:
  Multi-object supported
  Use --name for single object

mntner:
  Registry dependent

route / route6:
  Batch update supported

## Logs

Logs are stored under:
  logs/scripts/
  logs/registry/<registry>/<object>/

## Notes
- Missing values are complemented from common.conf
- dry-run performs real SMTP communication
- --mail-smtp-user is removed; use --smtp-user
