#
# https://03ea8e55-27ed-477f-b957-b98086cafb70.webhook.we.azure-automation.net/webhooks?token=ckFqiu6GGWkevr0MXIXLfEQQ8aThvEsXu6GEdSN0ja4%3d
# 
<#
.SYNOPSIS 
    This Automation runbook integrates with Azure event grid subscriptions to get notified when a 
    succesful write command is performed against an Azure VM. 
    The runbook:
    - adds a DNS Tag to the VM if it doesn't exist
    - creates private and public DNS records for the VM
    - enables backup policy LocalPolicy to the VM
    
.DESCRIPTION
    A RunAs account in the Automation account is required for this runbook.
    This runbook is converted to the new Azure Az API, so these modules must be loaded into the automation account

.PARAMETER WebhookData
    Optional. The information about the write event that is sent to this runbook from Azure Event grid.
  
.PARAMETER ChannelURL
    Optional. The Microsoft Teams Channel webhook URL that information will get sent.

.NOTES
    AUTHORs: Microsoft Automation Team, A.H.Ullings
    COPYRIGTH: All Rights Reserved, 2020
    LASTEDIT: 20/07/2020
#>
 
Param(
    [parameter (Mandatory=$false)]
    [object] $WebhookData,

    [parameter (Mandatory=$false)]
    $ChannelURL
)

#
function Remove-PrivateDnsIpv4Register ($rn)
{
    Remove-AzPrivateDnsRecordSet -RecordSet $rn | Write-Verbose
}

#
function New-PrivateDnsIpv4Register ([string]$rg, [string]$ipv4, [string]$name, [string]$zone)
{
    New-AzPrivateDnsRecordSet -Name $name -RecordType A -ZoneName $zone `
	-ResourceGroupName $rg -Ttl 3600 -PrivateDnsRecords `
	(New-AzPrivateDnsRecordConfig -IPv4Address $ipv4) | Write-Verbose
}

#
function PrivateDnsIpv4Register ([string]$rg, [string]$ipv4, [string]$name, [string]$zone)
{
#
    foreach ($rn in (Get-AzPrivateDnsRecordSet -RecordType A -ZoneName $zone -ResourceGroupName $rg))   
    {
        # when IPv4 address or Name already registered in an A record
        if(($rn.Records.Ipv4Address -eq $ipv4) -or ($rn.Name -eq $name))
        {
            # remove the DNS record
	        Remove-PrivateDnsIpv4Register ($rn)
        }
    }
# insert the new one anyway.....
    New-PrivateDnsIpv4Register ($rg)($ipv4)($name)($zone)
    return
}

#
function Remove-DnsIpv4Register ($rn)
{
    Remove-AzDnsRecordSet -RecordSet $rn | Write-Verbose
}

#
function New-DnsIpv4Register ([string]$rg, [string]$ipv4, [string]$name, [string]$zone)
{
    New-AzDnsRecordSet -Name $name -RecordType A -ZoneName $zone `
	-ResourceGroupName $rg -Ttl 3600 -DnsRecords `
	(New-AzDnsRecordConfig -IPv4Address $ipv4) | Write-Verbose
}

#
function DnsIpv4Register ([string]$rg, [string]$ipv4, [string]$name, [string]$zone)
{
#
    foreach ($rn in (Get-AzDnsRecordSet -RecordType A -ZoneName $zone -ResourceGroupName $rg))   
    {
        # when IPv4 address or the Name already registered in an A record
        if(($rn.Records.Ipv4Address -eq $ipv4) -or ($rn.Name -eq $name))
        {
	        Remove-DnsIpv4Register ($rn)
        }
    }
# insert the new one anyway.....
    New-DnsIpv4Register ($rg)($ipv4)($name)($zone)
    return
}

#
function VMDnsProcessing ([string]$subid, [string]$rgname, [string]$vmname)
{
    Write-Output "DnsProcessing" $subid

    # set dynamic subscription to work against
    Set-AzContext -SubscriptionID $subid | Write-Verbose
    $sub = Get-AzSubscription -SubscriptionID $subid

    # check if tag name exists in subscription and create if needed.
    $TagName0 = 'DNSinternal'
    $TagName1 = 'DNSexternal'
    
    # get all tags from Resource (VM)
    $tags = ($vm = Get-AzVM -ResourceName $vmname -ResourceGroupName $rgname).Tags

    # check if this VM already has the DNS tag set.
    if (!($tags.ContainsKey($TagName0)))
    {
        # Write-Output 'DNSinternal' $vmname $rgname
        $nic = $vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/') | select -Last 1
        $ipaddress = (Get-AzNetworkInterface -Name $nic).IpConfigurations.PrivateIpAddress
        # call IPv4 mapping table
        $mapped = ./ipv4map.ps1 $ipaddress
        
        Write-Output 'DNSipv4map' $mapped
        
        # force lowercase hostname
        $name = $vmname.ToLower()

        # extract and compose the subdomain here, 'vrc' is default
        $subdomain = 'vrc'
        if($sub.Name -Match '^.* (.*_[^ ]+) .*$')
        {
            $subdomain = $Matches[1].ToLower().replace("_", "-")
        }

        # add the DNS Tags, private and public if so
        $tags.Add($TagName0, $name+'.'+$subdomain+'.research-cloud.private')
        if(![string]::IsNullOrEmpty($mapped))
        {
            $tags.Add($TagName1, $name+'.'+$subdomain+'.research-cloud.amsterdam')
        }
        
        # write back the Tags
        $res = Set-AzResource -Tag $tags -Force -ResourceName $vmname -ResourceGroupName $rgname `
            -ResourceType Microsoft.Compute/virtualMachines

        # register DNS entries, private + public
        $sub = Select-AzSubscription -Subscription 'Amsterdam UMC Azure Playground' | Write-Verbose
        
        PrivateDnsIpv4Register('azure-play-rg')($ipaddress)($name+'.'+$subdomain)('research-cloud.private')
        if(![string]::IsNullOrEmpty($mapped))
        {
            DnsIpv4Register('azure-play-rg')($mapped)($name+'.'+$subdomain)('research-cloud.amsterdam')
        }
    }
}

#
function VMPackagesProcessing ([string]$subid, [string]$rgname, [string]$vmname)
{
    Write-Output "VMPackagesProcessing" $subid

    # set dynamic subscription to work against
    Set-AzContext -SubscriptionID $subid | Write-Verbose
    $sub = Get-AzSubscription -SubscriptionID $subid

    # check if tag name exists in subscription and create if needed.
    $TagName = 'VMPackages'

    # get all tags from Resource (VM)
    $tags = ($vm = Get-AzVM -ResourceName $vmname -ResourceGroupName $rgname).Tags

    if (($tags.ContainsKey($TagName)) -and ($tags[$TagName].Contains('request')))
    {
        # remove the python clutter.....
        $tags[$TagName] = $tags[$TagName].replace("[", "").replace("]", "")
        $tags[$TagName] = $tags[$TagName].replace("'", "").replace("""", "").replace(" ", "")

        # build a powershell array of requested packages
        $array = @($tags[$TagName]) -split ","
        $ostype = $vm.StorageProfile.OsDisk.OsType
        
        for ($i = 0; $i -lt $array.length; $i++)
        {
	        $package = $array[$i].replace("<", "").replace(">", "")
            $package = $package.replace("request", "")+$ostype
            Write-Output $package
            switch ($package)
	        {
   	            "SCZ:Linux"   { $result = ./deploy-SCZ-Linux.ps1 -VMName $vmname -VMResourceGroupName $rgname; break }
   	            "R:Windows"   { $result = ./deploy-Windows.ps1 -VMPath './R_windows.ps1' -VMName $vmname -VMResourceGroupName $rgname; break }
   	            default       { $result = 'fail'; break }
	        }
            $array[$i] = $array[$i].replace(":request", ":"+$result)
            Write-Output $i
        }
        $tags[$TagName] = ($array -join " ").replace(" ", ",")
        $res = Set-AzResource -Tag $tags -Force -ResourceName $vmname -ResourceGroupName $rgname `
                -ResourceType 'Microsoft.Compute/virtualMachines'
    }
}

#
function VMEnableBackupProtectionPolicy ([string]$subid, [string]$rgname, [string]$vmname)
{
    Write-Output "VMEnableBackupProtectionPolicy" $subid

    # set dynamic subscription to work against
    Set-AzContext -SubscriptionID $subid | Write-Verbose
    $sub = Get-AzSubscription -SubscriptionID $subid

    # get parameters direct from VM
    $vm = Get-AzVM -ResourceName $vmname -ResourceGroupName $rgname

    $rg = $vm.ResourceGroupName.ToLower()
    $status = Get-AzRecoveryServicesBackupStatus -Type "AzureVM" -Name $vm.Name -ResourceGroupName $rg 
    if ($status.BackedUp -eq $false)
    {	
        # assume the VRC nameconvention here, map vrcXXX-XXX-rg to vrcXXX-XXX-backup
        $vaultname = $rg.replace("-rg", "-backup")
        if ($vault = (Get-AzRecoveryServicesVault -Name $vaultname -ResourceGroupName $rg)) 
        {
            Write-Output $vm.Name
            # apply the predefined 'LocalPolicy'
            $policy = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.Id -Name "LocalPolicy"
            $res = Enable-AzRecoveryServicesBackupProtection -VaultId $vault.Id -Policy $policy `
                    -Name $vm.Name -ResourceGroupName $rg
        }
    }
}

#
#
$RequestBody = $WebhookData.RequestBody | ConvertFrom-Json
$Data = $RequestBody.data

# if ($Data.operationName -match "Microsoft.Resources/deployments/write")  
if ($Data.operationName -match "Microsoft.Compute/virtualMachines/write" -and $Data.status -match "Succeeded") 
{ 
    # authenticate to Azure
    $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
    Add-AzAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Write-Verbose
        
    # set static subscription to work against
    # Set-AzContext -SubscriptionID $ServicePrincipalConnection.SubscriptionId | Write-Verbose
    
    #
    # get subscription, resource group and VM name
    $Resources = $Data.resourceUri.Split('/')
    $SubscriptionId = $Resources[2]
    $VMResourceGroup = $Resources[4]
    $VMName = $Resources[8]

    # set dynamic subscription to work against
    Set-AzContext -SubscriptionID $SubscriptionId | Write-Verbose
    $sub = Get-AzSubscription -SubscriptionID $SubscriptionId

    # try to prevent race conditions.... you are not supposed to understand this
    Start-Sleep -s 60
    
    # get all tags from Resource (VM)
    $tags = ($vm = Get-AzVM -ResourceName $VMName -ResourceGroupName $VMResourceGroup).Tags

    # check if this VM already has the OnVMcreate tag set......
    if (!($tags.ContainsKey('OnVMcreate')))
    {
        $tags.Add('OnVMcreate', 'True')
        
        # write back the Tags
        $res = Set-AzResource -Tag $tags -Force -ResourceName $VMName -ResourceGroupName $VMResourceGroup `
            -ResourceType Microsoft.Compute/virtualMachines
    
        # proces several actions on this VM
        VMDnsProcessing ($SubscriptionId)($VMResourceGroup)($VMName)
        VMEnableBackupProtectionPolicy ($SubscriptionId)($VMResourceGroup)($VMName)
        # VMPackagesProcessing ($SubscriptionId)($VMResourceGroup)($VMName)
        
    }
}