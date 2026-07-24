# Retention

Configured via `limits_config.retention_period` in [`../../install/loki/values-minimum.yaml`](../../install/loki/values-minimum.yaml) (`24h`) / [`values-recommended.yaml`](../../install/loki/values-recommended.yaml) (`72h`) — matching [`../../config/retention.env`](../../config/retention.env)'s `LOKI_RETENTION_MINIMUM`/`LOKI_RETENTION_RECOMMENDED`.

## How retention actually happens

Loki's `compactor` component (running as part of the single `Monolithic`-mode binary in this lab, not a separately-scaled component) periodically removes chunks and index entries older than `retention_period`. This is a background, eventually-applied process — deleting a retention setting's worth of data is not instantaneous the moment the TTL is crossed; see `docs/14-loki-architecture.md` "Compactor" for the mechanics.

## What this lab does NOT implement

- **Per-tenant retention overrides** — this is a single-tenant lab (`auth_enabled: false`); multi-tenant retention policies are a real production Loki feature, documented but not exercised here (`docs/17-security-and-governance.md` "Multi-tenancy limitations").
- **Object storage lifecycle policies** (S3/GCS bucket-level expiration as a second, independent retention mechanism) — this lab uses `filesystem` storage (a PVC), so there is no object-store lifecycle layer to configure; `docs/16-production-design.md` "Loki" covers what changes at real production scale (object storage, and likely `SimpleScalable`/`Distributed` deployment mode instead of `Monolithic`).
