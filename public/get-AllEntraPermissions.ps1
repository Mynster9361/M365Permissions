﻿Function get-AllEntraPermissions {
    <#
        Author               = "Jos Lieben (jos@lieben.nu)"
        CompanyName          = "Lieben Consultancy"
        Copyright            = "https://www.lieben.nu/liebensraum/commercial-use/"
        
        Parameters:
    #>        
    Param(
        [Switch]$skipReportGeneration,

        [parameter(Mandatory=$false,DontShow=$true
        )]
        [bool]$testMode = $false
    )

    Write-LogMessage -message "Starting Entra scan..." -level 4

    New-StatisticsObject -category "GroupsAndMembers" -subject "Entities"
    Write-Progress -Id 1 -PercentComplete 0 -Activity "Scanning Entra ID" -Status "Getting users and groups" 

    # Get user count with proper error handling
    try {
        $userCount = (New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/users/`$count" -Method GET -ComplexFilter -nopagination)
        Write-LogMessage -message "Retrieving metadata for $userCount users..." -level 4
    }
    catch {
        Write-LogMessage -message "Failed to retrieve user count: $_" -level 2
        $userCount = 0
    }
    
    Write-Progress -Id 1 -PercentComplete 1 -Activity "Scanning Entra ID" -Status "Getting users and groups" 

    # Get users with proper error handling
    try {
        $allUsers = New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/users?`$select=id,userPrincipalName,displayName" -Method GET
        Write-LogMessage -message "Got metadata for $($allUsers.Count) users" -level 4
        
        # Verify we have users
        if ($null -eq $allUsers -or $allUsers.Count -eq 0) {
            Write-LogMessage -message "No users retrieved from Graph API" -level 2
            $allUsers = @()
        }
    }
    catch {
        Write-LogMessage -message "Failed to retrieve users: $_" -level 2
        $allUsers = @()
    }

    if ($testMode) {
        # For testing, we can limit the number of users processed
        $allUsers = $allUsers[0..999]
        $userCount = $allUsers.Count
        Write-LogMessage -message "Test mode enabled, processing only first 1000 users" -level 5
    }

    $activity = "Entra ID users"
    $jobsCreated = 0
    Write-Progress -Id 1 -PercentComplete 2 -Activity "Scanning Entra ID" -Status "Creating scan jobs for users"
    
    # Create scan jobs in batches of 100 users
    for ($i = 0; $i -lt $allUsers.Count; $i += 100) {
        $endIndex = [math]::Min($i + 99, $allUsers.Count - 1)
        $userBatch = $allUsers[$i..$endIndex]
        
        # Validate batch before creating job
        if ($null -eq $userBatch -or $userBatch.Count -eq 0) {
            Write-LogMessage -message "Empty user batch for range $i to $endIndex, skipping" -level 2
            continue
        }
    
        # Add memory optimization - after processing each 1000 users otherwise memory usage can grow significantly
        # This is especially important for large tenants with many users
        if ($i % 1000 -eq 0 -and $i -gt 0) {
            [System.GC]::Collect()
            Write-LogMessage -message "Forced garbage collection after processing $i users" -level 4
        }
    
        # Log batch size for debugging
        Write-LogMessage -message "Creating scan job for users $i to $endIndex (Users: $($userBatch.Count))" -level 4
        
        # Debug output the first few users to verify data
        $idSample = $userBatch | Select-Object -First 3 | ForEach-Object { "$($_.id)" } | Join-String -Separator ", "
        Write-LogMessage -level 4 -message "Processing users from $i to $endIndex with IDs: $idSample"
        New-ScanJob -Title $activity -Target "users_$($i)_$($endIndex)" -FunctionToRun "get-EntraUsersAndGroupsBatch" -FunctionArguments @{
            # Convert complex user objects to simple hashtables that can serialize properly
            # Only include users with valid properties
            "entraUsers" = ($userBatch | ForEach-Object {
                    @{
                        id                = $_.id
                        userPrincipalName = $_.userPrincipalName
                        displayName       = $_.displayName
                    }
                })
            "isTopLevel" = $true
        }
        $jobsCreated++
    }
    
    Write-LogMessage -message "Created $jobsCreated scan jobs for processing users" -level 4
    
    # Update statistics before starting jobs
    Update-StatisticsObject -category "GroupsAndMembers" -subject "Entities" -Amount $allUsers.Count
    Stop-StatisticsObject -category "GroupsAndMembers" -subject "Entities"
    
    if ($jobsCreated -gt 0) {
        Start-ScanJobs -Title $activity
    }
    else {
        Write-LogMessage -message "No scan jobs were created - skipping job execution" -level 2
    }
    # Cleanup before continuing to role scanning
    Remove-Variable -name allUsers -Force -Confirm:$False
    [System.GC]::GetTotalMemory($true) | out-null
    
    $global:EntraPermissions = @{}
    New-StatisticsObject -category "Entra" -subject "Roles"

    $partners = New-GraphQuery -Uri "$($global:octo.graphUrl)/beta/directory/partners" -Method GET
    foreach ($partner in $partners) {
        Update-StatisticsObject -category "Entra" -subject "Roles"
        $permissionSplat = @{
            targetPath        = "/"
            targetType        = "tenant"
            principalEntraId  = $partner.partnerTenantId
            principalEntraUpn = $partner.companyName
            principalSysName  = $partner.supportUrl
            principalType     = $partner.companyType
            principalRole     = $partner.contractType
            through           = "Direct"
            tenure            = "Permanent"                    
        }            
        New-EntraPermissionEntry @permissionSplat
    }

    Write-Progress -Id 1 -PercentComplete 5 -Activity "Scanning Entra ID" -Status "Retrieving role definitions"

    #get role definitions
    $roleDefinitions = New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/directoryRoleTemplates" -Method GET
    
    Write-Progress -Id 1 -PercentComplete 35 -Activity "Scanning Entra ID" -Status "Retrieving flexible (PIM) assigments"

    #get eligible role assignments
    try {
        $roleEligibilities = (New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/roleManagement/directory/roleEligibilityScheduleInstances" -Method GET -NoRetry | Where-Object { $_ })
        $roleActivations = (New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=assignmentType eq 'Activated'" -Method GET)
    }
    catch {
        Write-LogMessage -level 2 -message "Failed to retrieve flexible assignments, this is fine if you don't use PIM and/or don't have P2 licensing."
        $roleEligibilities = @()
    }

    Write-Progress -Id 1 -PercentComplete 45 -Activity "Scanning Entra ID" -Status "Processing flexible (PIM) assignments"
    
    $count = 0
    # Process all role eligibilities using the new batch functionality
    $batchSplat = @{
        useBatchApi = $true
        batchItems = $roleEligibilities
        batchSize = 20
        batchActivity = "Processing flexible (PIM) assignments"
        batchUrlGenerator = {
            param($item)
            return "/directoryObjects/$($item.principalId)"
        }
        batchIdGenerator = {
            param($index)
            return "principal_$index"
        }
        progressId = 2
    }
    $batchResults = new-GraphBatchQuery @batchSplat
    Write-LogMessage -message "Processing flexible (PIM) assignments in batches of 20" -level 4
    
    # Process the batch results
    foreach ($batchResponse in $batchResults) {
        foreach ($response in $batchResponse.responses) {
            $count++
            
            # Extract index from response ID
            $index = [int]($response.id -replace 'principal_', '')
            
            # Find corresponding eligibility in the current batch
            $batchStartIndex = $batchResults.IndexOf($batchResponse) * 20
            $roleEligibility = $roleEligibilities[$batchStartIndex + $index]
            
            # Find role definition
            $roleDefinition = $roleDefinitions | Where-Object { $_.id -eq $roleEligibility.roleDefinitionId }
            
            # Check if principal was found
            if ($response.status -ne 200) {
                Write-LogMessage -level 2 -message "Failed to resolve principal $($roleEligibility.principalId) to a directory object, was it deleted?"
                continue
            }
            
            $principal = $response.body
            
            Update-StatisticsObject -category "Entra" -subject "Roles"
            $permissionSplat = @{
                targetPath        = if ($null -eq $roleEligibility.directoryScopeId) { "/" } else { $roleEligibility.directoryScopeId.ToString() }
                principalEntraId  = $principal.id
                principalEntraUpn = $principal.userPrincipalName
                principalSysName  = $principal.displayName
                principalType     = $principal."@odata.type"
                principalRole     = $roleDefinition.displayName
                tenure            = "Eligible"    
                startDateTime     = $roleEligibility.startDateTime
                endDateTime       = $roleEligibility.endDateTime                 
            }            
            New-EntraPermissionEntry @permissionSplat
        }
    }
    
    Write-Progress -Id 2 -Completed -Activity "Processing flexible (PIM) assignments"


    Write-Progress -Id 1 -PercentComplete 10 -Activity "Scanning Entra ID" -Status "Retrieving fixed assigments"

    #get fixed assignments
    $roleAssignments = New-GraphQuery -Uri "$($global:octo.graphUrl)/beta/roleManagement/directory/roleAssignments?`$expand=principal" -Method GET

    Write-Progress -Id 1 -PercentComplete 20 -Activity "Scanning Entra ID" -Status "Processing fixed assigments"

    foreach ($roleAssignment in $roleAssignments) {
        if ($roleActivations -and $roleActivations.roleAssignmentOriginId -contains $roleAssignment.id) {
            Write-LogMessage -level 5 -message "Ignoring $($roleAssignment.id) because it is Eligible as well"
            continue
        }        
        $roleDefinition = $roleDefinitions | Where-Object { $_.id -eq $roleAssignment.roleDefinitionId }
        Update-StatisticsObject -category "Entra" -subject "Roles"
        $permissionSplat = @{
            targetPath        = $roleAssignment.directoryScopeId
            principalEntraId  = $roleAssignment.principal.id
            principalEntraUpn = $roleAssignment.principal.userPrincipalName
            principalSysName  = $roleAssignment.principal.displayName
            principalType     = $roleAssignment.principal."@odata.type"
            principalRole     = $roleDefinition.displayName
            tenure            = "Permanent"                    
        }            
        New-EntraPermissionEntry @permissionSplat
    }

    Remove-Variable roleDefinitions -Force -Confirm:$False
    Remove-Variable roleAssignments -Force -Confirm:$False
    Remove-Variable roleEligibilities -Force -Confirm:$False

    Write-Progress -Id 1 -PercentComplete 50 -Activity "Scanning Entra ID" -Status "Getting Service Principals"
    $servicePrincipals = New-GraphQuery -Uri "$($global:octo.graphUrl)/v1.0/servicePrincipals?`$expand=appRoleAssignments" -Method GET
    
    foreach ($servicePrincipal in $servicePrincipals) {
        Update-StatisticsObject -category "Entra" -subject "Roles"
        #skip disabled SPN's
        if ($servicePrincipal.accountEnabled -eq $false -or $servicePrincipal.appRoleAssignments.Count -eq 0) {
            continue
        }
        foreach ($appRole in @($servicePrincipal.appRoleAssignments)) {
            #skip disabled roles
            if ($appRole.deletedDateTime) {
                continue
            }

            $appRoleMeta = $Null; $appRoleMeta = @($servicePrincipals.appRoles | Where-Object { $_.id -eq $appRole.appRoleId })[0]
            if ($False -eq $appRoleMeta.isEnabled) {
                continue
            }

            $permissionSplat = @{
                targetPath       = "/$($appRole.resourceDisplayName)"
                targetType       = "API"
                targetId         = $appRole.resourceId
                principalEntraId = $servicePrincipal.id
                principalSysName = $servicePrincipal.displayName
                principalType    = $servicePrincipal.servicePrincipalType
                principalRole    = $appRoleMeta.value
                tenure           = "Permanent"             
            }   
            New-EntraPermissionEntry @permissionSplat
        }
    }

    Remove-Variable servicePrincipals -Force -Confirm:$False

    Stop-statisticsObject -category "Entra" -subject "Roles"
    
    $permissionRows = foreach ($row in $global:EntraPermissions.Keys) {
        foreach ($permission in $global:EntraPermissions.$row) {
            [PSCustomObject]@{
                "targetPath"       = $row
                "targetType"       = $permission.targetType
                "targetId"         = $permission.targetId
                "principalEntraId" = $permission.principalEntraId
                "principalSysId"   = $permission.principalSysId
                "principalSysName" = $permission.principalSysName
                "principalType"    = $permission.principalType
                "principalRole"    = $permission.principalRole
                "through"          = $permission.through
                "parentId"         = $permission.parentId
                "accessType"       = $permission.accessType
                "tenure"           = $permission.tenure
                "startDateTime"    = $permission.startDateTime
                "endDateTime"      = $permission.endDateTime
                "createdDateTime"  = $permission.createdDateTime
                "modifiedDateTime" = $permission.modifiedDateTime
            }
        }
    }

    Add-ToReportQueue -permissions $permissionRows -category "Entra"
    Remove-Variable -Name EntraPermissions -Scope Global -Force -Confirm:$False
    if (!$skipReportGeneration) {
        Write-LogMessage -message "Generating report..." -level 4
        Write-Report
    }
    else {
        Reset-ReportQueue
    }

    Write-Progress -Id 1 -Completed -Activity "Scanning Entra ID"
}