function get-SpOInvitee{
    <#
        Author               = "Jos Lieben (jos@lieben.nu)"
        CompanyName          = "Lieben Consultancy"
        Copyright            = "https://www.lieben.nu/liebensraum/commercial-use/"
    #>        
    Param(
        [Parameter(Mandatory=$true)]$invitee,
        [Parameter(Mandatory=$true)]$siteUrl
    )

    $retVal = @{}

    #type 1 = internal user
    #type 2 = group -> still used at all? enumerate in later version if reproducible
    #type 3 = external user
    if($invitee.Type -in @(1,2)){
        try{
            $usr = $Null;$usr = New-GraphQuery -maxAttempts 10 -Uri "$siteUrl/_api/Web/GetUserById($($invitee.PId))" -Method GET -resource "https://www.$($global:octo.sharepointUrl)"
        }catch{
            $usr = $Null
        }
        if($usr){
            return $usr
        }else{
            $retVal.Title = "Unknown (deleted?) PID: $($invitee.PId)"
            $retVal.LoginName = "Unknown (deleted?)"
            $retVal.Email = "Unknown (deleted?)"
            $retVal.PrincipalType = "Internal User"
            $retVal.ObjType = "Invitee"
        }
    }else{
        $retVal.Title = $invitee.Email.Split("@")[0]
        $retVal.Email = $invitee.Email
        $retVal.LoginName = $invitee.Email
        $retVal.PrincipalType = "External User" 
        $retVal.created = $invitee.InvitedOn
        $retVal.ObjType = "Invitee"
    }

    return $retVal
}