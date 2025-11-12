<#
.SYNOPSIS
    Creates a SQL database user for the AKS workload identity.

.DESCRIPTION
    This script creates a SQL user for the managed identity so the application
    can authenticate to Azure SQL Database using Entra ID (formerly Azure AD).
    
    Prerequisites:
    - Azure CLI must be installed and logged in
    - You must be an Azure AD admin on the SQL server
    - sqlcmd or Azure Data Studio with SqlServer module

.EXAMPLE
    .\setup-sql-user.ps1
#>

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SQL User Setup for Workload Identity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get environment variables
try {
    $envVars = azd env get-values | ConvertFrom-StringData
    $sqlServer = $envVars.AZURE_SQL_SERVER_FQDN.Trim('"')
    $database = $envVars.AZURE_SQL_DATABASE_NAME.Trim('"')
    $identityName = $envVars.AZURE_WORKLOAD_IDENTITY_NAME.Trim('"')
    $resourceGroup = $envVars.AZURE_RESOURCE_GROUP.Trim('"')
    $sqlServerName = $envVars.AZURE_SQL_SERVER_NAME.Trim('"')
} catch {
    Write-Host "Error: Could not retrieve environment variables. Make sure you've run 'azd up' or 'azd provision' first." -ForegroundColor Red
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  SQL Server: $sqlServer"
Write-Host "  Database: $database"
Write-Host "  Managed Identity: $identityName"
Write-Host "  Resource Group: $resourceGroup"
Write-Host ""

# Get access token for SQL
$token = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)

# Verify current user is SQL admin
Write-Host "Verifying permissions..." -ForegroundColor Yellow
try {
    $admins = az sql server ad-admin list --server $sqlServerName --resource-group $resourceGroup | ConvertFrom-Json
    $currentUser = az ad signed-in-user show | ConvertFrom-Json
    
    $isAdmin = $admins | Where-Object { $_.sid -eq $currentUser.id }
    if (-not $isAdmin) {
        Write-Host "Warning: You may not be an Azure AD admin on this SQL server." -ForegroundColor Yellow
        Write-Host "Current admins:" -ForegroundColor Yellow
        $admins | ForEach-Object { Write-Host "  - $($_.login)" }
        Write-Host ""
    }
} catch {
    Write-Host "Could not verify admin status. Proceeding anyway..." -ForegroundColor Yellow
}

# Create SQL script
$sqlScript = @"
-- Create user for managed identity
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$identityName')
BEGIN
    CREATE USER [$identityName] FROM EXTERNAL PROVIDER;
    ALTER ROLE db_datareader ADD MEMBER [$identityName];
    ALTER ROLE db_datawriter ADD MEMBER [$identityName];
    PRINT 'User created and roles assigned successfully!';
END
ELSE
BEGIN
    PRINT 'User [$identityName] already exists.';
    -- Ensure roles are assigned
    IF NOT IS_ROLEMEMBER('db_datareader', '$identityName') = 1
        ALTER ROLE db_datareader ADD MEMBER [$identityName];
    IF NOT IS_ROLEMEMBER('db_datawriter', '$identityName') = 1
        ALTER ROLE db_datawriter ADD MEMBER [$identityName];
    PRINT 'Roles verified.';
END
"@

Write-Host "Attempting to create SQL user..." -ForegroundColor Yellow
Write-Host ""

# Try method 1: sqlcmd with Azure AD auth
$sqlcmdAvailable = Get-Command sqlcmd -ErrorAction SilentlyContinue
if ($sqlcmdAvailable) {
    Write-Host "Trying sqlcmd..." -ForegroundColor Gray
    $tempFile = [System.IO.Path]::GetTempFileName()
    $sqlScript | Set-Content $tempFile
    
    $result = sqlcmd -S $sqlServer -d $database -G -C -i $tempFile 2>&1
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✓ SUCCESS!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "SQL user created and permissions granted." -ForegroundColor Green
        Write-Host ""
        Write-Host "You can now test your application:" -ForegroundColor Cyan
        Write-Host "  kubectl get service helloworld-service -n helloworld" -ForegroundColor White
        Write-Host ""
        exit 0
    } else {
        Write-Host "sqlcmd failed. Trying alternative method..." -ForegroundColor Yellow
    }
}

# Try method 2: Invoke-Sqlcmd (Azure Data Studio / SSMS module)
try {
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "Trying Invoke-Sqlcmd..." -ForegroundColor Gray
    
    $token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
    Invoke-Sqlcmd -ServerInstance $sqlServer -Database $database -AccessToken $token -Query $sqlScript
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ SUCCESS!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "SQL user created and permissions granted." -ForegroundColor Green
    Write-Host ""
    exit 0
} catch {
    Write-Host "Invoke-Sqlcmd not available or failed." -ForegroundColor Yellow
}

# Manual instructions
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "MANUAL SETUP REQUIRED" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Could not execute SQL automatically. Please run the following SQL manually:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Option 1: Azure Portal Query Editor" -ForegroundColor Cyan
Write-Host "  1. Go to: https://portal.azure.com" -ForegroundColor White
Write-Host "  2. Navigate to SQL Database: $database" -ForegroundColor White
Write-Host "  3. Click 'Query editor' in the left menu" -ForegroundColor White
Write-Host "  4. Sign in with Azure AD" -ForegroundColor White
Write-Host "  5. Run the SQL below" -ForegroundColor White
Write-Host ""
Write-Host "Option 2: Azure Data Studio or SSMS" -ForegroundColor Cyan
Write-Host "  1. Connect to: $sqlServer" -ForegroundColor White
Write-Host "  2. Database: $database" -ForegroundColor White
Write-Host "  3. Auth: Azure Active Directory - Universal with MFA" -ForegroundColor White
Write-Host "  4. Run the SQL below" -ForegroundColor White
Write-Host ""
Write-Host "SQL to execute:" -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host $sqlScript -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host ""
Write-Host "After running the SQL, test your application:" -ForegroundColor Yellow
Write-Host "  kubectl get service helloworld-service -n helloworld" -ForegroundColor White
Write-Host ""
