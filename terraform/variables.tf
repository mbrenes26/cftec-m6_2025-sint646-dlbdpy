# Ubicación por defecto para recursos en Azure
variable "location" {
  description = "Ubicación donde se desplegarán los recursos en Azure"
  type        = string
  default     = "westus2"
}

# Nombre del proyecto para identificar recursos
variable "project_name" {
  description = "Nombre base del proyecto"
  type        = string
  default     = "cftec-m6_2025-sint646-dlbdpy"
}
