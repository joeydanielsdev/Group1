terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.105.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "sugarcane"
  location = "East US"
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "myVnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subnets
resource "azurerm_subnet" "public" {
  name                 = "publicSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "private" {
  name                 = "privateSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Groups
resource "azurerm_network_security_group" "frontend_sg" {
  name                = "frontendNSG"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "backend_sg" {
  name                = "backendNSG"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowApp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "db_sg" {
  name                = "dbNSG"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowSQL"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.0.2.0/24"
    destination_address_prefix = "*"
  }
}

# Network Interfaces
resource "azurerm_network_interface" "frontend_nic" {
  name                = "frontendNic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "frontendIpConfig"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "backend_nic" {
  name                = "backendNic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "backendIpConfig"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Public IP for Frontend
resource "azurerm_public_ip" "frontend_ip" {
  name                = "frontendPublicIp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "lbPublicIp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
}

# Load Balancer
resource "azurerm_lb" "main" {
  name                = "myLoadBalancer"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }
}

# Load Balancer Backend Address Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id     = azurerm_lb.main.id
  name                = "BackendAddressPool"
}

# Load Balancer Probe
resource "azurerm_lb_probe" "http_probe" {
  loadbalancer_id     = azurerm_lb.main.id
  name                = "httpProbe"
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 5
  number_of_probes    = 2
}

# Load Balancer Rule
resource "azurerm_lb_rule" "http_rule" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "httpRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"

  probe_id                       = azurerm_lb_probe.http_probe.id
}

# Frontend VM
resource "azurerm_windows_virtual_machine" "frontend" {
  name                  = "frontendVM"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  admin_password        = "AdminPassword123!"
  network_interface_ids = [azurerm_network_interface.frontend_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  computer_name            = "frontendVM"
  provision_vm_agent       = true
  enable_automatic_updates = true
}

# Backend VM
resource "azurerm_windows_virtual_machine" "backend" {
  name                  = "backendVM"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  admin_password        = "AdminPassword123!"
  network_interface_ids = [azurerm_network_interface.backend_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  computer_name            = "backendVM"
  provision_vm_agent       = true
  enable_automatic_updates = true
}

# SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = "mysqlserver2024"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "Guard_098@2@"

  tags = {
    environment = "production"
  }
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  name      = "mydatabase"
  server_id = azurerm_mssql_server.main.id
  sku_name  = "Basic"
}

# SQL Firewall Rule
resource "azurerm_mssql_firewall_rule" "allow_all_azure_ips" {
  name                = "AllowAllAzureIPs"
  server_id = azurerm_mssql_server.main.id
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

output "frontend_lb_ip" {
  description = "Public IP of the Load Balancer"
  value       = azurerm_public_ip.lb_public_ip.ip_address
}

