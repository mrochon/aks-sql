// Federated Identity Credential module
// This needs to be at resource group scope

@description('The name of the user-assigned managed identity.')
param identityName string

@description('The OIDC issuer URL from the AKS cluster.')
param oidcIssuerUrl string

@description('The Kubernetes namespace.')
param kubernetesNamespace string

@description('The Kubernetes service account name.')
param kubernetesServiceAccountName string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: identityName
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'kubernetes-federated-credential'
  parent: identity
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${kubernetesNamespace}:${kubernetesServiceAccountName}'
  }
}

output federatedCredentialName string = federatedCredential.name
