# AGENTS.md

Reusable Terraform module. This file guides AI assistants and contributors. Write all documentation, comments, commit messages and
issues in English.

## Purpose
Builds a Talos Linux Kubernetes cluster on existing machines with the `siderolabs/talos` provider: secrets, machine configuration, etcd bootstrap, Kubernetes
and OS upgrades, kubeconfig and talosconfig. The module contains no context-specific value: everything goes through variables or patches.

Design rules specific to this module:
- Use `talos_machine` (configuration and OS version) and `talos_cluster` (bootstrap, health of the Talos layer, `upgrade-k8s`), not `talos_machine_configuration_apply`,
  `talos_machine_bootstrap` or `data.talos_cluster_health`. `talos_machine` always applies in AUTO mode and has no staged mode: document it, and tell users to run
  `terraform apply -parallelism=1` for changes that restart nodes. Recheck this in the provider source before each release.
- **The provider documentation and source on `main` are ahead of the releases.** Read the schema of the released version (`terraform providers schema -json`) and the
  source at the release tag. Example: `drain_timeout` is documented on `main` and absent in 0.12.0.
- Machine configuration is generated per node (`data.talos_machine_configuration.node`), because `talos_machine` takes a finished configuration and has no patch argument.
- Typed options are limited to common Talos settings. Everything else goes through `config_patches`. Patch order is part of the contract: base, control plane,
  disk encryption, node, then the caller's patches (all, role, node). Do not reorder it.
- **One format: the Talos v1.14 documents** (`patches.tf`, `local.talos_contract`). The provider generates a document for most settings and a node refuses the same setting in `v1alpha1`
  (`X is already set in v1alpha1 config`), so patch the generated document and never write the deprecated v1alpha1 field of a setting that has one. Field names come from the Talos sources at the release
  tag (`pkg/machinery/config/types`), not from the website. To support a new Talos release, read what the provider generates for it (offline, see below), diff the documents against `patches.tf`,
  then move the contract: a change of format is a major version.
- Patch a document the provider already generates (merge by kind), never create one the provider omits for that role: a worker gets no `KubeProxyConfig` or `KubeFlannelCNIConfig`,
  and a created document lacks required fields such as `image`. `$patch: delete` removes a document (Flannel for `cni = none`). A merge patch cannot remove a map key: the control-plane
  taint is removed by deleting `KubeNodeConfig` and writing it again.
- **The offline parser does not run the node's validation.** At the first real apply of the v1.14 documents the node refused two things the provider accepted: a CEL selector that compared the enum
  `link.type` with a string (it is an integer: `1` is `LINK_ETHER`), and `0.0.0.0/0` as a route destination (a default route has no `destination`). Check every CEL expression and every address against the
  Go validation of the document (`Validate()` in its source), not only against the example. Check each new document on a real node.
- Terraform cannot unify `cond ? {a = x, b = y} : {}` when the attributes have different types. Build sections with `merge()` of single-attribute conditionals.
- `keys()` returns names in lexical order: the first control plane by name bootstraps etcd. No `sort()` needed.
- The module never writes files and never reads files: the caller passes certificates as strings and writes the outputs where it wants.
- `secrets` is optional and sensitive. Whether it is set is read with `nonsensitive()`, because `count` cannot depend on a sensitive value.
- `kubeconfig` is an ephemeral variable (write-only `kubeconfig_wo`): never store it.
- OIDC needs Kubernetes 1.34 or later (`AuthenticationConfiguration` v1, checked in the Kubernetes source). The cidr membership of IP addresses is not validated: Terraform has no `cidrcontains`.
- Tests use `mock_provider`, which does not run the Talos configuration parser. Before a release that changes a patch, generate a real configuration offline: in a throwaway
  directory call the module and `terraform apply -target=module.<name>.data.talos_machine_configuration.node` with the real provider (it generates the PKI and the configuration locally,
  without contacting a machine), then read the result. **Delete that directory afterwards: its state holds generated secrets.**
- **That real check must turn on every typed option at once, including the nested ones** (`tpm_require_secureboot`, `oidc`, `encryption`, subnets, patches), and the other values of an option (`node_id`).
  An option that was not in the check was not checked: `tpm_require_secureboot` was written under `tpm.options` and the Talos parser refused it only at the first real apply.
  The Talos documentation tables list nested fields in a way that is easy to misread: confirm the nesting in the Go types (`yaml:"..."` tags in
  `pkg/machinery/config/types/block/*.go` of the Talos version embedded in the provider, see its `go.mod`), not in the website tables.
- A mutation check (break one validation, the patch order, the secrets switch) must make a test fail.

## Commands
- `terraform fmt -recursive`: format the code.
- `terraform init -backend=false && terraform validate`: validate the module.
- `tflint --init && tflint --recursive`: static analysis.
- `terraform test`: tests without real infrastructure (`command = plan` or `mock_provider`).
- `pre-commit run --all-files`: run everything at once, including `terraform-docs` and Trivy.

## Layout
`main.tf` (resources), `patches.tf` (the configuration patches of each node), `variables.tf`, `outputs.tf` and `versions.tf` at the root, `examples/` (one directory per example), `tests/` (`*.tftest.hcl`).
Resources, data sources and locals stay in `main.tf`. Split by theme if the file grows, never by block type.
The inputs and outputs tables in `README.md` are generated by `terraform-docs`: do not edit them by hand.

## Code conventions
- `snake_case` names, without repeating the resource type. Use `this` for the single resource of a type.
- Every variable and output has a `description` and a `type`. Set `sensitive = true` on secrets. Set `nullable = false` when `null` makes no sense.
- Use `for_each` for collections and `count = var.enabled ? 1 : 0` for conditional creation, as the first line of the block.
- **No `provider` block in the module.** Declare `required_providers` with a lower bound only (`>= x`).
- Rename a resource with a `moved` block, never by destroying it.

## Versions
Never write code from memory of an old release. Before starting, and before each release:
- Check the latest stable versions of Terraform and of every provider (registry, GitHub releases) and read the changelogs since the version you know.
- Use the new features that apply (for example output `type`, Terraform 1.15) and say so in the commit message.
- The lower bound of a module is the oldest release that provides the features it really uses. CI tests the lower bound and the latest release.
- Examples and tests use current versions of the tools they mention (for example the current Talos release), not a version from memory.

## Tests
Every variable with a `validation` has an `expect_failures` test. Every optional feature has a test with and without it.
Tests never call a real API.

## Security
- No secret, state file, `.tfvars` or kubeconfig in Git. See `SECURITY.md`.
- No permissive resource "just to test" (firewall rules, permissions).
- Run `terraform plan` and get human approval before any `apply` in a live repository.

## Commits and versions
Conventional Commits: `fix:` (patch), `feat:` (minor), `feat!:` or `BREAKING CHANGE:` (major). Squash-merge into `main`.
`release-please` opens the release pull request, creates the SemVer tag and `CHANGELOG.md`. Never tag by hand.
