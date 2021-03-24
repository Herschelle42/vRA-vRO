function Invoke-vRADbQuery {
<#
.SYNOPSIS
  Get vRA DB Query from the PostGres DB. Limited to SELECT only.
.EXAMPLE
$myQuery = "select id,name,status,request_id from cat_resource where name='testVM01';"
Get-vRADbQuery -Query $myQuery -ComputerName vra1.corp.local -Credential $cred_vra1_root -Verbose

id                                   name     status request_id                          
--                                   ----     ------ ----------                          
f8bfdbc3-97c0-4b81-9cf6-d26f5ca822cd testVM01 ACTIVE c430aaa1-f561-4afe-96e2-a9267a99f9f8

.NOTES
  Author: Clint Fritz
  vRA Version: 7.4 HF12

#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string]$Query,

    [Parameter(Mandatory)]
    [Alias("Server","IPAddress","FQDN","Name")]
    [string]$ComputerName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory=$false)]
    [string]$plinkEXEPath = "C:\Program Files\Putty\plink.exe"
)

Begin {

    Write-Verbose "[INFO] Query: $($Query)"

    if($Query -notmatch '^select') {
        throw "ERROR: Only SELECT statements are allowed."
    }

    #could support if grab the column names after check how many rows returned. If 1 or more rows returned
    #get the first line. check for the | 
    # Split on | and trim all white spaces to be the columns names and property names.
    #if none, check if there is only one word. this one word would be the only column.
    if($Query -match '^select \*') {
        throw "ERROR: SELECT * statements are not allowed at this time."
    }

    #check for carriage returns - on single line is supported.

    $tempCmdFile = [System.Io.Path]::GetTempFileName()
    $Username = $credential.username
    $Password = $credential.getnetworkcredential().Password

    if (-not (Test-Path -Path $plinkexepath -ErrorAction SilentlyContinue)) {
        throw "plink.exe not found at: $($plinkExePath)"
    }

    <# no longer required ?
    #if rows returned, then use the title row to capture where columns are name AS NAME
    [array]$columns = $query.tolower().Trim('^select').Substring(0,$Query.tolower().IndexOf(" from ")-6).split(",").Trim()
    Write-Verbose "[INFO] Columns: [$($columns -join ",")]"
    #>
}
Process {

$Command = @"
/opt/vmware/vpostgres/current/bin/psql -U postgres -d vcac -c "$($Query)"
"@


foreach ($item in $Command) {
    Write-Verbose "[INFO] Command: $($item)"
}
$command | Out-File -FilePath $tempCmdFile -Encoding ascii
$result = &($plinkExePath) -ssh $ComputerName -l $UserName -pw $Password -m $tempCmdFile
foreach ($item in $result) {
    Write-Verbose "[INFO] Result: $($item)"
}

#How many rows returned?
$rowCount = ($result | ? { $_ -match "\([0-9]* row[s]?\)" }) -replace "[^\d]"
if($rowCount -gt 0) {
    Write-Verbose "[INFO] Rows returned: $($rowCount)"

    #Collect the column names for the creation of a custom object
    [array]$columns = $result[0].Split("|").Trim()
    Write-Verbose "[INFO] Columns: [$($columns -join ",")]"

} else {
    Write-Verbose "No rows returned"
    Return
}

$params = @{
    Delimiter = '\|' 
    PropertyNames = $columns
}
Write-Verbose "[INFO] Params: $($params | Out-String)"


#Create a temporary object, excluding the the header row.
#TODO: work out why if only 1 column selected tempObject returns nothing.
[array]$tempObject = $result | ? { $_ -notmatch "\([0-9]* row[s]?\)" } | ConvertFrom-String @params | ? { $_.$($columns[0]).ToString().trim() -ne "$($columns[0])" }
Write-Verbose "[INFO] tempObject: $($tempObject | Out-String)"

#create a new object after trimming the values
$newObject = $tempObject.ForEach({
    $hash = [ordered]@{}
    $_.PSObject.Properties.ForEach({
        $hash.$($_.name) = "$($_.value)".trim()
    })
    $object = New-Object PSObject -Property $hash
    $object
})
$newObject

} 

End {
    if (Test-Path -Path $tempCmdFile -ErrorAction SilentlyContinue) {
        Remove-Item -Path $tempCmdFile -Force
    }
}

}
