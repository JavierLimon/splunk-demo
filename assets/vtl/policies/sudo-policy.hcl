// Example policy: "sudo"
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}