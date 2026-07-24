# Combined Observability Lab

The capstone exercise: every component this module builds, installed together, exercising the full incident-response workflow — metric alert → exemplar → trace → correlated logs → Kubernetes metadata → root cause — end to end, in one sitting.

This is not a new set of tools or configuration — it's the same `install-all`/`deploy-demo` path every independent lab (`../labs/lab-00`–`lab-21`) already uses, sequenced as one coherent walkthrough. If you've completed the independent labs, everything here should already be familiar; this lab's value is in the *sequencing* and the *incident-workflow narrative*, not new mechanics.

## Contents

- [`architecture/`](architecture/) — the final combined architecture diagram and its explanation.
- [`installation/`](installation/) — the exact install sequence for this capstone.
- [`dashboards/`](dashboards/) — a pointer to the 5 dashboards this lab uses (already provisioned by `make install-grafana`, not duplicated here).
- [`scenarios/`](scenarios/) — the incident-response workflow, step by step, with real commands.
- [`validation/`](validation/) — how to confirm every piece is actually working together.
- [`cleanup/`](cleanup/) — scoped teardown for this capstone specifically.

## Quick path

```bash
cd ..
make prerequisites && make verify-cluster
make install-all LAB_PROFILE=recommended
make build-demo-images
make deploy-demo
make generate-load
make validate
```
Then work through [`scenarios/incident-workflow.md`](scenarios/incident-workflow.md).
