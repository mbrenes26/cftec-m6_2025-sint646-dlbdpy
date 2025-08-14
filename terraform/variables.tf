# Ubicación por defecto para recursos en Azure
variable "location" {
  description = "Ubicación donde se desplegarán los recursos en Azure"
  type        = string
  default     = "westus3"
}

# Nombre del proyecto para identificar recursos
variable "project_name" {
  description = "Nombre base del proyecto"
  type        = string
  default     = "cftec-m6_2025-sint646-dlbdpy"
}
variable "ssh_public_key" {
  description = "Clave pública SSH para acceso a la VM"
  type        = string
}
