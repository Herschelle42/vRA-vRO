function Get-vRARequestsByResourceName
{
<#
.Synopsis
   Get the most recent requests for a given vRA Resource Name
.DESCRIPTION
   Return a list of recent requests for a vRA Resource, such as a deployment or
   a machine name.
   I often get asked why has this changed? Who changed it? When did it get 
   changed. When there are thousands of requests per day it is very difficult 
   to find. 
   This will look up in the DB for the resource, including parents and descendants, 
   then find all the requests. Sort them by Request number and present this list 
   back.
   Unless I can do this by the API somehow, instead of the DB. That would be better.
   Get the resource id by searching for the name, and then getting the requests?
   No. doesn't work because of:  resourceRef/id eq 'c155813f-791c-4787-85bb-d11de689125d'
   there seems to be a another parameter that I :might" be able to use if vRA actually
   supports it, that is.  ?$expand=resourceRef/id&$filter=resourceRef/id eq 'c155813f-791c-4787-85bb-d11de689125d'
   no idea if this will work.
   also notice that in the API Explorer the / gets changed to %2F  so not sure if this is part of the issue or not.

  Has to be via Db query at this point.
  get the Id(s) of the resources 
  then get the cat_request(s)

.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
.NOTES
  Author: Clint Fritz
  #select id,name,status,datedeleted from cat_resource where name like any(array['%$($Name)%']);


#>
    [CmdletBinding()]
    [Alias()]
    [OutputType([int])]
    Param
    (
        # vRA Resource name. Deployment name or machine name
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string[]]$Name,

        # vRA Server
        [Parameter(Mandatory)]
        [Alias("Server","IPAddress","FQDN","vRAServer")]
        [string]$ComputerName="vra1.corp.local",

        [Parameter(Mandatory,ParameterSetName="ByCredential")]
        [ValidateNotNullOrEmpty()]
        [Management.Automation.PSCredential]$Credential,

        #The number of requests to return. Default is 10
        [int]$MaxRequests=10,

        #Whether to search for any related items. e.g the Deployment parents and descendants.
        #sometimes an action is taken on the deployment and not the machine being queried.
        [Parameter(Mandatory=$false)]
        [switch]$Recursive=$true,

        #The full path to plink.exe. Without plink.exe this function will not work.
        [ValidateScript({Test-path -Path $_})]
        [string]$plinkExePath = "C:\Program Files\Putty\plink.exe"
    )

    Begin
    {

        $tempCmdFile = [System.Io.Path]::GetTempFileName()

        $Username = $credential.username
        $Password = $credential.getnetworkcredential().Password

        #TODO: test for plink.exe in the location and terminate if not found.
        #I am not sure if the ValidateScript will work or operate on the default parameter.
        #A: NO it does not. :( Unless I made the parameter mandatory. Which is sort of what I thought.

    }

    Process
    {


        [array]$resourceColumns = "id","name","status","parentresource_id"

$Command = @"
/opt/vmware/vpostgres/current/bin/psql -U postgres -d vcac -c "select $($resourceColumns -join ",") from cat_resource where name like any(array['%$($Name -join "%','%")%']);"
"@
        foreach ($item in $Command) {
            Write-Verbose "[INFO] Command: $($item)"
        }
        $command | Out-File -FilePath $tempCmdFile -Encoding ascii
        $result = &($plinkExePath) -ssh $ComputerName -l $UserName -pw $Password -m $tempCmdFile
        foreach ($item in $result) {
            Write-Verbose "[INFO] Result: $($item)"
        }    

        $params = @{
            Delimiter = '\|' 
            PropertyNames = $resourceColumns
        }

        $tempObject = $result | ? { $_ -notmatch "\([0-9]* row[s]?\)" } | ConvertFrom-String @params | ? { $_.id.trim() -ne "id" }
    
        #create a new object after trimming the values
        $resources = $tempObject.ForEach({
            $hash = [ordered]@{}
            $_.PSObject.Properties.ForEach({
                $hash.$($_.name) = "$($_.value)".trim()
            })
            $object = New-Object PSObject -Property $hash
            $object
        })






        #/opt/vmware/vpostgres/current/bin/psql -U postgres -d vcac -c "select id,requestnumber,state,resource_id from cat_request where resource_id in ('$($resourceIds -join "','")') order by requestnumber desc limit $($MaxRequests);"
        #Specify the columns for the sql statement and this will automatically be applied during the conversion of the results into a powershell object.
        [array]$requestColumns = "id","requestnumber","state","datesubmitted","resource_id","catalogitem","resourceaction_id"
   
$Command = @"
/opt/vmware/vpostgres/current/bin/psql -U postgres -d vcac -c "select $($requestColumns -join ",") from cat_request where resource_id in ('$($resourceIds -join "','")') order by requestnumber desc limit $($MaxRequests);"
"@
        foreach ($item in $Command) {
            Write-Verbose "[INFO] Command: $($item)"
        }
        $command | Out-File -FilePath $tempCmdFile -Encoding ascii
        $result = &($plinkExePath) -ssh $ComputerName -l $UserName -pw $Password -m $tempCmdFile
        foreach ($item in $result) {
            Write-Verbose "[INFO] Result: $($item)"
        }


        $params = @{
            Delimiter = '\|' 
            PropertyNames = $requestColumns
        }

        $tempObject = $result | ? { $_ -notmatch "\([0-9]* row[s]?\)" } | ConvertFrom-String @params | ? { $_.id.trim() -ne "id" }
    
        #create a new object after trimming the values
        $requests = $tempObject.ForEach({
            $hash = [ordered]@{}
            $_.PSObject.Properties.ForEach({
                $hash.$($_.name) = "$($_.value)".trim()
            })
            $object = New-Object PSObject -Property $hash
            $object
        })


        #get the request numbers
        $requestNumbers = $requests | Select -ExpandProperty requestnumber
        foreach ($item in $requestNumbers) {
            Write-Verbose "[INFO] Request Numbers: $($item)"
        }

    
   



    }

    End {
    }
}
