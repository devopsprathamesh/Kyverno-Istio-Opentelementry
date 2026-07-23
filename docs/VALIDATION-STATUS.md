# Validation Status

This document is the source of truth for what has actually been built and validated in this repository, as opposed to what is merely planned or documented. Update it at the end of every phase.

| Phase | Status | Validation performed | Result | Known limitations |
| --- | --- | --- | --- | --- |
| Phase 1 — Repository architecture and governance | Complete | Documentation existence check, placeholder-token scan, secret-file scan, nested-`.git` scan, `git diff --check`, relative markdown-link resolution check, manual Mermaid syntax review | Pass (see below) | Mermaid diagrams were not tool-validated — no `node`/`npx`/Mermaid CLI was available in this environment; only manual syntax review was performed |
| Phase 2 — Base VirtualBox and Vagrant Kubernetes environment | **Partial** — automation built and statically validated; live-cluster runtime validation not performed | File existence, `bash -n` + ShellCheck (if available), `ruby -c`/`vagrant validate`, YAML template structural checks, `make help` review, markdown-link check, git-safety checks; host tool presence (`VBoxManage`/`vagrant --version`) confirmed directly | Static suite: pass (see below). Runtime (VM boot, kubeadm, Cilium, storage, network tests): **not run**, by explicit user choice this session | No live cluster exists yet. See Phase 2 detail below for the exact commands to complete runtime validation, and known/deferred risks. |
| Phase 3 — Independent Kyverno lab | **Partial** — automation and documentation built and statically validated; live-cluster runtime validation not performed | File existence, `bash -n` + ShellCheck, YAML structural validation, `helm lint` (best-effort, network-dependent), Kyverno CLI `kyverno test` offline policy tests, policy-quality checks (API versions, duplicate names, descriptions, wildcards, image-tag hygiene), markdown-link check, `make help`, git-safety checks | Static suite: see Phase 3 detail below for exact pass/fail counts. Runtime (install, functional probes, all `tests/*-policy-tests.sh`): **not run** — no live cluster existed during this phase | No live cluster exists yet. See Phase 3 detail below for exact commands to complete runtime validation. |
| Phase 4 — Independent Istio lab | **Partial** — automation and documentation built and statically validated; live-cluster runtime validation not performed | File existence, `bash -n` + ShellCheck, YAML structural validation, `istioctl analyze --use-kube=false` (real tool execution, checksum-verified `istioctl` 1.30.3 installed this phase), manifest-quality checks (API versions, duplicate names, image-tag hygiene), markdown-link check, `make help`, git-safety checks | Static suite: **pass** (8/8 mandatory checks, 1 non-fatal WARN — see Phase 4 detail below). Runtime (`make verify-cluster`, `make install`, `make validate-installation`, `make deploy-demo`, `make test-runtime`, all 10 `tests/*-test.sh` runtime scripts): **not run** — no live cluster existed during this phase | No live cluster exists yet. See Phase 4 detail below for exact commands to complete runtime validation. |
| Phase 5 — Independent observability lab | Not started | — | — | — |
| Phase 6 — All-tools integrated lab | Not started | — | — | — |
| Phase 7 — Repository-wide validation and documentation review | Not started | — | — | — |

## Phase 1 detail

### Files created

- `.gitignore` (root)
- `PROJECT-IMPLEMENTATION-PLAN.md` (root)
- `docs/ARCHITECTURE.md`
- `docs/REPOSITORY-GOVERNANCE.md`
- `docs/VERSIONS.md`
- `docs/DEPENDENCIES.md`
- `docs/DECISIONS.md`
- `docs/LAB-WORKFLOW.md`
- `docs/VALIDATION-STATUS.md` (this file)

### Files modified

- `README.md` (root) — replaced the placeholder one-line title with a full repository landing page: purpose, architecture summary, module table with links, recommended learning order, base environment overview, independent-lab model, integrated lab overview, prerequisite summary, and an explicit phase-by-phase status statement.

### Files intentionally left unchanged

- `istio/README.md`, `kyverno/README.md`, `opentelemetry-prometheus-grafana-jaeger-loki/README.md` — remain empty; populating them is in scope for Phases 3, 4, and 5 respectively, not Phase 1.
- `auto-setup-default-kube-env/`, `all-tools-integrated-lab/` — remain empty directories; populating them is in scope for Phases 2 and 6 respectively.

### Pre-existing repository state noted, not modified

At the start of this phase, `git status --short` showed `opentelemetry-prometheus-grafana-jaeger/README.md` as deleted (unstaged) and `opentelemetry-prometheus-grafana-jaeger-loki/` as untracked — the result of a rename the user performed before this session, aligning the directory with this repository's target architecture name. This phase did not stage, commit, or otherwise touch that rename; it is left exactly as found for the user to commit at their discretion.

### Commands executed

```bash
pwd
git rev-parse --show-toplevel
git branch --show-current
git status --short
find . -maxdepth 4 -type f | sort
find . -maxdepth 3 -type d | sort
git log --oneline --all -- opentelemetry-prometheus-grafana-jaeger/ opentelemetry-prometheus-grafana-jaeger-loki/
git status
find <module dirs> -type f            # inventory of each module directory
# Read: README.md, istio/README.md, kyverno/README.md,
#       opentelemetry-prometheus-grafana-jaeger-loki/README.md

# --- after authoring all Phase 1 documents ---
for f in <9 required files>; do test -f "$f"; done
which npx node; npx --version
grep -rnE "TODO|TBD|FIXME|CHANGEME|<repository-url>" README.md PROJECT-IMPLEMENTATION-PLAN.md docs/ .gitignore
find . -path ./.git -prune -o -type f \( -iname "*kubeconfig*" -o -iname "*.key" -o -iname "*.pem" -o -iname "*.p12" -o -iname "*.token" -o -iname ".env" \) -print
find . -mindepth 2 -name ".git" -print
git diff --check
git status --short
git diff --stat
python3 <script checking every relative .md link in the 8 new/modified docs resolves to a real file>
```

### Tests run / passed / failed

| Check | Result |
| --- | --- |
| All 9 required Phase 1 files exist | Pass |
| Placeholder token scan (`TODO`/`TBD`/`FIXME`/`CHANGEME`/`<repository-url>`) | Pass — only match was the validation-requirements sentence in `PROJECT-IMPLEMENTATION-PLAN.md` that names the tokens as part of describing this very check; not an actual leftover placeholder |
| Secret-like file scan (`*kubeconfig*`, `*.key`, `*.pem`, `*.p12`, `*.token`, `.env`) | Pass — none found |
| Nested `.git` directory scan | Pass — none found |
| `git diff --check` (whitespace errors) | Pass — clean, exit code 0 |
| Relative markdown-link resolution (65 links across 8 files) | Pass — all 65 resolve to real files once `docs/VALIDATION-STATUS.md` (this file) was created; 10 of the 65 pointed here and were reported broken until this file existed |
| Mermaid diagram syntax | Not tool-validated — manually reviewed only (see limitations) |
| Files outside `docs/` + root planning files unintentionally changed | Pass — `git status --short` shows only `README.md` modified and the pre-existing, user-made rename noted above; no module directory content was touched |

### Items not testable in this phase

- **Mermaid rendering** — no `node`/`npx`/`@mermaid-js/mermaid-cli` was available in this environment (`which npx node` returned not-found for both). The 7 diagrams in `docs/ARCHITECTURE.md` were manually checked for valid `flowchart` syntax, balanced brackets, and valid node/edge declarations, but were not run through a rendering validator.
- **Everything implementation-related** — no cluster, tool, or manifest exists yet by design; there is nothing to functionally test until Phase 2 begins.

### Next phase (as of Phase 1)

```text
Phase 2: VirtualBox, Vagrant, Kubernetes, containerd, Cilium, Hubble, storage, kubeconfig export, and cluster validation
```

## Phase 2 detail

**Scope decision:** the user explicitly chose "build and statically validate only" for this pass, rather than "run the full provisioning end-to-end now" — see `PROJECT-IMPLEMENTATION-PLAN.md` Phase 2. Everything below reflects that scope honestly: full automation was built, everything checkable without a live cluster was checked and passed, and a live cluster was deliberately not provisioned in this session.

### Files created

39 files under `auto-setup-default-kube-env/`:
- `README.md`, `Makefile`, `Vagrantfile`, `.env.example`
- `config/`: `versions.env`, `cluster.env`, `profiles.env`, `kubeadm-config.yaml.tpl`, `kubeadm-join-config.yaml.tpl` (addition beyond the originally-listed file set — a standard, documented kubeadm `JoinConfiguration` mechanism needed for a correct worker `--node-ip` pin), `cilium-values.yaml.tpl` (addition — governance prefers a reviewable values file over a long inline `--set` chain), `crictl.yaml`, `containerd-config.toml.tpl`
- `scripts/lib/`: `common.sh`, `logging.sh`, `validation.sh`
- `scripts/host/`: `check-prerequisites.sh`, `setup-cluster.sh`, `export-kubeconfig.sh`, `validate-cluster.sh`, `status.sh`, `cleanup-generated-files.sh`
- `scripts/guest/`: `00-common.sh` through `10-node-validation.sh` (11 scripts, exact list as specified)
- `tests/`: `shellcheck.sh`, `vagrant-validation.sh`, `cluster-smoke-test.sh`, `network-test.sh`, `storage-test.sh`, `expected-results.md`
- `docs/`: `ARCHITECTURE.md`, `INSTALLATION.md`, `NETWORKING.md`, `CILIUM-HUBBLE.md`, `STORAGE.md`, `TROUBLESHOOTING.md`, `REBUILD-AND-RECOVERY.md`
- `examples/`: `profile-overrides.env.example`, `proxy.env.example`

### Files modified

- `README.md` (root) — status line updated from "Phase 1 only" to "Phase 2 in progress (partial)"; `auto-setup-default-kube-env` row in the module table updated from "Planned" to "Built, statically validated — live-cluster run pending".
- `PROJECT-IMPLEMENTATION-PLAN.md` — Phase 2 definition-of-done checkboxes updated to reflect exactly what's true (automation built vs. live-validated); known risks expanded with the host-only IP conflict encountered and the dynamically-resolved version items.
- `docs/VERSIONS.md` — added a "Phase 2 addendum" section: Ubuntu Vagrant box, Cilium CLI, Hubble CLI (intentionally unpinned — see below), `pkgs.k8s.io` repo detail, containerd's Docker-apt-repo source, local-path-provisioner, and reconciled VirtualBox/Vagrant rows against what was actually confirmed installed on this host.
- `docs/DEPENDENCIES.md` — added §15a documenting the host-only network IP conflict encountered during this phase as a real (not hypothetical) risk, and item 8 in the conflicts summary.
- `docs/DECISIONS.md` — appended ADR-011 (Cilium cluster-pool IPAM without a kubeadm `podSubnet`) and ADR-012 (Rancher local-path-provisioner as the lab StorageClass).

### Commands executed

```bash
# Inspection (before any changes)
pwd; git rev-parse --show-toplevel; git branch --show-current; git status --short
find auto-setup-default-kube-env -maxdepth 5 -print
git log --oneline -5; git show --stat HEAD

# Host capability inspection (read-only)
VBoxManage --version; vagrant --version; VBoxManage list vms; vagrant global-status
VBoxManage list hostonlyifs; lsmod | grep -i kvm; free -h; df -h; uname -a

# Conflict discovery and resolution (read-only investigation; the actual
# `vagrant destroy` of the unrelated environment was run by the user, not
# by this session)
grep -n "192.168\|private_network\|hostname" ~/lab-setup-code/homelabsetup/1.vagrant/Vagrantfile

# Version research (WebSearch/WebFetch against official docs)
# — Ubuntu Vagrant box, local-path-provisioner, Cilium CLI, pkgs.k8s.io

# Implementation: 39 files created under auto-setup-default-kube-env/ (Write)

# Static validation (this phase's actual test pass)
find scripts tests -name '*.sh' -exec chmod +x {} \;
bash tests/shellcheck.sh              # bash -n + shellcheck, all 25 scripts
bash tests/vagrant-validation.sh      # vagrant validate + YAML structural checks
make help                             # target listing, no side effects
make prerequisites                    # real, read-only host check — see results below

# Bug found and fixed during validation (see "Tests failed" below):
# a SIGPIPE-under-`pipefail` false-negative in `producer | grep -q` patterns,
# discovered because `make prerequisites`'s KVM check reported [PASS] "no
# KVM modules loaded" while `lsmod | grep -i kvm` directly showed kvm_intel/
# kvm/irqbypass loaded. Root-caused via bisection (bash -c isolation tests),
# fixed in 8 files, re-validated.

find . -mindepth 2 -name ".git" -print
find . -path ./.git -prune -o -type f \( -iname "*kubeconfig*" -o -iname "*.key" -o -iname "*.pem" -o -iname "*.p12" -o -iname "*.token" -o -iname ".env" \) -print
grep -rnE "TODO|TBD|FIXME|CHANGEME|<repository-url>" auto-setup-default-kube-env README.md PROJECT-IMPLEMENTATION-PLAN.md docs/
python3 <script checking all 116 relative .md links in the repo resolve>
git diff --check; git diff --stat; git status --short
git status --short istio/ kyverno/ opentelemetry-prometheus-grafana-jaeger-loki/ all-tools-integrated-lab/
git check-ignore -v auto-setup-default-kube-env/.env auto-setup-default-kube-env/.env.example
```

### Tests run / passed / failed

| Check | Result |
| --- | --- |
| All 39 required/justified files exist | Pass |
| `bash -n` syntax check, 25 scripts | Pass — all 25 |
| ShellCheck (severity: warning+, SC1091 excluded — see `tests/shellcheck.sh` header comment), 25 scripts | Pass — all 25, after fixing one real deprecated-`egrep` finding (SC2196, `scripts/host/check-prerequisites.sh`) and one real `local`-masking finding (SC2155, `scripts/lib/validation.sh`) |
| `vagrant validate` | Pass — "Vagrantfile validated successfully." (also implicitly validates Ruby syntax; `ruby -c` itself was skipped — no standalone `ruby` binary on this host, only Vagrant's bundled one) |
| YAML template structural check (3 `.yaml.tpl` files, placeholder-substituted) | Pass — all 3 |
| `make help` | Pass — lists all 20 targets with descriptions, confirmed no side effects |
| `make prerequisites` (real, read-only host check) | Pass — 17 checks passed, 1 expected `[WARN]` (KVM modules loaded — informational per this script's own design, not a blocker) |
| Markdown link check, whole repository | Pass — all 116 relative `.md` links across 21 files resolve |
| `git diff --check` | Pass — clean, exit 0 |
| Secret-like file scan | Pass — one filename match (`scripts/host/export-kubeconfig.sh`) confirmed to be a script, not a credential; no `.generated/` directory exists (no runtime occurred) |
| Nested `.git` scan | Pass — none found |
| Placeholder token scan | Pass — only self-referential matches inside this document's own description of the check |
| `istio/`, `kyverno/`, `opentelemetry-prometheus-grafana-jaeger-loki/`, `all-tools-integrated-lab/` unmodified | Pass — `git status --short` scoped to each returns empty |
| **Bug found during validation:** `producer \| grep -q pattern` under `set -o pipefail` can spuriously report failure (SIGPIPE on the producer when grep exits early after its first match) | **Failed, then fixed** — found via `make prerequisites`'s KVM check reporting a false `[PASS]`; root-caused and fixed in `scripts/lib/validation.sh`, `scripts/host/check-prerequisites.sh` (3 instances), `scripts/guest/01-configure-network.sh`, `03-install-containerd.sh`, `04-install-kubernetes.sh`, `06-install-cilium.sh`, `08-install-storage.sh`, `09-install-helm.sh` — by capturing producer output into a variable first, then matching against it, rather than piping live. Re-ran the full static suite afterward; all pass. Also found and fixed one independent **logic** bug in `scripts/host/validate-cluster.sh`'s certificate-expiry check (`grep -qv` tested "at least one row is fine" instead of "no row is invalid/expired"). |

### Runtime validation

**Not performed in this session, by explicit user choice** (see scope decision above), even though this host is actually capable of it (VirtualBox 7.2.12r174389 and Vagrant 2.4.9 confirmed installed and functional; 23.7GB RAM free against an 18GB `recommended`-profile requirement; 396GB disk free; hardware virtualization present; no host-only IP conflict after the user cleared the unrelated environment that previously occupied `192.168.56.10-.12`).

Not run: `make setup`, VM boot, `kubeadm init`/`kubeadm join`, Cilium/Hubble install and health checks, `make validate`, `tests/network-test.sh`, `tests/storage-test.sh`, `tests/cluster-smoke-test.sh`, host `kubectl`/`helm` against a real cluster.

**To complete runtime validation:**

```bash
cd auto-setup-default-kube-env
make prerequisites
make setup LAB_PROFILE=recommended
make validate
export KUBECONFIG="$(pwd)/.generated/kubeconfig"
kubectl get nodes -o wide
```

### Items not testable in this phase

- Everything under "Runtime validation" above — requires the live-cluster run the user deferred.
- A few version/config details are intentionally resolved dynamically at install time rather than pinned statically (documented, not hidden): the exact `containerd.io` Docker-apt-repo package revision suffix, and the Hubble CLI version (no stable, independently pinnable release cadence relative to the Cilium chart — see `docs/VERSIONS.md` Phase 2 addendum).

### Next phase (as of Phase 2)

```text
Phase 3: Independent Kyverno hands-on lab
```

## Phase 3 detail

**Scope note:** no live Kubernetes cluster existed at any point during this phase (`VBoxManage list vms` and `vagrant global-status` both empty, no `.generated/kubeconfig`, `kubectl` not installed on the host) — this matches the phase's own "no live cluster available" execution policy exactly: build the complete implementation, perform all possible static validation, do not auto-run `vagrant up`, do not claim runtime success, mark runtime validation as pending with exact follow-up commands.

### Files created

110 files under `kyverno/` (22 shell scripts, 48 YAML files, 35 markdown files, plus `Makefile`/`.env.example`): `README.md`, `Makefile`, `.env.example`, `config/{versions.env, namespaces.env, lab-settings.env}`, 15 `docs/*.md` concept documents (12 Mermaid diagrams total), `install/{namespace.yaml, values-minimum.yaml, values-recommended.yaml, optional/policy-reporter-values.yaml}`, `demo/` (namespace + applications + 9 insecure-workload fixtures + 3 compliant-workload fixtures + 7 test-resource fixtures), `policies/` (17 policies across all 9 required subdirectories), 18 `labs/lab-*.md` walkthroughs, `scripts/lib/{common.sh, logging.sh, kubernetes.sh}` + 11 orchestration scripts, `tests/` (`static-validation.sh`, `installation-test.sh`, 6 runtime policy-type test scripts, `expected-results.md`, and `cli-test-cases/` — 4 offline Kyverno CLI test suites, one per subdirectory as `kyverno test` requires).

### Files modified

`README.md` (root, status line + module table row), `PROJECT-IMPLEMENTATION-PLAN.md` (Phase 3 checkboxes), `docs/VERSIONS.md` (Kyverno "Phase 3 addendum" + a new uncertain-compatibility item on the Helm chart's exact values schema), `docs/DEPENDENCIES.md` (§2 Kyverno reconciliation note), `docs/DECISIONS.md` (+ADR-013 through ADR-018).

### Lab implementation summary

Installation via pinned Helm chart (3.8.2 / app v1.18.2) with minimum/recommended profiles (replica counts, PDB, anti-affinity on the admission controller only — the one component in the synchronous request path). 17 policies covering every required type (audit, validate, mutate, generate, cleanup, verify-images, exceptions, advanced/context/foreach/precondition, production-examples), each cross-referenced to a lab and, where offline-testable, a `kyverno test` fixture. Demo workloads: one intentionally-incomplete "real" application plus 9 individually-labeled insecure fixtures and 3 compliant references. 18 sequential labs from prerequisites through production readiness. Runtime test scripts for every policy type, each namespace-isolated, labeled, and self-cleaning via `trap`. Report tooling via `kubectl`/`jq`, no Grafana/Prometheus dependency. Troubleshooting: a 27-row symptom table plus a hands-on lab (lab-16) that deliberately triggers several of the failure modes.

### Policy inventory

See `kyverno/README.md`'s own "Policy inventory" table (17 rows) for the authoritative, current list — not duplicated here to avoid drift between two copies.

### Static validation

Commands executed:

```bash
# Kyverno CLI install (disclosed in the approved plan before execution)
curl -fsSL -o checksums.txt https://github.com/kyverno/kyverno/releases/download/v1.18.2/checksums.txt
curl -fsSL -o kyverno-cli_v1.18.2_linux_x86_64.tar.gz https://github.com/kyverno/kyverno/releases/download/v1.18.2/kyverno-cli_v1.18.2_linux_x86_64.tar.gz
sha256sum -c <(grep kyverno-cli_v1.18.2_linux_x86_64.tar.gz checksums.txt)   # OK
install -m 0755 kyverno ~/.local/bin/kyverno   # user-local, no sudo

find scripts tests -name '*.sh' -exec chmod +x {} \;
bash tests/static-validation.sh
kyverno test tests/cli-test-cases/
make help
git diff --check; git status --short istio/ opentelemetry-prometheus-grafana-jaeger-loki/ all-tools-integrated-lab/ auto-setup-default-kube-env/
python3 <repo-wide relative-markdown-link checker — 141 links across 55 files>
find . -mindepth 2 -name ".git"; find . -type f \( -iname "*kubeconfig*" -o -iname "*.key" -o ... \)
```

Results:

| Check | Result |
| --- | --- |
| `bash -n`, 22 scripts | Pass — 22/22 |
| ShellCheck (severity: warning+, SC1091 excluded — same documented rationale as Phase 2), 22 scripts | Pass — 22/22 |
| YAML structural validation, 48 files | Pass — 48/48 |
| `helm lint` | **Skipped, documented** — `helm` is not installed on this host and was not installed in this session (only the Kyverno CLI download was disclosed/approved in the plan; installing a second binary would have needed a fresh disclosure, so this was deliberately left as a documented skip rather than done without asking) |
| Kyverno CLI offline policy tests (`kyverno test tests/cli-test-cases/`) | **Pass — 10/10 test assertions**, across 4 suites (require-labels, resource-limits, privileged-containers, mutate-labels) |
| Policy quality checks (API versions, duplicate names, descriptions, messages) | Pass, after fixing one real gap found: `policies/exceptions/allow-demo-hostpath-exception.yaml` was missing a `policies.kyverno.io/description` annotation — added |
| Unsafe wildcard match check | Pass — no policy matches `kinds: ["*"]` |
| Image-tag hygiene check | Pass, after fixing one real inconsistency found: `demo/test-resources/noncompliant-pod.yaml` and `noncompliant-deployment.yaml` used a different marker label (`lab-marker: intentionally-noncompliant`) than every other intentionally-bad fixture (`intentionally-insecure`), so the hygiene check's exemption logic didn't recognize them — unified the label rather than special-casing the check |
| Markdown link check (kyverno/ only, then repo-wide) | Pass — 25/25 within `kyverno/`, 141/141 repository-wide |
| `make help` | Pass — lists 23 targets |
| Secret-like file scan | Pass — the one filename match (`export-kubeconfig.sh`, a script, not a credential) is the same pre-existing, confirmed-benign match from Phase 2 |
| Nested `.git` scan | Pass — none found |
| Placeholder token scan | Pass — only self-referential matches inside this document's own description of the check |
| `git diff --check` | Pass — clean, exit 0 |
| `istio/`, `opentelemetry-prometheus-grafana-jaeger-loki/`, `all-tools-integrated-lab/`, `auto-setup-default-kube-env/` unmodified | Pass — `git status --short` scoped to each returns empty |

**A genuine bug class found and fixed via real execution, not just review:** two `kyverno-test.yaml` schema mistakes (using `resource:`/`patchedResource:` instead of the actual current schema's `resources:` (list) / `patchedResources:`, and Kyverno's requirement that `kyverno test` scan for folders each containing a file literally named `kyverno-test.yaml`, not arbitrarily-named files in one flat directory) — found only because the CLI was actually run, not assumed correct from documentation memory. Fixed by restructuring `tests/cli-test-cases/` into one subdirectory per test case and correcting the field names against a real, current example fetched directly from Kyverno's own `kyverno/policies` repository. This is the same category of lesson as Phase 2's SIGPIPE-under-pipefail discovery: static/textual correctness and actually-running-it correctness are not the same thing, and this phase's real CLI execution caught what a syntax-only review would have missed.

**Real, positive semantic confirmation, not just syntax validation:** all 10 `kyverno test` assertions passed on the first fully-correct run, confirming the actual JMESPath `pattern`/`deny.conditions`/mutation logic in `require-labels-enforce`, `require-resource-limits`, `restrict-privileged-containers` (all 4 of its rules), and `add-default-labels` produces exactly the pass/fail/mutation outcomes documented in the corresponding labs and docs — not merely that the YAML parses. This run also surfaced Kyverno's "autogen" behavior in practice (a `kinds: ["Pod"]`-only policy correctly governing a Deployment fixture via an auto-generated `autogen-validate-resources` rule), which has been documented in `kyverno/docs/04-policy-anatomy.md` as a result.

### Runtime validation

**Not performed — no live cluster existed at any point during this phase**, not a scope choice made mid-session (contrast with Phase 2, where the user actively chose static-only despite a capable host). Not run: `make verify-cluster`, `make install`, `make validate-installation`, `make deploy-demo`, `make test-runtime`, and every `tests/*-policy-tests.sh` runtime script.

**To complete runtime validation:**

```bash
cd auto-setup-default-kube-env
make prerequisites && make setup LAB_PROFILE=recommended && make validate
export KUBECONFIG="$(pwd)/.generated/kubeconfig"

cd ../kyverno
make prerequisites
make verify-cluster
make install LAB_PROFILE=recommended
make validate-installation
make deploy-demo
make test-runtime
```

### Items not testable in this phase

- Everything under "Runtime validation" above.
- `helm lint` against the actual pinned chart (documented skip, not a silent omission — see the static-validation table above).
- Real Sigstore/Rekor keyless signature verification for `policies/verify-images/verify-image-signature.yaml` (requires both a live cluster and outbound network access to `rekor.sigstore.dev`) — `kyverno/docs/08-image-verification.md` and `kyverno/tests/image-verification-tests.sh` both document this limitation explicitly rather than assuming it works.
- A real 1-hour-aged `CleanupPolicy` deletion cycle (`kyverno/tests/cleanup-policy-tests.sh` validates readiness and selector scoping only, by design — see that script's own note).

### Next phase

```text
Phase 4: Independent Istio hands-on lab
```

## Phase 4 detail

**Repository state at start:** working tree clean; `istio/` contained only an empty placeholder `README.md`. No live cluster existed (`VBoxManage list vms`/`vagrant global-status` empty, no `.generated/kubeconfig`) — matching this phase's own "no live cluster available" execution branch, the same situation as Phase 3.

**Files created:** `istio/config/{versions,namespaces,lab-settings,endpoints}.env`; `istio/scripts/lib/{common,logging,kubernetes,istio}.sh` + 11 orchestration scripts; `istio/install/` (namespace, base/istiod/cni/gateway Helm values × minimum/recommended profiles, Gateway API reference); `istio/demo/` (4-service demo app, gateway, traffic/resilience/egress/security manifests); `istio/policies/` (peerauthentication, authorization, requestauthentication, sidecar); `istio/Makefile`; `istio/tests/` (`static-validation.sh`, `installation-test.sh`, 9 runtime test scripts, `expected-results.md`); `istio/docs/` (16 concept documents, 16 Mermaid diagrams); `istio/labs/` (21 lab documents, `lab-00`–`lab-20`); `istio/README.md`, `istio/.env.example`, `istio/examples/` (3 files).

**Files modified:** `PROJECT-IMPLEMENTATION-PLAN.md` (Phase 4 checkboxes), `docs/VERSIONS.md` (Phase 4 addendum), `docs/DEPENDENCIES.md` (§8 Cilium/Istio compatibility reconciled with the confirmed CNI-chaining values gap), `docs/DECISIONS.md` (+ADR-019 through ADR-024), root `README.md` (status line + module table row).

### Static validation

`istioctl` 1.30.3 was downloaded (explicit permission requested and granted), checksum-verified against the release's published `.sha256`, installed to `~/.local/bin` (user-local, no sudo) — the same disclosed-download pattern used for the Kyverno CLI in Phase 3.

| Check | Result |
| --- | --- |
| `bash -n`, 27 scripts | Pass — 27/27 |
| ShellCheck (severity: warning+, SC1091 excluded — same documented rationale as Phase 2/3), 27 scripts | Pass — 27/27, after fixing one real finding (below) |
| YAML structural validation, 38 files | Pass — 38/38, plus the `.tpl` JWT template's post-placeholder-substitution structure |
| `helm lint` | **Skipped, documented** — `helm` is not installed on this host; only the `istioctl` download was disclosed/approved this session |
| `istioctl analyze --use-kube=false` against every install/demo/policy manifest | **Pass — reports no errors** (real tool execution, not a schema-only check) |
| Manifest quality checks (API versions, duplicate names, `:latest` tags) | Pass, 1 non-fatal `WARN` — duplicate resource `name:` values across files (`default`, `frontend`, `order-service`, etc.) are expected/intentional (Service+Deployment name reuse across `kind`, and `permissive.yaml`/`strict.yaml` both intentionally naming their `PeerAuthentication` `default`, since only one is ever applied at a time) |
| Deprecated Istio API version detection | Pass — all manifests use current `networking.istio.io/v1`/`security.istio.io/v1`, no `v1alpha3`/`v1beta1` |
| Markdown link check (`istio/` only) | Pass — 48/48 relative links resolve across 42 files |
| `make help` | Pass — lists 26 targets |
| Secret-like file scan | Pass — none found |
| Nested `.git` scan | Pass — none found |
| Placeholder token scan | Pass — none found |
| `git diff --check` | Pass — clean, exit 0 |
| `kyverno/`, `opentelemetry-prometheus-grafana-jaeger-loki/`, `all-tools-integrated-lab/`, `auto-setup-default-kube-env/` unmodified | Pass — `git status --short` shows no changes under any of these paths |

**Two real bugs found and fixed via actually running the tools, not just review — the same category of lesson as Phase 2's SIGPIPE-under-pipefail discovery and Phase 3's `kyverno-test.yaml` schema mistakes:**

1. **ShellCheck SC2034** in `tests/circuit-breaking-test.sh`: `for i in $(seq 1 30); do` — the loop counter `i` was never referenced in the loop body (only used to repeat a fixed number of times). Fixed by renaming to `for _ in $(seq 1 30); do`.
2. **A SIGPIPE-under-pipefail bug in `tests/static-validation.sh` itself**: `grep -E '^  name:' "${f}" | awk '{print $2}' >>"${NAME_CHECK_FILE}"` inside a loop, unguarded, under `set -euo pipefail`. Any manifest file where that exact two-space-indented pattern found zero matches caused `grep` to exit 1, which — under `pipefail` and with no `if`/`||` guarding it — immediately terminated the entire validation script mid-run, silently, right after printing the next section's header. Found only because the full suite was actually executed twice (once before the fix, reproducing the silent stop, once after). Fixed by appending `|| true`, since zero matches is an expected, non-error case for this check.

### Runtime validation

**Not performed — no live cluster existed at any point during this phase**, matching this phase's own "no live cluster available" execution policy. Not run: `make verify-cluster`, `make install`, `make validate-installation`, `make deploy-demo`, `make test-runtime`, and all 10 `tests/*-test.sh` runtime scripts (including `cilium-compatibility-test.sh`, which specifically needs a live cluster to confirm the Cilium CNI-chaining Helm-values gap documented in `docs/DEPENDENCIES.md` §8 and `istio/docs/04-istio-cni-and-cilium.md`).

**To complete runtime validation:**

```bash
cd auto-setup-default-kube-env
make prerequisites && make setup LAB_PROFILE=recommended && make validate
export KUBECONFIG="$(pwd)/.generated/kubeconfig"

cd ../istio
make prerequisites
make verify-cluster   # heed the Cilium CNI-chaining WARNING if one appears
# If warned: run the printed `helm upgrade cilium ... --reuse-values` command manually first.
make install LAB_PROFILE=recommended
make validate-installation
make deploy-demo
make test-runtime
```

### Items not testable in this phase

- Everything under "Runtime validation" above.
- `helm lint` against the actual pinned charts (documented skip, not a silent omission — see the static-validation table above).
- The Cilium CNI-chaining compatibility gap itself (`docs/DEPENDENCIES.md` §8) can be *documented and detected* statically (the exact Helm values are known from upstream Cilium documentation), but whether this cluster's actual Cilium release needs the remediation can only be confirmed by `make verify-cluster`/`make install` against a live cluster.
- Statistical/timing-sensitive runtime tests (canary-split tolerance, circuit-breaker overflow, fault-injection rate) by nature require live traffic and cannot be meaningfully approximated statically.

### Next phase

```text
Phase 5: Independent observability lab (OpenTelemetry, Prometheus, Grafana, Jaeger, Loki)
```
