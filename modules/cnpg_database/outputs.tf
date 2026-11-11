output "cluster_name" {
  description = "Name of the Cluster and Helm release (var.name)."
  value       = var.name
}

output "secret_name" {
  description = "CNPG-generated application Secret (<name>-app) with keys host, port, dbname, username, password. Pass to the app (Firezone database_secret_name)."
  value       = "${var.name}-app"
}
