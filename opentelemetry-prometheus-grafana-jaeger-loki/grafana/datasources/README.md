# Datasources

The actual, applied datasource provisioning file is [`../../install/grafana/datasources/datasources.yaml`](../../install/grafana/datasources/datasources.yaml) — it lives under `install/` (not here) because it's passed directly to `helm upgrade -f` by `scripts/install-grafana.sh`, alongside `install/grafana/values-{profile}.yaml`. Keeping the one functional copy there (rather than duplicating it here and risking drift) is deliberate — see `docs/DECISIONS.md` and the same pattern used by `../../install/`'s other per-tool values files.

This directory exists to satisfy the required top-level `grafana/` layout and as the place a learner would naturally look first — see [`../correlations/README.md`](../correlations/README.md) for what those datasources' `exemplarTraceIdDestinations`/`tracesToLogsV2`/`derivedFields` fields actually configure.
