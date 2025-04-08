#base script: https://www.alitajran.com/import-conditional-access-policies/


# Connect to Microsoft Graph
$ApplicationId = $env:AZURE_CLIENT_ID
$SecuredPassword = $env:AZURE_CLIENT_SECRET
$tenantID = $env:AZURE_TENANT_ID

# Create secure credential
$SecuredPasswordPassword = ConvertTo-SecureString -String $SecuredPassword -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecuredPasswordPassword

# Connect to Microsoft Graph
Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential | Out-Null

# Define the path to the directory containing your JSON files
$jsonFilesDirectory = "./policies/"

# Get all JSON files in the directory
$jsonFiles = Get-ChildItem -Path $jsonFilesDirectory -Filter *.json

# Check if there are no JSON files
if ($jsonFiles.Count -eq 0) {
    Write-Host "No JSON files found in the directory to import." -ForegroundColor Yellow
}
else {
    # Get existing policies once to avoid multiple API calls
    Write-Host "Retrieving existing policies..." -ForegroundColor Cyan
    $existingPolicies = Get-MgIdentityConditionalAccessPolicy
    
    # Loop through each JSON file
    foreach ($jsonFile in $jsonFiles) {
        try {
            # Read the content of the JSON file and convert it to a PowerShell object
            $policyJson = Get-Content -Path $jsonFile.FullName | ConvertFrom-Json

            # Create a custom object
            $policyObject = [PSCustomObject]@{
                displayName     = $policyJson.displayName
                conditions      = $policyJson.conditions
                grantControls   = $policyJson.grantControls
                sessionControls = $policyJson.sessionControls
                state           = $policyJson.state
            }

            # Convert the custom object to JSON with a depth of 10
            $policyJsonString = $policyObject | ConvertTo-Json -Depth 10

            # Check if a policy with the same display name already exists
            $existingPolicy = $existingPolicies | Where-Object { $_.DisplayName -eq $policyJson.displayName }

            if ($existingPolicy) {
                # Update the existing policy
                Write-Host "Policy already exists: $($policyJson.displayName) - Updating..." -ForegroundColor Yellow
                $null = Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $existingPolicy.Id -Body $policyJsonString
                Write-Host "Policy updated successfully: $($policyJson.displayName)" -ForegroundColor Green
            } else {
                # Create a new policy
                Write-Host "Creating new policy: $($policyJson.displayName)" -ForegroundColor Cyan
                $null = New-MgIdentityConditionalAccessPolicy -Body $policyJsonString
                Write-Host "Policy created successfully: $($policyJson.displayName)" -ForegroundColor Green
            }
        }
        catch {
            # Print an error message if an exception occurs
            Write-Host "An error occurred while processing the policy '$($policyJson.displayName)': $_" -ForegroundColor Red
        }
    }
}