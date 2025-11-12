# AKS + Azure SQL with Workload Identity

This project demonstrates a simple C# ASP.NET Core web application deployed to Azure Kubernetes Service (AKS) that connects to Azure SQL Database using Entra ID authentication via Workload Identity (federated tokens).

## Architecture

- **Application**: ASP.NET Core 8.0 web app displaying "Hello World"
- **Container Platform**: Azure Kubernetes Service (AKS)
- **Database**: Azure SQL Database with Entra-only authentication
- **Authentication**: AKS Workload Identity with federated credentials
- **Container Registry**: Azure Container Registry (ACR)
- **Deployment**: Azure Developer CLI (azd)

## Features

- ✅ Passwordless authentication to Azure SQL using Workload Identity
- ✅ Entra-only authentication (no SQL passwords)
- ✅ Infrastructure as Code using Bicep with Azure Verified Modules
- ✅ Secure container deployment with non-root user
- ✅ One-command deployment with `azd up`

## Prerequisites

1. **Azure Developer CLI (azd)**: [Install azd](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
2. **Azure CLI**: [Install az CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
3. **Docker**: [Install Docker](https://docs.docker.com/get-docker/)
4. **kubectl**: [Install kubectl](https://kubernetes.io/docs/tasks/tools/)
5. **Azure Subscription**: You need an active Azure subscription

## Quick Start

### 1. Login to Azure

```powershell
azd auth login [--tenant-id <tenant-id-or-domain>]
az login [--tenant <tenant name or id>]
```

### 2. Initialize Environment

```powershell
# Set environment name (will be used in resource naming)
azd env new <environment-name>

# Set location for resources
azd env set AZURE_LOCATION eastus
```

### 3. (Optional) Configure SQL Admin

By default, the managed identity created for workload identity will be set as the SQL admin. If you want to use your own account:

```powershell
# Get your Azure AD Object ID
$objectId = az ad signed-in-user show --query id -o tsv

# Set as SQL admin
azd env set SQL_ADMIN_OBJECT_ID $objectId
azd env set SQL_ADMIN_LOGIN "your-email@example.com"
```

### 4. Deploy Everything

```powershell
azd up
```

This single command will:
1. Provision all Azure resources (AKS, SQL Database, ACR, Managed Identity)
2. Build and push the Docker image to ACR
3. Deploy the application to AKS
4. Configure workload identity
5. Display the application URL

### 5. Grant SQL Database Access to Managed Identity

The managed identity needs permission to access the SQL database. You can do this using the provided script or manually:

#### Option A: Using the Setup Script (Requires sqlcmd or Azure Data Studio)

```powershell
./scripts/setup-sql-user.ps1
```

#### Option B: Manual Setup via Azure Portal

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to your SQL database `helloworlddb`
3. Click **Query editor** in the left menu
4. Sign in with your Azure AD account
5. Run this SQL command (replace the identity name with your actual workload identity name from `azd env get-values | Select-String AZURE_WORKLOAD_IDENTITY_NAME`):

```sql
-- Get your workload identity name from: azd env get-values | Select-String AZURE_WORKLOAD_IDENTITY_NAME
CREATE USER [<your-workload-identity-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [<your-workload-identity-name>];
ALTER ROLE db_datawriter ADD MEMBER [<your-workload-identity-name>];
```

Example:
```sql
CREATE USER [id-7wxauy2fk32fi] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [id-7wxauy2fk32fi];
ALTER ROLE db_datawriter ADD MEMBER [id-7wxauy2fk32fi];
```

#### Option C: Using Azure Data Studio or SSMS

1. Connect to your SQL server (get the FQDN from `azd env get-values | Select-String AZURE_SQL_SERVER_FQDN`)
2. Select the database `helloworlddb`
3. Use **Azure Active Directory - Universal with MFA** authentication
4. Run the same SQL commands as above

### 6. Access the Application

After deployment completes and SQL user is configured, the output will show the application URL:

```
Application deployed successfully!
Access your application at: http://<EXTERNAL-IP>
```

Visit the URL in your browser to see "Hello World from AKS!" with database connection status.

**Test the endpoint:**
```powershell
curl http://<EXTERNAL-IP>
```

Expected output:
```html
<html><body><h1>Hello World from AKS!</h1><p style='color: green;'>✓ Database connection successful!</p></body></html>
```

## Project Structure

```
.
├── src/
│   └── HelloWorldApp/
│       ├── Program.cs              # Main application code
│       ├── HelloWorldApp.csproj    # Project file with dependencies
│       ├── appsettings.json        # Application configuration
│       ├── Dockerfile              # Container image definition
│       └── .dockerignore           # Docker ignore file
├── manifests/
│   └── deployment.yaml             # Kubernetes manifests (with workload identity)
├── infra/
│   ├── main.bicep                  # Main infrastructure template
│   ├── main.bicepparam             # Parameters file
│   ├── federated-credential.bicep  # Federated identity module
│   └── abbreviations.json          # Resource naming abbreviations
├── scripts/
│   └── setup-sql-user.ps1          # Script to create SQL user for managed identity
├── azure.yaml                      # Azure Developer CLI configuration
└── README.md                       # This file
```

## How It Works

### Workload Identity Flow

1. AKS cluster is configured with OIDC Issuer enabled
2. A Kubernetes service account is annotated with Azure Managed Identity client ID
3. A federated identity credential links the K8s service account to the Azure Managed Identity
4. The pod uses `DefaultAzureCredential` which automatically detects workload identity
5. Azure issues a token that grants the pod access to Azure SQL Database

### Security Features

- **No passwords**: Completely passwordless authentication using Entra ID
- **Non-root containers**: Application runs as non-privileged user
- **Entra-only SQL**: SQL authentication is disabled, only Entra ID auth allowed
- **Managed identities**: No service principal secrets to manage
- **RBAC**: Proper role assignments for least privilege access

## Management Commands

### Update the Application

```powershell
# Make code changes, then:
azd deploy
```

### View Kubernetes Resources

```powershell
# Get AKS credentials
az aks get-credentials --resource-group <resource-group> --name <aks-cluster>

# View pods
kubectl get pods -n helloworld

# View service
kubectl get service -n helloworld

# View logs
kubectl logs -n helloworld -l app=helloworld
```

### Clean Up Resources

```powershell
azd down
```

This will delete all Azure resources created by the deployment.

## Troubleshooting

### Application can't connect to database

**Error: "Login failed for user '<token-identified principal>'"**

This means the managed identity hasn't been granted access to the SQL database. Follow step 5 above to create the SQL user.

You can verify by:

1. Check that the SQL user was created:
   - Connect to the database using Azure Portal Query Editor
   - Run: `SELECT name, type_desc FROM sys.database_principals WHERE name = '<your-identity-name>';`

2. Check that the managed identity exists:
   ```powershell
   $env = azd env get-values | ConvertFrom-StringData
   az identity show --name $env.AZURE_WORKLOAD_IDENTITY_NAME --resource-group $env.AZURE_RESOURCE_GROUP
   ```

3. Verify federated credential is configured:
   ```powershell
   $env = azd env get-values | ConvertFrom-StringData
   az identity federated-credential list --identity-name $env.AZURE_WORKLOAD_IDENTITY_NAME --resource-group $env.AZURE_RESOURCE_GROUP
   ```

4. Check pod logs for authentication errors:
   ```powershell
   kubectl logs -n helloworld -l app=helloworld
   ```

5. Verify the service account annotation:
   ```powershell
   kubectl get serviceaccount helloworld-sa -n helloworld -o yaml
   ```
   Should show: `azure.workload.identity/client-id: <client-id>`

### LoadBalancer IP not assigned

This can take a few minutes. Check status:
```powershell
kubectl get service helloworld-service -n helloworld --watch
```

### Docker build fails

Ensure Docker is running:
```powershell
docker info
```

## Learn More

- [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/azure/aks/)
- [Workload Identity for AKS](https://learn.microsoft.com/azure/aks/workload-identity-overview)
- [Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Verified Modules](https://aka.ms/avm)

## License

This project is provided as-is for demonstration purposes.
