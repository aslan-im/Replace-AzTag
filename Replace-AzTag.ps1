#Requires -module Logging, Az.Accounts

<#
.SYNOPSIS
    Script for tag keys consolidation
.DESCRIPTION
    You need to provide a list of tags to replace and a correct tag name. Script will replace all incorrect tags with correct one.
.NOTES
    Dependencies: Logging, Az.Accounts
    Do not forget to specify the list of tag keys to replace and correct tag name!
.LINK
    https://github.com/aslan-im/Replace-AzTag
.EXAMPLE
    .\Replace-AzTag.ps1
#>

#region CommonVariables
$WorkingDirectory = Switch ($Host.name) {
    'Visual Studio Code Host' { 
        split-path $psEditor.GetEditorContext().CurrentFile.Path 
    }
    'Windows PowerShell ISE Host' {
        Split-Path -Path $psISE.CurrentFile.FullPath
    }
    'ConsoleHost' {
        $PSScriptRoot 
    }
}

$CurrentDate = Get-Date

$TagsToReplace = @(
    " Application Name",
    "Applicaion Name",
    "Applicaiton Name",
    "application",
    "Application Name",
    "AppName",
    "appname",
    "Application"
)
$CorrectTag = "Application Name"
#endregion

#region Logging Configuration
$LogFilePath = "$WorkingDirectory\logs\log_$($CorrectTag -replace ' ', '_')_$($CurrentDate.ToString("yyyy-MM-dd")).log"
Set-LoggingDefaultLevel -Level 'Info'
Add-LoggingTarget -Name File -Configuration @{
    Path        = $LogFilePath
    PrintBody   = $false
    Append      = $true
    Encoding    = 'ascii'
}

Add-LoggingTarget -Name Console -Configuration @{}
#endregion


Write-Log "Checking current Az Connection"
$Context = Get-AzContext
if($Context){
    Write-Log "Connection to $($Context)"
}
else{
    Write-Log "No connection found, connecting to Azure"
    Connect-AzAccount
}

Write-Log "Getting subscription list"
$Subscriptions = Get-AzSubscription

Write-Log "Working with tags"
Write-Log "Tags to replace: $($TagsToReplace -join ', ') `nCorrect tag: $CorrectTag"

foreach($TagToReplace in $TagsToReplace){
    Write-Log "Working with tag '$TagToReplace'"
    if ($TagToReplace -eq $CorrectTag){
        Write-Log "Tag is correct, skipping"
        continue
    }
    foreach($Subscription in $Subscriptions){
        Write-Log "Working with subscription '$($Subscription.Name)'"
        $Subscription | Set-AzContext
        $Resources = Get-AzResource -TagName $TagToReplace
        Write-Log "Found $($Resources.count) resources with tag '$TagToReplace'"
        if($Resources.count -gt 0){
            foreach($Resource in $Resources){
                Write-Log "Resource: $($Resource.ResourceId)"
                $ResourceTags = $Resource.Tags
                Write-Log "Resource tags: $($ResourceTags | Out-String)"
                if($ResourceTags.Keys -ccontains $TagToReplace){
                    if($ResourceTags.Keys -notcontains $CorrectTag){
                        $TagToReplaceValue = $ResourceTags[$TagToReplace]
                        Write-Log "Tag value: $TagToReplaceValue"
                        Write-Log "Removing incorrect tag: '$TagToReplace'"
                        $ResourceTags.Remove($TagToReplace)
                        Write-Log "Adding correct tag: '$CorrectTag'"
                        $ResourceTags.Add($CorrectTag, $TagToReplaceValue)
                        try{
                            Write-Log "Updating resource tags"
                            Set-AzResource -ResourceId $Resource.ResourceId -Tag $ResourceTags -Force -ErrorAction "STOP" | Out-Null
                            Write-Log "Tag replaced"
                            $NewResourceTags = Get-AzResource -ResourceId $Resource.ResourceId | Select-object Tags
                            Write-Log "Tags after update:`n$($NewResourceTags.Tags | Out-String)"
                        }
                        catch{
                            Write-Log "Error replacing tag: $($_.Exception.Message)" -Level Error
                        }
                    }
                    else{
                        Write-Log "Tag '$CorrectTag' already exists, skipping" -level WARNING
                    }                  
                }
                else{
                    Write-Log "Tag key case is not the same. Skipping!" -Level Warning
                    continue
                }
                $ResourceTags = $null
                $TagToReplaceValue = $null
                
            }
        }
        else{
            Write-Log "No resources found with tag '$TagToReplace'"
        }
    }
    Write-Log "Completed"
}