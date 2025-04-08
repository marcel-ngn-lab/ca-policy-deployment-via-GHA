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
$policyPath = "./policies/policy.json"
$policyContent = Get-Content -Path $policyPath -Raw
$policyDefinition = $policyContent | ConvertFrom-Json

# Extract the displayName for comparison
$policyDisplayName = $policyDefinition.displayName

# Check if policy already exists
$existingPolicy = Get-MgIdentityConditionalAccessPolicy | Where-Object {$_.DisplayName -eq $policyDisplayName}

# Convert the JSON string directly to a hashtable for the BodyParameter
$policyHashtable = @{}
$policyDefinition.PSObject.Properties | ForEach-Object {
    $policyHashtable[$_.Name] = $_.Value
}

if ($existingPolicy) {
    # Update existing policy
    Write-Output "Found existing policy with ID: $($existingPolicy.Id)"
    Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -BodyParameter $policyHashtable
    Write-Output "Updated existing policy: $policyDisplayName"
} else {
    # Create new policy
    Write-Output "No existing policy found. Creating new policy: $policyDisplayName"
    New-MgIdentityConditionalAccessPolicy -BodyParameter $policyHashtable
    Write-Output "Created new policy: $policyDisplayName"
}



