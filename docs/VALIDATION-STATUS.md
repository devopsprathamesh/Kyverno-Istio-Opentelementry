# Validation Status

This document is the source of truth for what has actually been built and validated in this repository, as opposed to what is merely planned or documented. Update it at the end of every phase.

| Phase | Status | Validation performed | Result | Known limitations |
| --- | --- | --- | --- | --- |
| Phase 1 — Repository architecture and governance | Complete | Documentation existence check, placeholder-token scan, secret-file scan, nested-`.git` scan, `git diff --check`, relative markdown-link resolution check, manual Mermaid syntax review | Pass (see below) | Mermaid diagrams were not tool-validated — no `node`/`npx`/Mermaid CLI was available in this environment; only manual syntax review was performed |
| Phase 2 — Base VirtualBox and Vagrant Kubernetes environment | **Partial** — automation built and statically validated; live-cluster runtime validation not performed | File existence, `bash -n` + ShellCheck (if available), `ruby -c`/`vagrant validate`, YAML template structural checks, `make help` review, markdown-link check, git-safety checks; host tool presence (`VBoxManage`/`vagrant --version`) confirmed directly | Static suite: pass (see below). Runtime (VM boot, kubeadm, Cilium, storage, network tests): **not run**, by explicit user choice this session | No live cluster exists yet. See Phase 2 detail below for the exact commands to complete runtime validation, and known/deferred risks. |
| Phase 3 — Independent Kyverno lab | Not started | — | — | — |
| Phase 4 — Independent Istio lab | Not started | — | — | — |
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

### Next phase

```text
Phase 3: Independent Kyverno hands-on lab
```
