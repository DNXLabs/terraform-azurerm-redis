output "resource_group_name" {
  value = local.rg_name
}

output "redis" {
  value = {
    id       = local.is_enterprise ? try(azurerm_managed_redis.this[0].id, null) : try(azurerm_redis_cache.this[0].id, null)
    name     = local.is_enterprise ? try(azurerm_managed_redis.this[0].name, null) : try(azurerm_redis_cache.this[0].name, null)
    hostname = local.is_enterprise ? try(azurerm_managed_redis.this[0].hostname, null) : try(azurerm_redis_cache.this[0].hostname, null)
    port     = local.is_enterprise ? try(azurerm_managed_redis.this[0].default_database[0].port, 10000) : try(azurerm_redis_cache.this[0].port, null)
    ssl_port = local.is_enterprise ? try(azurerm_managed_redis.this[0].default_database[0].port, 10000) : try(azurerm_redis_cache.this[0].ssl_port, null)

    private_endpoints = {
      for k, pe in azurerm_private_endpoint.this :
      k => {
        id                 = pe.id
        name               = pe.name
        private_ip_address = try(pe.private_service_connection[0].private_ip_address, null)
      }
    }

    private_dns_zone_ids = {
      for k, v in local.pe_services_enabled :
      k => local.private_dns_zone_id[k]
    }
  }
}

output "primary_access_key" {
  value     = local.is_enterprise ? try(azurerm_managed_redis.this[0].default_database[0].primary_access_key, null) : try(azurerm_redis_cache.this[0].primary_access_key, null)
  sensitive = true
}

output "secondary_access_key" {
  value     = local.is_enterprise ? try(azurerm_managed_redis.this[0].default_database[0].secondary_access_key, null) : try(azurerm_redis_cache.this[0].secondary_access_key, null)
  sensitive = true
}
  