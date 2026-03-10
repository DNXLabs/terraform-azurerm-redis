resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "azurerm_resource_group" "dns" {
  for_each = local.dns_rg_create ? { "this" = true } : {}
  name     = local.dns_rg_name
  location = local.dns_rg_loc
  tags     = local.tags
}

resource "azurerm_redis_cache" "this" {
  count = local.is_enterprise ? 0 : 1

  name                = local.redis_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  sku_name = try(var.redis.sku_name, "Premium")
  family   = try(var.redis.family, "P")
  capacity = try(var.redis.capacity, 1)

  shard_count = try(var.redis.shard_count, null)
  zones       = try(var.redis.zones, null)

  non_ssl_port_enabled          = try(var.redis.non_ssl_port_enabled, false)
  minimum_tls_version           = try(var.redis.minimum_tls_version, "1.2")
  public_network_access_enabled = try(var.redis.public_network_access_enabled, false)

  redis_version = try(var.redis.redis_version, "6")

  dynamic "redis_configuration" {
    for_each = local.redis_cfg_has_values ? [local.redis_cfg] : []
    content {
      authentication_enabled          = lookup(redis_configuration.value, "authentication_enabled", null)
      maxmemory_policy                = lookup(redis_configuration.value, "maxmemory_policy", null)
      maxmemory_reserved              = lookup(redis_configuration.value, "maxmemory_reserved", null)
      maxmemory_delta                 = lookup(redis_configuration.value, "maxmemory_delta", null)
      maxfragmentationmemory_reserved = lookup(redis_configuration.value, "maxfragmentationmemory_reserved", null)
      notify_keyspace_events          = lookup(redis_configuration.value, "notify_keyspace_events", null)

      aof_backup_enabled              = lookup(redis_configuration.value, "aof_backup_enabled", null)
      aof_storage_connection_string_0 = lookup(redis_configuration.value, "aof_storage_connection_string_0", null)
      aof_storage_connection_string_1 = lookup(redis_configuration.value, "aof_storage_connection_string_1", null)

      rdb_backup_enabled              = lookup(redis_configuration.value, "rdb_backup_enabled", null)
      rdb_storage_connection_string   = lookup(redis_configuration.value, "rdb_storage_connection_string", null)
      rdb_backup_frequency            = lookup(redis_configuration.value, "rdb_backup_frequency", null)
      rdb_backup_max_snapshot_count   = lookup(redis_configuration.value, "rdb_backup_max_snapshot_count", null)
    }
  }

  tags = local.tags
}

resource "azurerm_managed_redis" "this" {
  count = local.is_enterprise ? 1 : 0

  name                = local.redis_name
  resource_group_name = local.rg_name
  location            = local.rg_loc

  sku_name = var.redis.sku_name # e.g. Balanced_B0

  default_database {
    clustering_policy = try(var.redis.clustering_policy, "OSSCluster")
  }

  tags = local.tags
}

resource "azurerm_private_dns_zone" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.dns_zone_should_create[k] }

  name                = each.value.zone_name
  resource_group_name = local.dns_rg_name
  tags                = local.tags
  depends_on = [
    azurerm_resource_group.dns
  ]
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = { for k, v in local.pe_services_enabled : k => v if local.vnet_link_should_create[k] }

  name                = each.value.link_name
  resource_group_name = local.dns_rg_name

  private_dns_zone_name = coalesce(
    try(azurerm_private_dns_zone.this[each.key].name, null),
    each.value.zone_name
  )

  virtual_network_id = local.vnet_id
  tags               = local.tags

  depends_on = [
    azurerm_resource_group.dns,
    azurerm_private_dns_zone.this
  ]
}

resource "azurerm_private_endpoint" "this" {
  for_each            = local.pe_services_enabled
  name                = each.value.pe_name
  location            = local.pe_rg_loc
  resource_group_name = local.pe_rg_name
  subnet_id                     = local.pe_subnet_id
  custom_network_interface_name = each.value.nic_name
  tags                          = local.tags

  private_service_connection {
    name                           = each.value.psc_name
    private_connection_resource_id = local.is_enterprise ? azurerm_managed_redis.this[0].id : azurerm_redis_cache.this[0].id
    is_manual_connection           = false
    subresource_names              = [each.value.subresource]
  }

  private_dns_zone_group {
    name                 = "pdzg-${each.key}"
    private_dns_zone_ids = [local.private_dns_zone_id[each.key]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.redis_name}"
  target_resource_id             = local.is_enterprise ? azurerm_managed_redis.this[0].id : azurerm_redis_cache.this[0].id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "ConnectedClientList" }

  enabled_metric {
    category = "AllMetrics"
  }
}
