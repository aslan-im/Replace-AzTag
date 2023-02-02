#Requires -module Logging, Az.Accounts

<#
.SYNOPSIS
    Script for tag keys consolidation
.DESCRIPTION
    You need to provide a list of tags to replace and a correct tag name. Script will replace all incorrect tags with correct one.
.NOTES
    Dependencies: Logging, Az.Accounts
    Do not forget to specify the list of tag keys to replace and correct tag name!
    Version: 1.2.0
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
$ScriptErrors = @()
$ScriptWarnings = @()

$TagsToReplace = @(
    "Created By"
)
$CorrectTag = "CreatedBy"
#endregion

#region Logging Configuration
$LogFilePath = "$WorkingDirectory\logs\log_$($CorrectTag -replace ' ', '_')_$($CurrentDate.ToString("yyyy-MM-dd")).log"
$ErrorsLogFilePath = "$WorkingDirectory\logs\errors_$($CorrectTag -replace ' ', '_')_$($CurrentDate.ToString("yyyy-MM-dd")).log"
$WarningsLogFilePath = "$WorkingDirectory\logs\warnings_$($CorrectTag -replace ' ', '_')_$($CurrentDate.ToString("yyyy-MM-dd")).log"

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

#region Counters
$TagsToReplaceCount = $TagsToReplace.count
$TagsCounter = 1
#endregion

foreach($TagToReplace in $TagsToReplace){

    $TagsPercent = $TagsCounter / $TagsToReplaceCount * 100

        $TagsProgressSplat = @{
            Activity = "Checking Tags"
            PercentComplete = $TagsPercent
            Id = 1
            Status = "[$TagsCounter/$TagsToReplaceCount] Checking '$TagToReplace' tag..."
        }

        Write-Progress @TagsProgressSplat

    Write-Log "Working with tag '$TagToReplace'"

    if ($TagToReplace -eq $CorrectTag){
        Write-Log "Tag is correct, skipping"
        continue
    }

    $SubsCount = $Subscriptions.count
    $SubsCounter = 1

    foreach($Subscription in $Subscriptions){
        $SubsPercent = $SubsCounter / $SubsCount * 100

        $SubsProgressSplat = @{
            Activity = "Checking '$TagToReplace' ==> '$CorrectTag' in '$($Subscription.name)' subscription"
            PercentComplete = $SubsPercent
            Id = 2
            Status = "[$SubsCounter/$SubsCount] Checking '$($Subscription.name)' subscription..."
        }

        Write-Progress @SubsProgressSplat
        Write-Log "Working with subscription '$($Subscription.Name)'"
        $Subscription | Set-AzContext
        $Resources = Get-AzResource -TagName $TagToReplace
        Write-Log "Found $($Resources.count) resources with tag '$TagToReplace'"

        $ResourcesCount = $Resources.count
        $ResourcesCounter = 1
        if($ResourcesCount -gt 0){
            foreach($Resource in $Resources){

                $ResourcesPercent = $ResourcesCounter / $ResourcesCount * 100

                $ResourcesProgressSplat = @{
                    Activity = "Working with resources in '$($Subscription.name)' subscription"
                    PercentComplete = $ResourcesPercent
                    Id = 3
                    Status = "[$ResourcesCounter/$ResourcesCount] Checking '$($Resource.ResourceId)' resource ID..."
                }

                Write-Progress @ResourcesProgressSplat

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
                            Write-Log "Error replacing tag $TagToReplace on $($Resource.ResourceId): $($_.Exception.Message)" -Level Error
                            "Error replacing tag $TagToReplace on $($Resource.ResourceId): $($_.Exception.Message)" | Out-File $ErrorsLogFilePath -Append
                        }
                    }
                    else{
                        Write-Log "Tag '$CorrectTag' already exists, skipping" -level Warning
                        "Tag '$CorrectTag' already exists. Skipping: $($Resource.ResourceId)" | Out-File $WarningsLogFilePath -Append
                    }                  
                }
                else{
                    Write-Log "Tag key case is not the same. Skipping!" -Level Warning
                    "Tag key case is not the same ['$CorrectTag']. Skipping! `n  Resource tags: $($ResourceTags | Out-String)" | Out-File $WarningsLogFilePath -Append
                    continue
                }
                $ResourceTags = $null
                $TagToReplaceValue = $null
                $ResourcesCounter++
            }
        }
        else{
            Write-Log "No resources found with tag '$TagToReplace'"
        }
        $SubsCounter++
    }
    $TagsCounter++    
}
Write-Log "Completed!"