output "resource_group_name" {
  value = local.rg_name
}

output "redis" {
  value = {
    id       = azurerm_redis_cache.this.id
    name     = azurerm_redis_cache.this.name
    hostname = azurerm_redis_cache.this.hostname
    port     = azurerm_redis_cache.this.port
    ssl_port = azurerm_redis_cache.this.ssl_port

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
  value     = azurerm_redis_cache.this.primary_access_key
  sensitive = true
}

output "secondary_access_key" {
  value     = azurerm_redis_cache.this.secondary_access_key
  sensitive = true
}
  