function Get-Assertion{
    <#
        Author               = "Jos Lieben (jos@lieben.nu)"
        CompanyName          = "Lieben Consultancy"
        Copyright            = "https://www.lieben.nu/liebensraum/commercial-use/"
    #>        
    Param()
    #check if there is a cert in the cert store with the target tenant ID:
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.Subject -eq "CN=$($global:octo.userConfig.LCTenantId)"}
    
    if(!$cert){
        Throw "No certificate found for tenant $($global:octo.userConfig.LCTenantId) in the current user store. Please ensure the certificate is installed in the current user store by importing the PFX generated with new-SpnAuthCert."
    }    

    $clientAssertion = @{
        Header        = @{
            alg = "RS256"
            typ = "JWT"
            x5t = [System.Convert]::ToBase64String(($cert.GetCertHash()))
        }
        ClaimsPayload = @{
            aud = "$($global:octo.idpUrl)/$($global:octo.userConfig.LCTenantId)/oauth2/token"
            exp = [math]::Round(((New-TimeSpan -Start ((Get-Date "1970-01-01T00:00:00Z" ).ToUniversalTime()) -End (Get-Date).ToUniversalTime().AddMinutes(2)).TotalSeconds), 0)
            iss = $($global:octo.userConfig.LCClientId)
            jti = (New-Guid).Guid
            nbf = [math]::Round(((New-TimeSpan -Start ((Get-Date "1970-01-01T00:00:00Z" ).ToUniversalTime()) -End ((Get-Date).ToUniversalTime())).TotalSeconds), 0)
            sub = $($global:octo.userConfig.LCClientId)
        }
    }
    $clientAssertion['Base64Header'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($clientAssertion.Header | ConvertTo-Json -Compress))).Split('=')[0].Replace('+', '-').Replace('/', '_')
    $clientAssertion['Base64ClaimsPayload'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($clientAssertion.ClaimsPayload | ConvertTo-Json -Compress))).Split('=')[0].Replace('+', '-').Replace('/', '_')

    $clientAssertion['Signature'] = [Convert]::ToBase64String(
        $cert.PrivateKey.SignData(
            [System.Text.Encoding]::UTF8.GetBytes("$($clientAssertion.Base64Header).$($clientAssertion.Base64ClaimsPayload)"),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    ).Replace('+', '-').Replace('/', '_').Replace('=', '')

    return "$($clientAssertion.Base64Header).$($clientAssertion.Base64ClaimsPayload).$($clientAssertion.Signature)"
}
