// ==================================================
// Main Bicep template for AKS + Azure SQL with Workload Identity
// ==================================================
// This template deploys:
// - Azure Kubernetes Service (AKS) with Workload Identity enabled
// - Azure SQL Database with Entra-only authentication
// - Azure Container Registry (ACR) for container images
// - User-assigned Managed Identity for workload identity
// - Federated Identity Credential linking AKS to the managed identity
// - Role assignments for SQL access

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the workload which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources.')
param location string

@description('The SQL administrator login name.')
param sqlAdminLogin string = ''

@description('The SQL administrator Azure AD Object ID.')
param sqlAdminObjectId string = ''

@description('SQL database name.')
param databaseName string = 'helloworlddb'

@description('Kubernetes namespace for the application.')
param kubernetesNamespace string = 'helloworld'

@description('Kubernetes service account name for workload identity.')
param kubernetesServiceAccountName string = 'helloworld-sa'

// Generate a unique suffix for resource names
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Resource group for all resources
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// ==================================================
// User-assigned Managed Identity for Workload Identity
// ==================================================
module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'workload-identity-${resourceToken}'
  scope: rg
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

// ==================================================
// Azure Container Registry (ACR)
// ==================================================
module acr 'br/public:avm/res/container-registry/registry:0.6.0' = {
  name: 'acr-${resourceToken}'
  scope: rg
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    acrSku: 'Basic'
    tags: tags
    // Enable admin user for azd to push images
    acrAdminUserEnabled: true
  }
}

// ==================================================
// Azure Kubernetes Service (AKS)
// ==================================================
module aks 'br/public:avm/res/container-service/managed-cluster:0.7.0' = {
  name: 'aks-${resourceToken}'
  scope: rg
  params: {
    name: '${abbrs.containerServiceManagedClusters}${resourceToken}'
    location: location
    // kubernetesVersion: kubernetesVersion // Using default version
    tags: tags
    
    // Enable Workload Identity and OIDC Issuer (required for federated identity)
    enableOidcIssuerProfile: true
    enableWorkloadIdentity: true
    
    // System-assigned managed identity for AKS
    managedIdentities: {
      systemAssigned: true
    }
    
    // Primary agent pool
    primaryAgentPoolProfiles: [
      {
        name: 'systempool'
        count: 2
        vmSize: 'Standard_DS2_v2'
        mode: 'System'
        osType: 'Linux'
        maxPods: 110
        availabilityZones: [] // Disable availability zones to avoid regional restrictions
      }
    ]
    
    // Enable RBAC for Kubernetes authorization
    enableRBAC: true
    
    // Network configuration (using kubenet for simpler setup)
    networkPlugin: 'kubenet'
    
    // Enable public network access to API server
    enablePrivateCluster: false
    publicNetworkAccess: 'Enabled'
    
    // Explicitly disable local accounts setting (requires AAD integration which we're not using)
    disableLocalAccounts: false
  }
}

// Grant AKS permission to pull images from ACR
module acrPullRole 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'acr-pull-role-${resourceToken}'
  scope: rg
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId!
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    resourceId: acr.outputs.resourceId
  }
}

// ==================================================
// Azure SQL Server with Entra-only Authentication
// ==================================================
module sqlServer 'br/public:avm/res/sql/server:0.9.0' = {
  name: 'sql-${resourceToken}'
  scope: rg
  params: {
    name: '${abbrs.sqlServers}${resourceToken}'
    location: location
    tags: tags
    
    // Entra-only authentication (no SQL authentication)
    administrators: {
      azureADOnlyAuthentication: true
      login: !empty(sqlAdminLogin) ? sqlAdminLogin : 'SQL Admin'
      sid: !empty(sqlAdminObjectId) ? sqlAdminObjectId : identity.outputs.principalId
      principalType: 'User'
      tenantId: subscription().tenantId
    }
    
    // Network rules - allow Azure services
    firewallRules: [
      {
        name: 'AllowAllAzureServices'
        startIpAddress: '0.0.0.0'
        endIpAddress: '0.0.0.0'
      }
    ]
    
    // Databases
    databases: [
      {
        name: databaseName
        sku: {
          name: 'Basic'
          tier: 'Basic'
        }
        maxSizeBytes: 2147483648 // 2GB
        zoneRedundant: false // Disable zone redundancy for Basic tier
      }
    ]
  }
}

// Grant managed identity SQL DB Contributor role on the database
// This is done in a separate module to handle scoping correctly
module sqlDbContributorRole 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'sql-db-contributor-role-${resourceToken}'
  scope: rg
  params: {
    principalId: identity.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // SQL DB Contributor
    resourceId: sqlServer.outputs.resourceId
  }
}

// ==================================================
// Federated Identity Credential
// ==================================================
// Links the Kubernetes service account to the managed identity
module federatedCredential './federated-credential.bicep' = {
  name: 'federated-credential-${resourceToken}'
  scope: rg
  params: {
    identityName: identity.outputs.name
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl!
    kubernetesNamespace: kubernetesNamespace
    kubernetesServiceAccountName: kubernetesServiceAccountName
  }
}

// ==================================================
// Outputs
// ==================================================
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = subscription().tenantId
output AZURE_RESOURCE_GROUP string = rg.name

// AKS outputs
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.name
output AZURE_AKS_OIDC_ISSUER_URL string = aks.outputs.oidcIssuerUrl!

// ACR outputs
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name

// SQL outputs
output AZURE_SQL_SERVER_NAME string = sqlServer.outputs.name
output AZURE_SQL_SERVER_FQDN string = '${sqlServer.outputs.name}${environment().suffixes.sqlServerHostname}'
output AZURE_SQL_DATABASE_NAME string = databaseName

// Workload Identity outputs
output AZURE_CLIENT_ID string = identity.outputs.clientId
output AZURE_WORKLOAD_IDENTITY_NAME string = identity.outputs.name

// Connection string (without credentials - uses Entra auth)
output SQL_CONNECTION_STRING string = 'Server=tcp:${sqlServer.outputs.name}${environment().suffixes.sqlServerHostname},1433;Database=${databaseName};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
