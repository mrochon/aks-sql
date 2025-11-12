# Deployment validation and preview script
# Run this before 'azd up' to validate the infrastructure

Write-Host "===================================" -ForegroundColor Cyan
Write-Host "AKS + SQL Deployment Validator" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$prereqPassed = $true

# Check azd
if (Get-Command azd -ErrorAction SilentlyContinue) {
    $azdVersion = azd version
    Write-Host "✓ Azure Developer CLI: $azdVersion" -ForegroundColor Green
} else {
    Write-Host "✗ Azure Developer CLI not found" -ForegroundColor Red
    Write-Host "  Install from: https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd" -ForegroundColor Yellow
    $prereqPassed = $false
}

# Check az CLI
if (Get-Command az -ErrorAction SilentlyContinue) {
    $azVersion = az version --query '\"azure-cli\"' -o tsv
    Write-Host "✓ Azure CLI: $azVersion" -ForegroundColor Green
} else {
    Write-Host "✗ Azure CLI not found" -ForegroundColor Red
    Write-Host "  Install from: https://learn.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Yellow
    $prereqPassed = $false
}

# Check Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    try {
        $dockerVersion = docker --version
        Write-Host "✓ Docker: $dockerVersion" -ForegroundColor Green
    } catch {
        Write-Host "✗ Docker not running" -ForegroundColor Red
        Write-Host "  Start Docker Desktop or Docker daemon" -ForegroundColor Yellow
        $prereqPassed = $false
    }
} else {
    Write-Host "✗ Docker not found" -ForegroundColor Red
    Write-Host "  Install from: https://docs.docker.com/get-docker/" -ForegroundColor Yellow
    $prereqPassed = $false
}

# Check kubectl
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    $kubectlVersion = kubectl version --client --short 2>$null
    Write-Host "✓ kubectl: $kubectlVersion" -ForegroundColor Green
} else {
    Write-Host "✗ kubectl not found" -ForegroundColor Red
    Write-Host "  Install from: https://kubernetes.io/docs/tasks/tools/" -ForegroundColor Yellow
    $prereqPassed = $false
}

Write-Host ""

if (-not $prereqPassed) {
    Write-Host "Please install missing prerequisites before continuing." -ForegroundColor Red
    exit 1
}

# Check Azure login
Write-Host "Checking Azure authentication..." -ForegroundColor Yellow

try {
    $account = az account show 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Host "✓ Logged in to Azure as: $($account.user.name)" -ForegroundColor Green
        Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Gray
    } else {
        Write-Host "✗ Not logged in to Azure" -ForegroundColor Red
        Write-Host "  Run: az login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "✗ Not logged in to Azure" -ForegroundColor Red
    Write-Host "  Run: az login" -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Check if environment is initialized
Write-Host "Checking azd environment..." -ForegroundColor Yellow

try {
    $envName = azd env list --output json 2>$null | ConvertFrom-Json | Select-Object -First 1 -ExpandProperty Name
    if ($envName) {
        Write-Host "✓ Environment: $envName" -ForegroundColor Green
        
        # Show current configuration
        $envVars = azd env get-values
        if ($envVars -match "AZURE_LOCATION=(.+)") {
            Write-Host "  Location: $($matches[1])" -ForegroundColor Gray
        }
    } else {
        Write-Host "⚠ No environment configured" -ForegroundColor Yellow
        Write-Host "  Run: azd env new <environment-name>" -ForegroundColor Yellow
        Write-Host "  Then: azd env set AZURE_LOCATION <location>" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ No environment configured" -ForegroundColor Yellow
    Write-Host "  Run: azd env new <environment-name>" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "Ready to deploy!" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. (Optional) Set SQL admin:"
Write-Host "     azd env set SQL_ADMIN_OBJECT_ID <your-object-id>"
Write-Host ""
Write-Host "  2. Preview deployment:"
Write-Host "     azd provision --preview"
Write-Host ""
Write-Host "  3. Deploy everything:"
Write-Host "     azd up"
Write-Host ""
