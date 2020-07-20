<#
.SYNOPSIS 
    Update Event Grid subscription webhook  for all the VRC-Production workspaces
    using the Azure API within the existing Amsterdam UMC Research Cloud  research-cloud.nl context
    
.DESCRIPTION

.NOTES
    AUTHORs: A.H.Ullings
    LASTEDIT: 26/06/2020
    VERSION : 1.00
    Copyright 2020 All Rights Reserved
#>
$MGMTGROUP = 'SURFcumulus-Amsterdam-UMC-VRC-Production'
$ONVMCREATE = 'https://s2events.azure-automation.net/webhooks?token=6L9QtyiANEVho7tRCoXzx%2b3snUQ7Vwv8d9xWz1w4aWU%3d'
$AZVERSION = '4.1.0'

#
class workspaceRecord {
    [string] $rg
    [string] $subname
    [string] $short
    [string] $automate
    [string] $subevent
    [string] $rgevent
}

#
# Import the required modules
#
Write-Host 'import the required Azure API modules.....'
#
# iex "& { $(irm https://aka.ms/install-powershell.ps1) } -UseMSI"
# we need the newest stuff....
# Install-Module -Name Az -Force
# Install-Module -Name Az.Security -Force
# Update-Module Az -RequiredVersion $AZVERSION
Import-Module Az -RequiredVersion $AZVERSION

#
Clear-AzContext -Force

# Authenticate
# $PSDefaultParameterValues['Connect-AzAccount:UseDeviceAuthentication']=$true
$res = Connect-AzAccount
#

# at least one subscription must be selected.
Select-AzSubscription -Subscription 'SURFcumulus Amsterdam UMC VRC VUmc_ICT Production'

# get all subscription children of the Management Group
$response = Get-AzManagementGroup -GroupName $MGMTGROUP -Expand

Write-Host 'collect the workspaces list.....'
$workspaceList = [System.Collections.Generic.List[workspaceRecord]]::new()
#
foreach ($child in $response.Children) 
{
#
# Determine the per workspace ResourceGroupName adhering the namingconvention
#
	$sub = Select-AzSubscription -Subscription $child.DisplayName
	$rg = (Get-AzResourceGroup | Where ResourceGroupName -like "vrc*prod-rg").ResourceGroupName
    $short = $rg.replace("-rg", "");
    $newRec = [workspaceRecord] @{ `
         rg = $rg; `
         
         subname = $child.DisplayName; `
         short = $short; `
         automate = $short+'-automate'; `
         subevent = $short+'-event-01'; `
         rgevent = $rg+'-event' `
    }
    $workspaceList.Add($newRec)
}

#
foreach ($ws in $workspaceList[0])
{

    $sub = Select-AzSubscription -Subscription $ws.subname
    
    #
    # Select automation account facilitating Event subscriptions
    #
    Write-Host 'update automation account event', $ws.automate, $ws.subevent, $ws.rgevent
    $res = Get-AzAutomationAccount -ResourceGroupName $ws.rg -Name $ws.automate

    #
    # Remove legacy and current entry/webhook and resource group DEFAULT-EVENTGRID if any
    #
    Remove-AzEventGridSubscription -ResourceGroupName $ws.rg -EventSubscriptionName $ws.subevent
    Remove-AzEventGridSubscription -ResourceGroupName $ws.rg -EventSubscriptionName $ws.rgevent
    $res = Remove-AzResourceGroup -Name "DEFAULT-EVENTGRID" -Force -ErrorAction SilentlyContinue

    #
    # 
    # Define the Event Subscription parameters to the predefined webhook
    #
    $includedEventTypes = "Microsoft.Resources.ResourceWriteSuccess"
    $advancedFilter = @{operator="StringContains"; key="subject"; values=@("Microsoft.compute/virtualMachines/")}

    $res = New-AzEventGridSubscription -ResourceGroup $ws.rg -EventSubscriptionName $ws.rgevent `
	    -Endpoint $ONVMCREATE `
	    -IncludedEventType $includedEventTypes -AdvancedFilter @($advancedFilter)
}