output "nodes" {
  value = {
    for name, node in local.nodes : name => {
      vm_id       = node.vm_id
      ip_address  = node.ip_address
      target_node = node.target_node
      role        = node.role
    }
  }
}

output "control_plane_vip" {
  value = var.control_plane_vip
}

output "ssh_username" {
  value = var.ssh_username
}

output "bootstrap_command" {
  value = "../scripts/bootstrap-k3s.sh"
}
