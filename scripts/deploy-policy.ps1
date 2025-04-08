$ApplicationId = "${{ secrets.AZURE_CLIENT_ID }}"
$SecuredPassword = "${{ secrets.AZURE_CLIENT_SECRET }}"
$tenantID = "${{ secrets.AZURE_TENANT_ID }}"

$SecuredPasswordPassword = ConvertTo-SecureString `
-String $SecuredPassword -AsPlainText -Force

$ClientSecretCredential = New-Object `
-TypeName System.Management.Automation.PSCredential `
-ArgumentList $ApplicationId, $SecuredPasswordPassword
Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential
# Execute the deployment script

# Get policy definition from repository
$policyDefinition = Get-Content -Path "./policies/policy.ps1"

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