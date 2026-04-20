# Registries profiles layout

Each registry has its own directory:

```
settings/registries/<rr>/
  common.conf       # registry-specific, non-secret values (WHOIS/SOURCE/MAIL_TO/default attributes)
  credential.conf   # optional secret/local values such as CRYPT_PW (gitignored recommended)
  secret.conf       # optional legacy compatibility file
```

The script loads, in this order:

1. `settings/registries/common.conf` (optional defaults; must NOT contain secrets)
2. `settings/registries/<rr>/common.conf` (required)
3. `settings/registries/<rr>/credential.conf` (optional)
4. `settings/registries/<rr>/secret.conf` (optional)
5. `general/settings/<rr>` (legacy fallback)

## common.conf continuation options

- `CONTINUATION_TARGET_DESCR_KEYS`: keys emitted after `descr:`
- `CONTINUATION_TARGET_REMARKS_KEYS`: keys emitted after `remarks:`
- Keys listed there must be defined in `Organization Parameters`
- Empty values are skipped
- Undefined keys are ignored without error
- `remarks:` continuation is emitted only when the base `REMARKS` value exists
