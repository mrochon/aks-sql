// Parameters file for main.bicep
using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'aks-sql-demo')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param sqlAdminLogin = readEnvironmentVariable('SQL_ADMIN_LOGIN', '')
param sqlAdminObjectId = readEnvironmentVariable('SQL_ADMIN_OBJECT_ID', '')
