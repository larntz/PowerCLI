<#

.SYNOPSIS
This script depoys virtual machines from details specified in a CSV file. 

.DESCRIPTION
This script uses a CSV file to deploy virtual machines. 

Columns required to be in the CSV file are:
viserver, name, template, cluster, datastore, cpu, ram, description, and customization spec

Optional colums are:
ipaddress, portgroup, diskx (can have as many as required, e.g., disk2,disk3,disk4),sql

.EXAMPLE
./Deploy-VM.ps1 -CSV_Deployment_File "c:\deployment.csv" -Verbose

.NOTES
If the -CSV_Deployment_File option is not used the script will attempt to use "\\VMDeployment\VMDeploy.csv"

#>

param (
    [switch]$whatif,
    [switch]$verbose,
    [string]$CSV_Deployment_File = "\\VMDeployment\VMDeploy.csvv",
    $ProgressPreference = 'SilentlyContinue'
)

function check-viserver ($viserver) {
    if (($global:DefaultViServers.count) -And ($global:DefaultViServers.name -eq $viserver) ) {
        $vcenter = $global:DefaultViServers.name
    } else {
        write-host "`n`nNot connected to $viserver!" -f red
        Connect-ViServer $viserver
    }
}

function vm-exists ($vm) {
    $result = Get-VM $vm -ErrorAction SilentlyContinue | Select Name
    if ($result) { 
        write-host "`n`tCheck Failed: VM Exists - $vm" -f red
        return $true 
    } else { 
        return $false 
    }
}

function check-cluster ($cluster) {
    $result = Get-Cluster $cluster -ErrorAction SilentlyContinue | Select Name
    if ($result) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Cluster not found - $cluster" -f red
        return $false 
    }
}

function check-datastore ($datastore) {
    $ds_result = Get-Datastore $datastore -ErrorAction SilentlyContinue 
    $dsc_result = Get-DatastoreCluster $datastore -ErrorAction SilentlyContinue 
    if ($ds_result) { 
        return $ds_result 
    } elseif ($dsc_result) {
        return $dsc_result
    } else { 
        write-host "`n`tCheck Failed: Datastore not found - $datastore" -f red
        return $false 
    }
}

function check-template ($template) {
    $result = Get-Template -Name $template -ErrorAction SilentlyContinue | Select Name
    if ($result) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Template not found - $template" -f red
        return $false 
    }
}

function check-oscustomization ($customizationspec) {
    $result = Get-OSCustomizationSpec $customizationspec -ErrorAction SilentlyContinue | Select Name
    if ($result) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Customization Spec not found - $customizationspec" -f red
        return $false 
    }
}

function modifyCustomizationSpec ($viserver,$customizationSpec,$ipAddress) {
    ## Create a non-persistent customization spec and set the static IP address.
    ## returns the new customization spec object
    write-output $customizationSpec

    $ipAddressObject = [ipaddress]$ipAddress
    $defaultGW = ([string]$ipAddressObject.GetAddressBytes()[0]) +"."+ ([string]$ipAddressObject.GetAddressBytes()[1]) +"."+ ([string]$ipAddressObject.GetAddressBytes()[2]) +".1"
    if (-Not ($tempSpec = Get-OSCustomizationSpec -Server $viserver -Name npCustSpec -EA SilentlyContinue)) {
        $tempSpec = (Get-OSCustomizationSpec -Server $viserver -Name $customizationSpec | New-OSCustomizationSpec -Name npCustSpec -Type NonPersistent)
    }
    $nicMapping = Get-OSCustomizationNicMapping -OSCustomizationSpec $tempSpec
    
    if ($customizationSpec -eq "LS_PowerShell_CustomizationSpec") {
        $nicMapping | Set-OSCustomizationNicMapping -IPMode UseStatic -IPAddress $ipAddress -SubnetMask 255.255.255.0 -DefaultGateway $defaultGW 
    } else {
        $nicMapping | Set-OSCustomizationNicMapping -IPMode UseStatic -IPAddress $ipAddress -SubnetMask 255.255.255.0 -DefaultGateway $defaultGW -Dns 10.5.60.100,10.8.60.100
    }
    

    return (Get-OSCustomizationSpec -Server $viserver -Name npCustSpec)
}


function deploy-vm ($vm) {
    write-host -NoNewline `n`nPerforming checks before deployment of $vm.name": "  -f yellow
    ## Perform Checks
    $VIServerCheck = check-viserver $vm.viserver
    $ClusterCheck = check-cluster $vm.cluster
    $DatastoreCheck = check-datastore $vm.datastore
    $TemplateCheck = check-template $vm.template
    $OSCustCheck = check-oscustomization $vm.customizationspec
    $VMExists = vm-exists $vm.name
    
    if ( $ClusterCheck -And $DatastoreCheck -And $TemplateCheck -And $OSCustCheck -And -Not $VMExists ) {
        write-host PASSED -f green
        write-host "`tDeploying $($vm.name) on $($vm.viserver)" -f cyan
        if ($whatif) {
            write-host `tNew-VM -Server $vm.viserver -Name $vm.name -ResourcePool $vm.cluster -Datastore $DatastoreCheck -Template $vm.template -f magenta
            $nvm_result = $true
            } else {
                ## -DiskStorageFormat EagerZeroedThick <- Doesn't work when using datastore clusters :(
                $nvm_result = New-VM -Server $vm.viserver -Name $vm.name -ResourcePool $vm.cluster -Datastore $DatastoreCheck  -Template $vm.template -WA silentlyContinue 
            }
        
        if ($nvm_result) {
            if ($whatif) {
                write-host `tSet-VM -Server $vm.viserver -MemoryGB $vm.ram -NumCpu $vm.cpu -Description $vm.description -OSCustomizationSpec $vm.customizationspec -Confirm:$false -f magenta  
                write-host "`tGet-NetworkAdapter | Set-NetworkAdapter -NetworkName $($vm.portgroup) -confirm:`$false" -f magenta
                write-host `tRemove-OSCustomizationSpec npCustSpec -confirm:$false -f magenta
                } else {
                    if ($vm.ipaddress) { 
                        ## We have a static IP and need to create a non-persistent customization spec that sets the IP to for this VM.
                        write-host `tModifying non-persistent customization spec to include static ip address [$($vm.ipaddress)] -f cyan
                        $customizationSpec = modifyCustomizationSpec $vm.viserver $vm.customizationspec $vm.ipAddress
                        write-host "`tSetting VM CPU, RAM, and customization spec" -f cyan
                        $svm_result = $nvm_result | Set-VM -Server $vm.viserver -MemoryGB $vm.ram -NumCpu $vm.cpu -OSCustomizationSpec npCustSpec -Description $vm.description -Confirm:$false -WA silentlyContinue 
                        write-host `tRemoving non-persistent customization spec `"npCustSpec`" -f cyan 
                        Remove-OSCustomizationSpec -Server $vm.viserver npCustSpec -confirm:$false
                    } else {
                        ## No static IP specified.  Use DHCP
                        write-host "`tSetting VM CPU, RAM, and customization spec" -f cyan
                        $svm_result = $nvm_result | Set-VM -Server $vm.viserver -MemoryGB $vm.ram -NumCpu $vm.cpu -OSCustomizationSpec $vm.customizationspec -Description $vm.description -Confirm:$false -WA silentlyContinue 
                    }
                    if ($vm.portgroup) {
                        if ($vm.dvswitch)
                        {
                            ## Using VDPortGroup
                            $portgroup = Get-VDPortGroup -VDSWitch $vm.dvswitch -Name $vm.portgroup
                            write-host `tChanging VD port group to $($vm.portgroup) -f cyan
                            $pgvm_result = $nvm_result | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $portgroup -confirm:$false -WA silentlyContinue 
                        } else {
                            ## Using Standard Network
                            write-host `tChanging port group to $($vm.portgroup) -f cyan
                            $pgvm_result = $nvm_result | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $vm.portgroup -confirm:$false -WA silentlyContinue 
                        }
                    }
                }
            }
            
            foreach ($Pname in ((Get-Member -InputObject $vm -MemberType NoteProperty).name) ) {
                if (($Pname -like "disk*") -And ($vm.$Pname)) {
                    $driveLetter,$diskSizeGB = $vm.$Pname.split(':')
                    write-host "`tAdding a $diskSizeGB GB disk" -f cyan
                    if ($whatif) {
                        write-host "`tNew-HardDisk -StorageFormat EagerZeroedThick -CapacityGB $diskSizeGB 	| New-ScsiController -Type ParaVirtual -confirm:`$false -WA silentlyContinue" -f magenta
                        } else {
                            $nhd_result = $nvm_result | New-HardDisk -StorageFormat EagerZeroedThick -CapacityGB $diskSizeGB | New-ScsiController -Type ParaVirtual -confirm:$false -WA silentlyContinue 
                        }
                }
            }
        }

       
        if (($nvm_result) -And ($svm_result) -And ($pgvm_result)) {
            write-host "$($vm.name) deployed successfully.`n`n" -f yellow
            $success = $true
        }
        elseif ($whatif) {
            $success = "whatif"
        } else {
            $success = $false
        }
    
    $Results = New-Object PSObject -Property @{
        Name = $vm.name
        Success = $success
        ClusterExists = $ClusterCheck
        DatastoreExists = $DatastoreCheck
        TemplateExists = $TemplateCheck
        OSCustomizationExists = $OSCustCheck
        VMExists = $VMExists
        Notes = $vm.notes
        }
           
    return $Results;
    
} # function deploy-vm 

######
# Main script block 
######
$VMList = @()
$ResultList = @()

if (-Not ($VMList = Import-CSV $CSV_Deployment_File) ) {
    write-host "File not found: $CSV_Deployment_File" -f red
    exit
    }

foreach ($vm in $VMList) {
    if ($verbose){
        write-host "Starting deployment of $($vm.name):" -f yellow
        write-output $vm
    }
    if ($vm.deploy -eq "Y") {
        $ResultList += deploy-vm $vm
    }
}
