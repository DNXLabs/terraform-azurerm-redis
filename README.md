# terraform-azurerm-redis

Terraform module for creating and managing Azure Cache for Redis with support for all SKU tiers (Basic, Standard, Premium), private endpoints with automatic DNS zone management, and advanced Redis configuration.

This module provides enterprise-grade caching infrastructure with configurable persistence, clustering, and secure connectivity through private endpoints.

## Features

- **Multiple SKU Support**: Basic, Standard, and Premium tiers
- **Redis Configuration**: Customizable memory policies, persistence (AOF/RDB), keyspace notifications
- **Clustering**: Shard count configuration for Premium tier
- **Availability Zones**: Zone support for Premium tier
- **Private Endpoints**: Automatic private endpoint creation for Redis
- **Private DNS Zones**: Automatic creation and management of private DNS zones
- **DNS Zone Auto-Discovery**: Reuses existing DNS zones when available
- **TLS Configuration**: Minimum TLS version enforcement
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support

## Usage

### Example 1 — Non-Prod (Standard, Public Access)

A simple Redis cache for development/testing with public access.

```hcl
module "redis" {
  source = "./modules/redis"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = true
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  redis = {
    sku_name = "Standard"
    family   = "C"
    capacity = 1

    public_network_access_enabled = true
    minimum_tls_version           = "1.2"

    redis_configuration = {
      maxmemory_policy = "allkeys-lru"
    }
  }

  private = {
    enabled = false
  }
}
```

### Example 2 — Production (Premium, Private, Clustered)

A production Redis cache with Premium SKU, clustering, private endpoints, and persistence.

```hcl
module "redis" {
  source = "./modules/redis"

  name = "contoso-prod-aue-cache"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-cache-001"
    location = "australiaeast"
  }

  tags = {
    project     = "cache-platform"
    environment = "production"
    compliance  = "soc2"
  }

  redis = {
    sku_name = "Premium"
    family   = "P"
    capacity = 2

    shard_count = 3
    zones       = ["1", "2", "3"]

    public_network_access_enabled = false
    minimum_tls_version           = "1.2"
    non_ssl_port_enabled          = false

    redis_version = "6"

    redis_configuration = {
      maxmemory_policy                = "volatile-lru"
      maxmemory_reserved              = "256"
      maxmemory_delta                 = "256"
      maxfragmentationmemory_reserved = "256"
      rdb_backup_enabled              = true
      rdb_backup_frequency            = 60
      rdb_backup_max_snapshot_count   = 1
    }
  }

  private = {
    enabled = true

    endpoints = {
      redis = true
    }

    pe_subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-pe"
    vnet_id      = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod"

    dns = {
      create_zone      = true
      create_vnet_link = true

      resource_group = {
        create = false
        name   = "rg-contoso-prod-aue-dns-001"
      }
    }
  }

  private_endpoint = {
    resource_group_name = "rg-contoso-prod-aue-network-001"
    location            = "australiaeast"
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/platform.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"
  pe_subnet_name: "snet-stg-pe"

platform:
  redis_caches:
    session-cache:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      redis:
        sku_name: Premium
        family: P
        capacity: 1
        public_network_access_enabled: false
        minimum_tls_version: "1.2"

        redis_configuration:
          maxmemory_policy: allkeys-lru

      private:
        enabled: true
        endpoints:
          redis: true
        dns:
          create_zone: true
          create_vnet_link: true
          resource_group:
            create: true
            name: "rg-dns-services-lab-aue-001"
            location: australiaeast
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_resource_group" "network" {
  name = local.workspace.network_lookup.resource_group_name
}

data "azurerm_virtual_network" "this" {
  name                = local.workspace.network_lookup.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

data "azurerm_subnet" "pe" {
  name                 = local.workspace.network_lookup.pe_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_resource_group.network.name
}

module "redis" {
  for_each = try(local.workspace.platform.redis_caches, {})

  source = "./modules/redis"

  name           = "${each.value.naming.org}-${each.value.naming.env}-${each.value.naming.region}-${each.value.naming.workload}"
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  redis = each.value.redis

  private = merge(
    try(each.value.private, { enabled = false }),
    try(each.value.private, {}).enabled == true ? {
      pe_subnet_id = data.azurerm_subnet.pe.id
      vnet_id      = data.azurerm_virtual_network.this.id
    } : {}
  )

  private_endpoint = try(each.value.private, {}).enabled == true ? {
    resource_group_name = data.azurerm_resource_group.network.name
    location            = data.azurerm_resource_group.network.location
  } : null

  diagnostics = try(each.value.diagnostics, {})
}
```

## Redis SKU Tiers

| SKU | Family | Use Case | Features |
|-----|--------|----------|----------|
| `Basic` | `C` | Dev/test | No SLA, no replication |
| `Standard` | `C` | General purpose | SLA-backed, replica node |
| `Premium` | `P` | Production | Clustering, persistence, zones, VNet |

## Redis Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `maxmemory_policy` | Eviction policy when max memory is reached | `volatile-lru` |
| `maxmemory_reserved` | Memory reserved for non-cache operations (MB) | – |
| `maxmemory_delta` | Memory reserved for fragmentation (MB) | – |
| `maxfragmentationmemory_reserved` | Memory for fragmentation overhead (MB) | – |
| `rdb_backup_enabled` | Enable RDB persistence (Premium only) | `false` |
| `rdb_backup_frequency` | RDB snapshot frequency in minutes | – |
| `aof_backup_enabled` | Enable AOF persistence (Premium only) | `false` |
| `notify_keyspace_events` | Keyspace notification configuration | – |

## Private Endpoints

### Supported Services

The module supports private endpoints for:
- **redis**: Azure Cache for Redis (`privatelink.redis.cache.windows.net`)

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- Redis Cache: `redis-{name}-001`
- Private Endpoint: `{name}-pe-redis`

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Resource Group where Redis is deployed |
| `redis` | Redis object with id, name, hostname, port, ssl_port, endpoints, DNS zones |
| `primary_access_key` | Primary access key (sensitive) |
| `secondary_access_key` | Secondary access key (sensitive) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `redis` | Redis cache configuration (SKU, capacity, TLS) | object | yes |
| `private` | Private endpoint configuration | object | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |
| `private_endpoint` | Private endpoint resource group placement | object | no |

### Detailed Input Specifications

#### redis

```hcl
object({
  name        = optional(string)
  name_suffix = optional(string, "001")

  sku_name = optional(string, "Premium")  # Basic | Standard | Premium
  family   = optional(string, "P")        # C (Basic/Standard) | P (Premium)
  capacity = optional(number, 1)

  shard_count = optional(number)          # Premium only
  zones       = optional(list(string))    # Premium only

  minimum_tls_version           = optional(string, "1.2")
  non_ssl_port_enabled          = optional(bool, false)
  public_network_access_enabled = optional(bool, false)

  redis_version = optional(string, "6")

  redis_configuration = optional(map(any), {})
})
```

#### private

```hcl
object({
  enabled = bool

  endpoints = optional(map(bool), {
    redis = true
  })

  pe_subnet_id = optional(string)  # Required if enabled = true
  vnet_id      = optional(string)  # Required if enabled = true

  dns = optional(object({
    create_zone      = optional(bool, true)
    create_vnet_link = optional(bool, true)
    resource_group = optional(object({
      create   = bool
      name     = string
      location = optional(string)
    }))
  }), {})
})
```

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.
