variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "redis" {
  description = "Azure Cache for Redis configuration."
  type = object({
    name        = optional(string)

    sku_name = optional(string, "Premium") # Basic | Standard | Premium
    family   = optional(string, "P")       # C for Basic/Standard, P for Premium
    capacity = optional(number, 1)

    shard_count = optional(number)
    zones       = optional(list(string))

    minimum_tls_version           = optional(string, "1.2") # 1.0 | 1.1 | 1.2
    non_ssl_port_enabled          = optional(bool, false)
    public_network_access_enabled = optional(bool, false)

    redis_version = optional(string, "6")

    # In azurerm v4.x this is a BLOCK (redis_configuration { ... })
    # We accept a map and map known keys into the block.
    redis_configuration = optional(map(any), {})
  })
}

variable "private" {
  type = object({
    enabled = bool

    endpoints = optional(map(bool), {
      redis = true
    })

    pe_subnet_id = optional(string)
    vnet_id      = optional(string)

    dns = optional(object({
      create_zone      = optional(bool, true)
      create_vnet_link = optional(bool, true)

      resource_group = optional(object({
        create   = bool
        name     = string
        location = optional(string)
      }))

      resource_group_name = optional(string)
    }), {})
  })
}

variable "private_endpoint" {
  description = "Where to place Private Endpoints (RG/location). Only required when private.enabled = true."
  type = object({
    resource_group_name = string
    location            = optional(string)
  })
  default = null
}
