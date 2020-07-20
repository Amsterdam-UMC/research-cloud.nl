<#
.SYNOPSIS 
    This Automation runbook runs in a 1one hour schedule and does:
    - deallocate stopped VM's
    
.DESCRIPTION
    A RunAs account in the Automation account is required for this runbook.
    This runbook is converted to the new Azure Az API, so these modules must be loaded into the automation account
    - enable LocalPolicy backup on each VM withut backup policy
    - deallocate each VM that is only stopped

.NOTES
    AUTHORs: Microsoft Automation Team, A.H.Ullings
    Copyright 2019, All Rights Reserved
    LASTEDIT: 03/03/2020 
#>

# Ensures you do not inherit an AzureRMContext in your runbook
# Disable-AzureRmContextAutosave –Scope Process
$AZUREPLAYID = 'd27809b6-6226-43f4-8daa-dc2ecc8f8fe2'

$connection = Get-AutomationConnection -Name AzureRunAsConnection
$res = Add-AzAccount -ServicePrincipal -Tenant $connection.TenantID `
-ApplicationId $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
#
#
function VMDeallocateStopped($vm)
{
    $vmdetail = Get-AzVM -Name $vm.Name -Status
    if ($vmdetail.Powerstate.CompareTo("VM stopped") -eq 0)
    {
        $res = Stop-AzVM -Force -Id $vm.Id
    }
}

#
$sublist = Get-AzSubscription
foreach ($sub in $sublist)
{
    if ($sub.Id -eq $AZUREPLAYID) 
    {
        continue
    }
    $res = Set-AzContext -SubscriptionId $sub.Id
    Write-Output $sub.Name
    $vmlist = Get-AzVM
    foreach ($vm in $vmlist)
    {
        $ErrorActionPreference = "SilentlyContinue"
        VMDeallocateStopped($vm)
    }
}	
