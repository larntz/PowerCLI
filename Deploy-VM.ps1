param (
    [switch]$whatif
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
    $result = Get-VM $vm -ErrorAction SilentlyContinue   
    if ($result) { 
        write-host "`n`tCheck Failed: VM Exists - $vm" -f red
        return $true 
    } else { 
        return $false 
    }
}

function check-cluster ($cluster) {
    $result = Get-Cluster $cluster -ErrorAction SilentlyContinue   
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
    if (($ds_result) -Or ($dsc_result)) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Datastore not found - $datastore" -f red
        return $false 
    }
}

function check-template ($template) {
    $result = Get-template $template -ErrorAction SilentlyContinue   
    if ($result) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Template not found - $template" -f red
        return $false 
    }
}

function check-oscustomization ($customizationspec) {
    $result = Get-OSCustomizationSpec $customizationspec -ErrorAction SilentlyContinue   
    if ($result) { 
        return $true 
    } else { 
        write-host "`n`tCheck Failed: Customization Spec not found - $customizationspec" -f red
        return $false 
    }
}


function deploy-vm ($vm) {
    write-host -NoNewline `n`nPerforming checks on $vm.name": "  -f yellow
    ## Perform Checks
    $VIServerCheck = check-viserver $vm.viserver
    $ClusterCheck = check-cluster $vm.cluster
    $DatastoreCheck = check-datastore $vm.datastore
    $TemplateCheck = check-template $vm.template
    $OSCustCheck = check-oscustomization $vm.customizationspec
    $VMExists = vm-exists $vm.name
    
    if ( $ClusterCheck -And $DatastoreCheck -And $TemplateCheck -And $OSCustCheck -And -Not $VMExists ) {
        write-host "PASSED" -f green
        $nvm_result = New-VM -Server $vm.viserver -Name $vm.name -ResourcePool $vm.cluster -Datastore $vm.datastore -Template $vm.template -OSCustomizationSpec $vm.customizationspec -Description $vm.notes
        $svm_result = Set-VM -Server $vm.viserver -VM $vm.name -MemoryGB $vm.ram -NumCpu $vm.cpu -Confirm:$false
        
        if (($nvm_result) -And ($svm_result)) {
            $success = $true
        }
        else {
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

if (-Not ($VMList = Import-CSV "VMDeployDetails.csv") ) {
    write-host "File not found: VMDeployDetails.csv" -f red
    exit
    }
    
$ResultList = @()

foreach ($vm in $VMList) {
    $ResultList += deploy-vm $vm
}

write-output $ResultList

    
    
