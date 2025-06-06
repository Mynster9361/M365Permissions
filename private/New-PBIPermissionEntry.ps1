Function New-PBIPermissionEntry{
    <#
        Author               = "Jos Lieben (jos@lieben.nu)"
        CompanyName          = "Lieben Consultancy"
        Copyright            = "https://www.lieben.nu/liebensraum/commercial-use/"
    #>    
    Param(
        [Parameter(Mandatory=$true)]$targetPath,
        [Parameter(Mandatory=$true)]$targetType,
        [Parameter(Mandatory=$true)]$targetId,
        [Parameter(Mandatory=$true)]$principalEntraId,
        [Parameter(Mandatory=$false)]$principalEntraUpn,
        [Parameter(Mandatory=$false)]$principalSysId,
        [Parameter(Mandatory=$false)]$principalSysName,
        [Parameter(Mandatory=$true)]$principalType,
        [Parameter(Mandatory=$true)]$principalRole,
        [Parameter(Mandatory=$false)]$through="Direct",
        [Parameter(Mandatory=$false)]$parentId = "",
        [Parameter(Mandatory=$false)]$startDateTime,
        [Parameter(Mandatory=$false)]$endDateTime,
        [Parameter(Mandatory=$false)]$createdDateTime,
        [Parameter(Mandatory=$false)]$modifiedDateTime
    )

    if($global:octo.currentUser.userPrincipalName -eq $principalEntraUpn -and !$global:octo.userConfig.includeCurrentUser){
        Write-LogMessage -level 5 -message "Skipping permission $($principalRole) scoped at $targetPath for $($principalEntraId) as it is the auditor account"
        return $Null
    }

    $principalType = $principalType.Replace("User (Member)","Internal User").Replace("User (Guest)","External User")

    Write-LogMessage -level 5 -message "Adding permission $($principalRole) scoped at $targetPath for $($principalEntraId)"
    if(!$global:PBIPermissions.$targetPath){
        $global:PBIPermissions.$targetPath = @()
    }
    
    $global:PBIPermissions.$targetPath += [PSCustomObject]@{
        targetPath = $targetPath
        targetType = $targetType
        targetId = $targetId
        principalEntraId = $principalEntraId
        principalSysId = $principalSysId
        principalSysName = $principalSysName
        principalType = $principalType   
        principalRole = $principalRole  
        through = $through
        parentId = $parentId
        startDateTime = $startDateTime
        endDateTime = $endDateTime
        createdDateTime = $createdDateTime
        modifiedDateTime = $modifiedDateTime
    }
}