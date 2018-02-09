param (
    [switch]$whatif,
    [switch]$verbose,
    [string]$CSV_Deployment_File = "VMDeploy.csv"
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
    $ds_result = Get-Datastore $datastore -ErrorAction SilentlyContinue | Select Name
    $dsc_result = Get-DatastoreCluster $datastore -ErrorAction SilentlyContinue | Select Name
    if (($ds_result) -Or ($dsc_result)) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Datastore not found - $datastore" -f red
        return $false 
    }
}

function check-template ($template) {
    $result = Get-template $template -ErrorAction SilentlyContinue | Select Name
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
        write-host "`tDeploying" $vm.name -f cyan
        if ($whatif) {
            write-host `tNew-VM -Server $vm.viserver -Name $vm.name -ResourcePool $vm.cluster -Datastore $vm.datastore -Template $vm.template -OSCustomizationSpec $vm.customizationspec -Description $vm.notes -f magenta
            $nvm_result = $true
            } else {
                $nvm_result = New-VM -Server $vm.viserver -Name $vm.name -ResourcePool $vm.cluster -Datastore $vm.datastore -Template $vm.template -OSCustomizationSpec $vm.customizationspec -Description $vm.notes
            }
        
        if ($nvm_result) {
            if ($whatif) {
                write-host `tSet-VM -Server $vm.viserver -MemoryGB $vm.ram -NumCpu $vm.cpu -Confirm:$false -f magenta
                } else {
                    $svm_result = $nvm_result | Set-VM -Server $vm.viserver -MemoryGB $vm.ram -NumCpu $vm.cpu -Confirm:$false
                }
            
            foreach ($Pname in ((Get-Member -InputObject $vm -MemberType NoteProperty).name) ) {
                if (($Pname -like "disk*") -And ($vm.$Pname)) {
                    $driveLetter,$diskSizeGB = $vm.$Pname.split(':')
                    write-host "`tAdding a $diskSizeGB GB disk" -f cyan
                    if ($whatif) {
                        write-host `tNew-HardDisk -StorageFormat Thin -CapacityGB $diskSizeGB -Confirm:$false -WarningAction silentlyContinue -f magenta
                        } else {
                            $nhd_result = $nvm_result | New-HardDisk -StorageFormat Thin -CapacityGB $diskSizeGB -Confirm:$false -WarningAction silentlyContinue
                        }
                }
            }
        }

       
        if (($nvm_result) -And ($svm_result)) {
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
    
    } # if ( $ClusterCheck -And $DatastoreCheck -And $TemplateCheck -And $OSCustCheck -And -Not $VMExists )
       
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
    $ResultList += deploy-vm $vm
}

if ($verbose) {
    write-output $ResultList
}

    
    
