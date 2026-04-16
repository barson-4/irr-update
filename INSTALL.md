# INSTALL

## Requirements

- bash
- grep
- sed
- base64
- date
- nc (netcat)
- whois (optional)

## Directory Setup

Extract the package under:

/opt/irrv2/

## Permissions

Set executable permissions:

chmod 755 /opt/irrv2/scripts/*.sh

Secure credential files:

chmod 600 /opt/irrv2/settings/registries/*/credential.conf

## Initial Configuration

1. Edit mail settings:

vim /opt/irrv2/settings/mail.conf

2. Set credentials:

vim /opt/irrv2/settings/registries/*/credential.conf

3. Configure common parameters:

vim /opt/irrv2/settings/registries/*/common.conf

## Test Run

Run dry-run:

/opt/irrv2/scripts/irr_update.sh \
  --registries radb \
  --object route \
  --update \
  --mode dry-run \
  --mail-sender you@example.com

## Cron Setup (Recommended)

Edit cron:

crontab -e

Example:

30 2 * * * bash /opt/irrv2/scripts/cron_runner.sh --registries radb --mode production --mail-sender you@example.com --objects mntner,aut-num,as-set,route,route6 >> /opt/irrv2/logs/scripts/cron_runner.log 2>&1

## Notes

- objects/*.ini is the source of truth
- dry-run performs real SMTP send to sender
- All configuration must be completed before production use
