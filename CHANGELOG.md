# Changelog

## [1.0.0](https://github.com/itlinuxfr/terraform-talos-cluster/compare/v0.1.1...v1.0.0) (2026-11-14)


### ⚠ BREAKING CHANGES

* the talos_version variable is removed and the module no longer builds a cluster with a Talos contract older than v1.14.

### Features

* support Talos 1.14 and later only, with one configuration format ([f6b599f](https://github.com/itlinuxfr/terraform-talos-cluster/commit/f6b599f6345039ea4cea8ee63e94b17b5da1d77b))
* write the Talos multi-document configuration for the v1.14 contract ([cb73bd1](https://github.com/itlinuxfr/terraform-talos-cluster/commit/cb73bd1e27793e5759f4cd54eb11c2e9619022ad))
* write the Talos multi-document configuration for the v1.14 contract ([a06fd7b](https://github.com/itlinuxfr/terraform-talos-cluster/commit/a06fd7bc12a91198afc5396ef155b541e06dad47))


### Bug Fixes

* use the link type enum and a destination-less default route in the v1.14 documents ([b902d4f](https://github.com/itlinuxfr/terraform-talos-cluster/commit/b902d4f20bd98fef42d818683ac1f3bccc843d67))


### Miscellaneous Chores

* release 1.0.0 ([9062645](https://github.com/itlinuxfr/terraform-talos-cluster/commit/90626457fbc64600109bd5fdd6d219d73b0cfca3))

## [0.1.1](https://github.com/itlinuxfr/terraform-talos-cluster/compare/v0.1.0...v0.1.1) (2026-11-14)


### Bug Fixes

* refuse a configuration contract of v1.14 or later ([a8a9752](https://github.com/itlinuxfr/terraform-talos-cluster/commit/a8a97528f1c27e2a5ff3f4322e1bea5913316b08))
* refuse a configuration contract of v1.14 or later ([71e3a04](https://github.com/itlinuxfr/terraform-talos-cluster/commit/71e3a041af0c557b21e36c5f0cbdb60bfe0a83d8))
* write checkSecurebootStatusOnEnroll next to tpm options, not inside them ([6ace1d5](https://github.com/itlinuxfr/terraform-talos-cluster/commit/6ace1d534ba534ea7dea263c9d15e7e7e3eacff9))
* write checkSecurebootStatusOnEnroll next to tpm options, not inside them ([deae97d](https://github.com/itlinuxfr/terraform-talos-cluster/commit/deae97d360bddf07ddf2275419e6a4576f8439ff))

## 0.1.0 (2026-11-14)


### ⚠ BREAKING CHANGES

* rewrite the module around talos_machine and talos_cluster

### Features

* rewrite the module around talos_machine and talos_cluster ([31d5684](https://github.com/itlinuxfr/terraform-talos-cluster/commit/31d56840a9f6a6f4b369dca21f89bcabcdeac632))
