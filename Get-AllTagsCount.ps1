#Requires -module Logging, ImportExcel

$Subscriptions = Get-AzSubscription
$AllTags = @()
foreach($Subs in $Subscriptions){
    $Subs | Set-AzContext
    $AllTags += Get-AzTag
}

$CurrentDate = Get-Date
$ReportName = $($CurrentDate.ToString("yyyy-MM-dd")) + "_AllTags.xlsx"
$FinalTagsList = @()

# Merge duplicated tags  keys in $AllTags
foreach($Tag in $AllTags){
    $TagKey = $Tag.Name
    if($TagKey -cin $FinalTagsList.Name){
        continue
    }
    else{
        $TagCounts = $AllTags | Where-Object {$_.Name -ceq $TagKey} | Select-Object -ExpandProperty Count
        $TagSumm = 0
        foreach($Count in $TagCounts){
            $TagSumm += $Count
        }
        $FinalTagsList += New-Object PSObject -Property @{
            Name = $TagKey
            Count = $TagSumm
        }
    }    
}

if(Test-Path $ReportName){
    Remove-Item $ReportName
}
$FinalTagsList | Select-Object Name, Count | Export-Excel -Path $ReportName -AutoSize -AutoFilter -TableStyle Medium2