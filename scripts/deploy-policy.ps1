# Get credentials from environment variables
$ApplicationId = $env:AZURE_CLIENT_ID
$SecuredPassword = $env:AZURE_CLIENT_SECRET
$tenantID = $env:AZURE_TENANT_ID

# Create secure credential
$SecuredPasswordPassword = ConvertTo-SecureString -String $SecuredPassword -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPasswordPassword

# Connect to Microsoft Graph
Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential

# Get policy definition from repository
# This should be a JSON file, not a PS1 file
$policyPath = "./policies/policy.json"
$policyContent = Get-Content -Path $policyPath -Raw
$policyDefinition = $policyContent | ConvertFrom-Json

# Check if policy already exists
$existingPolicy = Get-MgIdentityConditionalAccessPolicy | Where-Object {$_.DisplayName -eq $policyDefinition.displayName}

if ($existingPolicy) {
    # Update existing policy
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $policyDefinition
    Write-Output "Updated existing policy: $($policyDefinition.displayName)"
} else {
    # Create new policy
    New-MgIdentityConditionalAccessPolicy -BodyParameter $policyDefinition
    Write-Output "Created new policy: $($policyDefinition.displayName)"
}