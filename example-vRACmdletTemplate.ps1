function example-vRACmdletTemplate
{
<#
.SYNOPSIS
  A template from which can create vRA 7.x cmdlets
.DESCRIPTION
  
.EXAMPLE
  Get-vRACmdletTemplate -Server vra74.corp.local -Credential $credential

.NOTES
  vRA Version: 7.4
  Author: Clint Fritz
#>
[CmdletBinding(DefaultParameterSetName='Default')]
[Alias()]
#[OutputType([int])]
param(
    #Server to connect to
    [Parameter(ParameterSetName='Default',
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
    [Alias('CN','__SERVER',"ComputerName","IPAddress","Hostname","FQDN")]
    [string]$Server,

    #Credentials to use to connect to server
    [Parameter(Mandatory=$false)]
    [Management.Automation.PSCredential]
    $Credential,

    [Parameter]
    [string]
    $tenant="vsphere.local"


)

Begin {
    Write-Verbose "[INFO] ParameterSet: $($PSCmdlet.ParameterSetName)"

    #Check if credentials passed
    if ($Credential) {
        Write-Verbose "[INFO] Credentials passed"

        $Username = $credential.username
        $Password = $credential.getnetworkcredential().Password

        $body = @{
            username = $Username
            password = $Password
            tenant = $tenant
        } | ConvertTo-Json

        #this fails on systems where Powershell is locked down. preventing even .net things from working :(
        try {
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        } catch {
            Write-Warning "You organisation has broken stuff!"
            Write-Output "Exception: $($_.Exception)"
            throw
        }
        $headers.Add("Accept", 'application/json')
        $headers.Add("Content-Type", 'application/json')

        $method = "POST"
        $baseUrl = "https://$($Server)"
        $uri = "$($baseUrl)/identity/api/tokens"

        #Request a token from vRA
        try
        {
            $response = $null
            $response = Invoke-RestMethod -Method $method -Uri $uri -Headers $headers -Body $body
        }
        catch 
        {
            Write-Output "StatusCode:" $_.Exception.Response.StatusCode.value__
            throw
        }

        #Add the retrieved Bearer token to the headers
        $bearer_token = $response.id
        $headers.Add("Authorization", "Bearer $($bearer_token)")

    } else {
        Write-Verbose "[INFO] No credential"

        #check if there is a vRA connection via Power-vRA
        #TODO: This does not work if the token has expired. vRAConnection does not contain the expiry, so how to determine if it is expired?
        if ($vRAConnection) {
            Write-Verbose "[INFO] Found a Power-vRA connection, using this."

            #create a header variable from the vraConnection
            $baseUrl = $vRAConnection.Server

            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Accept", 'application/json')
            $headers.Add("Content-Type", 'application/json')
            $headers.Add("Authorization", "Bearer $($vRAConnection.Token)")
        } else {
            Write-Error "No vRA Connection found. Please either enter Credentials or connect using PowervRA and try again."
            Return
        }
    }

}

Process {
        Write-Verbose "[INFO] Computer Name: $($Server)"


        #create url.
        #$uri = "$($baseUrl)/catalog-service/api/catalogItems?page=1&limit=20&`$filter=substringof('SOE - ',name)"
        $Id = "6d816b72-2767-4650-b64a-541c3a3ca0bf"
        $uri = "$($baseUrl)/catalog-service/api/consumer/entitledCatalogItems/$($Id)/requests/template"

        Write-Verbose "[INFO] uri: $($uri)"
        $escapedURI = [uri]::EscapeUriString($uri)
        Write-Verbose "[INFO] Escaped URI: $($escapedURI)"

        $method = "GET"
        $Params = @{

            Method = $method
            Headers = $headers
            Uri = $escapedURI
        }

        try{
            $result = Invoke-RestMethod @Params
        } catch {
            throw
        }

        #catalogItems
        #Return $result.content
        #request/templates
        Return $result
}


End {
    Write-Verbose "[INFO] End"
}

}
