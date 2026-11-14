terraform {
  # 1.15 adds explicit type constraints on outputs. The ephemeral variable (1.10) and the write-only kubeconfig_wo argument (1.11) are older.
  required_version = ">= 1.15"

  # A module declares a lower bound only: the live repository pins exact versions.
  # 0.12.0 is the first release checked with the talos_cluster and talos_machine resources used here.
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0"
    }
  }
}
