param (
    [Parameter(
    Position=0, 
    Mandatory=$true, 
    ValueFromPipeline=$true,
    ValueFromPipelineByPropertyName=$true)
    ]
    [string[]]$vmname
)

Begin {
    # api authorization header
    $headers = @{"Authorization"="Token ADDTOKEN"}
    $url = "http://ipamurl/api"
    # today's date
    $date = get-date -uformat "%Y-%m-%d"
    
    #####################################################
    ### FUNCTIONS
    #####################################################

    ## ADD IP to IPAM. 
    function add_ipaddress ($ipslash) {
        $uri = "$url/ipam/ip-addresses/"
        $ipaddress_object = @{
            address = $ipslash
        }
        $ipaddress_object_json = $ipaddress_object | ConvertTo-Json
        $add_ip_results = Invoke-RestMethod -Method POST -ContentType "application/json" -Headers $headers -uri $uri -body $ipaddress_object_json

    }

    function update_ipaddress($ipslash,$adapter_id) {
        $uri = "$url/ipam/ip-addresses/?q=$ipslash"


        $ipam_ip_query = Invoke-RestMethod -uri $uri
        if ($ipam_ip_query.count -eq 1) {
            if (-not $ipam_ip_query.results.count) {
                add_ipaddress $ipslash
                $ipam_ip_query = Invoke-RestMethod -uri $uri
            }

            $ip_id = $ipam_ip_query.results.id

            $uri = "$url/ipam/ip-addresses/$ip_id/"
            $ip_object = @{
                interface = $adapter_id
            }
            $ip_object_json = $ip_object | ConvertTo-Json

            $update_ip_results = Invoke-RestMethod -uri $uri -Method PATCH -ContentType "application/json" -Headers $headers  -body $ip_object_json
        } 
        return
    }


    ## UPDATE interfaces.
    function update_interfaces($vm_view, $num_nics, $vm_ipam_id) {

        # Loop through the NICs and IP addresses
        for ($i=0; $i -lt $num_nics; $i++) {
            $adapter_number = ($i+1)
            $adapter_name = "Network Adapter "+$adapter_number

            if (($num_nics -gt 1) -And ($vm_view.guest.net.DeviceConfigID[$i] -ge 4000) ){
                write-verbose "if num_nics = $num_nics and DeviceConfigID[$i] = $vm_view.guest.net.DeviceConfigID[$i]"
                $adapter_type = (($vm_view.Config.Hardware.Device | where {$_ -is [VMware.Vim.VirtualEthernetCard]})[$i]).GetType().Name
                $network_name = ($vm_view.Guest.Net.Network)[$i]
                $adapter_object = @{
                    virtual_machine = $vm_ipam_id
                    name = $adapter_name
                    description = "NETWORK NAME: $network_name. ADAPTER TYPE: $adapter_type."
                    mac_address =  if ($num_nics -gt 1) { ($vm_view.Guest.Net.MacAddress)[$i] } else { $vm_view.Guest.Net.MacAddress }
                }
            } elseif (($num_nics -eq 1) -And ($vm_view.guest.net.DeviceConfigID -ge 4000))  {
                write-verbose "elseif num_nics = $num_nics and DeviceConfigID = $vm_view.guest.net.DeviceConfigID"
                $adapter_type = ($vm_view.Config.Hardware.Device | where {$_ -is [VMware.Vim.VirtualEthernetCard]}).GetType().Name
                $network_name = $vm_view.Guest.Net.Network
                $adapter_object = @{
                    virtual_machine = $vm_ipam_id
                    name = $adapter_name
                    description = "NETWORK NAME: $network_name. ADAPTER TYPE: $adapter_type."
                    mac_address =  if ($num_nics -gt 1) { ($vm_view.Guest.Net.MacAddress)[$i] } else { $vm_view.Guest.Net.MacAddress }
                }       
            
            }
            
            ## Find out if the adapter already exists
            $adapter_mac = $adapter_object.mac_address
            write-verbose "mac address = $adapter_mac" 
            $uri = "$url/virtualization/interfaces/?mac_address=$adapter_mac"
            $adapter_exists = Invoke-RestMethod -uri $uri
            write-verbose "adapter_exists =  $adapter_exists"
            
            if ($adapter_exists.count -eq 1) {
                $adapter_id = $adapter_exists.results.id

                ## UPDATE Adapter in IPAM.
                $adapter_object_json = $adapter_object | Convertto-json 
                $uri = "$url/virtualization/interfaces/$adapter_id/"
                $adapter_response = Invoke-RestMethod -Method PATCH -ContentType "application/json" -Headers $headers -uri $uri -body $adapter_object_json
                write-verbose "Updating adapter id =$adapter_exists.results.id  response id = $adapter_response.id"
            } elseif ($adapter_exists.count -eq 0) {
                ## ADD Adapter in IPAM.
                $adapter_object_json = $adapter_object | Convertto-json 
                $uri = "$url/virtualization/interfaces/"
                $adapter_response = Invoke-RestMethod -Method POST -ContentType "application/json" -Headers $headers -uri $uri -body $adapter_object_json
                write-verbose "Added adapter ($adapter_mac) adapter_reponse.id =$adapter_response.id"
            }


            #get number of IPs assigned to NIC
            $num_ips = ($vm_view.guest.net[$i].ipaddress | where  {([IPAddress]$_).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork}).count
            
            if ($num_ips -gt 1) {
                for ($y=0; $y -lt $num_ips; $y++) {
                        # Get VM IP address and add '/24' to the end for compatibilty with the ipam format.  !We are assuming all nets are /24!
                        $vm_ip = ($vm_view.guest.net[$i].ipaddress | where  {([IPAddress]$_).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork})[$y] + "/24"
                    
                        # Associate IP with Adapter
                        if ($vm_ip -ne "0.0.0.0/24") { update_ipaddress $vm_ip $adapter_response.id }
                }
            } elseif ($num_ips -eq 1) {
                # Get VM IP address and add '/24' to the end for compatibilty with the ipam format.  !We are assuming all nets are /24!
                $vm_ip = ($vm_view.guest.net[$i].ipaddress | where  {([IPAddress]$_).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork}) + "/24"
                
                # Associate IP with Adapter
                if ($vm_ip -ne "0.0.0.0/24") { update_ipaddress $vm_ip $adapter_response.id }
            }
        }
    }

    ## Update or Add VM to IPAM
    function update_vm($vm) {
        $vm_name = $vm.name
        $ipam_vm_query = Invoke-RestMethod -uri $url/virtualization/virtual-machines/?name="$vm_name"
        

        if (-not $ipam_vm_query.count) { 
            ## VM is not in IPAM and will be added.

            ## Get VM Cluster Info
            $cluster_name = $vm.cluster
            $uri = "$url/virtualization/clusters/?name=$cluster_name"
            $ipam_cluster_query = Invoke-RestMethod -uri $uri
            
            if (-not $cluster_name) {
                write-host "Ignoring VM (not in cluster)" -f yellow
                return -1;
            }
            
            if($vm.primary_ip4) {
                $ipslash = $vm.primary_ip4+"/24"
                $ipam_ip_query = Invoke-RestMethod -uri $url/ipam/ip-addresses/?q=$ipslash
                if (-not $ipam_ip_query.count) {
                    add_ipaddress $ipslash
                    $ipam_ip_query = Invoke-RestMethod -uri $url/ipam/ip-addresses/?q=$ipslash
                }
                if (($ipam_ip_query.count -gt 1) -Or ($ipslash -eq "0.0.0.0/24")) {
                    write-host "DUPLICATE IP ADDRESS $ipslash" -f yellow
                    write-host "THIS IP WILL NOT BE ADDED TO IPAM" -f yellow
                    $vm_object = @{
                            name=$vm.name
                            status=$vm.status
                            cluster=$ipam_cluster_query.results.id
                            vcpus=$vm.vcpus
                            memory=$vm.memory
                            disk=[int]$vm.disk
                            comments=$vm.comments + "<br><br>---<br>Added via ipam.ps1 script on $date"
                        }
                } else {
                    $vm_object = @{
                            name=$vm.name
                            status=$vm.status
                            cluster=$ipam_cluster_query.results.id
                            primary_ip4=$ipam_ip_query.results.id
                            vcpus=$vm.vcpus
                            memory=$vm.memory
                            disk=[int]$vm.disk
                            comments=$vm.comments + "<br><br>---<br>Added via ipam.ps1 script on $date"
                        }
                }
            } else {
                $vm_object = @{
                        name=$vm.name
                        status=$vm.status
                        cluster=$ipam_cluster_query.results.id                    
                        vcpus=$vm.vcpus
                        memory=$vm.memory
                        disk=[int]$vm.disk
                        comments=$vm.comments + "<br><br>No IP information available. VMware tools are not installed, VM is powered off, or no IP address is assigned. <br>---<br>Added via ipam.ps1 script on $date"
                    }
            }

            $uri = "$url/virtualization/virtual-machines/"
            $vm_object_json = $vm_object | ConvertTo-Json 
            write-verbose "DEBUG"
            write-verbose "ipslash = $ipslash"
            write-verbose $ipam_ip_query
            if ($verbose) {
                write-output $vm_object
            }
            $add_vm_results = Invoke-RestMethod -Method POST -ContentType "application/json" -Headers $headers -uri $uri -body $vm_object_json
        } 
        else {
            ## VM is in IPAM and will be updated.
            $cluster_name = $vm.cluster
            $ipam_cluster_query = Invoke-RestMethod -uri $url/virtualization/clusters/?name=$cluster_name
            
            $ipam_vm_id = $ipam_vm_query.results.id
            if($vm.primary_ip4) {
                $ipslash = $vm.primary_ip4+"/24"
                $ipam_ip_query = Invoke-RestMethod  -uri $url/ipam/ip-addresses/?q=$ipslash
                if (-not $ipam_ip_query.count) {
                    add_ipaddress $ipslash
                    $ipam_ip_query = Invoke-RestMethod -uri $url/ipam/ip-addresses/?q=$ipslash
                }

                if (($ipam_ip_query.count -gt 1) -Or ($ipslash -eq "0.0.0.0/24")) {
                    write-host "DUPLICATE IP ADDRESS $ipslash" -f yellow
                    write-host "THIS IP WILL NOT BE ADDED TO IPAM" -f yellow
                    $vm_object = @{
                            name=$vm.name
                            status=$vm.status
                            cluster=$ipam_cluster_query.results.id
                            vcpus=$vm.vcpus
                            memory=$vm.memory
                            disk=[int]$vm.disk
                            comments=$vm.comments + "<br><br>---<br>Updated via ipam.ps1 script on $date"
                        }
                } else { 
                    $vm_object = @{
                            name=$vm.name
                            status=$vm.status
                            cluster=$ipam_cluster_query.results.id
                            primary_ip4=$ipam_ip_query.results.id
                            vcpus=$vm.vcpus
                            memory=$vm.memory
                            disk=[int]$vm.disk
                            comments=$vm.comments + "<br><br>---<br>Updated via ipam.ps1 script on $date"
                        }
                }
            } else {
                $vm_object = @{
                        name=$vm.name
                        status=$vm.status
                        cluster=$ipam_cluster_query.results.id                    
                        vcpus=$vm.vcpus
                        memory=$vm.memory
                        disk=[int]$vm.disk
                        comments=$vm.comments + "<br><br>No IP information available. VMware tools are not installed, VM is powered off, or no IP address is assigned. <br>---<br>Added via ipam.ps1 script on $date"
                    }
            }

            $uri = "$url/virtualization/virtual-machines/$ipam_vm_id/"
            $vm_object_json = $vm_object | ConvertTo-Json 
            write-verbose "DEBUG"
            write-verbose "ipslash = $ipslash"
            write-verbose "$ipam_ip_query.results"
            write-verbose $vm_object_json
                
            $update_vm_results =Invoke-RestMethod -Method PATCH -ContentType "application/json" -Headers $headers -uri $uri -body $vm_object_json
            

        }
        $uri = "$url/virtualization/virtual-machines/?name="+$vm.name
        $vm_confirm = Invoke-RestMethod -uri $uri

        return $vm_confirm.results.id
    }



} # end Begin

process {
#####################################################
### MAIN SCRIPT
#####################################################

    $vm =  Get-VM $vmname

    $curVm++
    $vm_info = get-vm  $vm | 
        Select Name, 
        @{N='status';E={if ($_.PowerState -eq "PoweredOn") {1} else {0}}},
        @{N='cluster';E={(Get-Cluster -vm $_).name}},
        @{N='vcpus';E={$_.numcpu}},
        @{N='memory';E={$_.MemoryMB}},
        @{n="disk"; e={(Get-HardDisk -VM $_ | Measure-Object -Sum CapacityGB).Sum}},
        @{n="primary_ip4";E={$_.guest.ipaddress[0]}},
        @{n="comments";E={$_.Notes}}

    ##############
    # Add or UPDATE VM in IPAM        
    Write-Host -NoNewline Processing VM $vm_info.name "... "
    $vm_ipam_id = update_vm $vm_info
    
    if ($vm_ipam_id -gt 0) {
        # Get-View - this is used to get NICs and which IPs are assigned to the specific NICs
        $vm_view = Get-View $vm
        # Get number of nics

        $num_nics = $vm_view.guest.net.DeviceConfigID.count

        write-verbose "num_nics = $num_nics" 

        if ($num_nics) {
            write-verbose "vm_ipam_id = $vm_ipam_id"
            update_interfaces $vm_view $num_nics $vm_ipam_id
            $vm_ipam_id = update_vm $vm_info
        }
    }
    Write-Host Finished
} # End Process


