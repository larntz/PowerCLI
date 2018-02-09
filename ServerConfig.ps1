param (
    [switch]$whatif
)
########### Run script as administrator
# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
 
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-Not $myWindowsPrincipal.IsInRole($adminRole))
   {
        # Create a new process object that starts PowerShell
        $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
        
        
        # Specify the current script path and name as a parameter
        $newProcess.Arguments =  "-executionpolicy bypass -noexit -file ServerConfig.ps1";
        
        # Indicate that the process should be elevated
        $newProcess.Verb = "runas";
        
        # Start the new process
        $process = [System.Diagnostics.Process]::Start($newProcess);
        
        # Exit from the current, unelevated, process
        exit
   }
########### Run script as administrator



##### CSV Location
$CSV_Deployment_File = "VMDeploy.csv"

if ($ComputerSpecs = Import-CSV $CSV_Deployment_File | where {$_.Name -eq $env:ComputerName}) {
    #Write-Output $ComputerSpecs
    Write-Host Found computer specs. Starting configuration...`n`n -f green
    
    $netadapter = (Get-NetIPInterface | Where {($_.InterfaceAlias -eq "Ethernet0") -And ($_.AddressFamily -eq "IPv4")})
    $netipAddress =  (Get-NetIPAddress | Where {($_.AddressFamily -eq "IPv4")})
    $ipAddress = [ipaddress]$ComputerSpecs.ipAddress

    $netadapter_disableDHCP = $netadapter |Set-NetIPInterface -DHCP Disabled 
    $DefaultGW = ([string]$ipAddress.GetAddressBytes()[0]) +"."+ ([string]$ipAddress.GetAddressBytes()[1]) +"."+ ([string]$ipAddress.GetAddressBytes()[2]) +".1"
    $netadapter_assignip = $netadapter | New-NetIPAddress -AddressFamily IPv4 -IPAddress $ComputerSpecs.ipAddress -PrefixLength 24 -DefaultGateway $DefaultGW  

    write-host `tSet $netadapter.InterfaceAlias IP address to $ComputerSpecs.ipaddress -f Green
    write-host "`t******************************" -f green
    write-host "`t* You must make sure the VM portgroup is set properly!" -f Green
    write-host "`t******************************" -f green
    Write-Host -NoNewLine "`tPress any key to continue..." -f white
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")


    write-host `n`tConfiguring Disks... -f green
    foreach ($ComputerProperty in (((Get-Member -InputObject $ComputerSpecs -MemberType NoteProperty).name) | Where {$_ -like "disk*"})) {
        $driveLetter,$diskSizeGB = $ComputerSpecs.$ComputerProperty.split(':')
        if ($driveLetter) {
            Write-Host "`tConfiguring Disk $driveLetter ($diskSizeGB GB)" -f green
            Stop-Service -Name ShellHWDetection -WarningAction silentlyContinue
            foreach ($disk in (Get-Disk | where {$_.PartitionStyle -eq "RAW"})) {
                if ( ($disk.Size / 1GB) -eq $diskSizeGB) {
                    Write-Host `t`tAssign $driveLetter to ($disk.size / 1GB)GB disk number $disk.Number -f green
                    $initialize = $disk | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter $driveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false
                }
            }
            Start-Service -Name ShellHWDetection -WarningAction silentlyContinue
        }
    }

    ##### Register Dynamic DNS Update 
    Write-Host "`n`tRunning Register-DNSClient" -f green
    Register-DNSClient 

    ##### Start Windows Update
    Write-Host "`n`tChecking for Updates..." -f green
    $registrypath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $registryname = "DisableWindowsUpdateAccess"
    $registryvalue = "0"
    $nip_result = New-ItemProperty -Path $registrypath -Name $registryname -Value $registryvalue -PropertyType DWORD -Force 

    if ($nip_result) {
        Restart-Service wuauserv -WarningAction silentlyContinue
        $AutoUpdates = New-Object -ComObject "Microsoft.Update.AutoUpdate"
        if ([environment]::OSVersion.Version.Major -eq "10") {
            Start-Process ms-settings:windowsupdate
        } elseif ([environment]::OSVersion.Version.Major -eq "6") {
            Invoke-Command {wuauclt.exe /detectnow /showautoscan} 
        }
        $AutoUpdates.DetectNow()
    }


    Write-Host "`n`n`tConfiguration Finished." -f Green
    Write-Host "`n`n`tYou may want to:"
    Write-Host "`t1. Move the computer to the Servers OU"
    Write-Host "`t2. Add server to ipam ( vm_ipam.ps1" $ComputerSpecs.name ")"
    Write-host `n`n`n

} else {
    Write-Host Computer Specs not found in $CSV_Deployment_File -f red
    Exit
}



