# REF: https://communities.vmware.com/thread/541573
# REF: https://pubs.vmware.com/vsphere-6-0/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.scheduler.ScheduledTaskManager.html
# REF: https://pubs.vmware.com/vsphere-6-0/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.scheduler.ScheduledTask.html

param(
    [Parameter(Mandatory=$true,Position=0)]
    [string]$VirtualMachine,
    [switch]$Create,
    [switch]$Update,
    [switch]$Remove,
    [string]$ForUser="$($env:username.ToLower())@$($env:userdnsdomain.ToLower())",
    [datetime]$Date = (Get-Date 21:00),
    [string]$Notify,
    [string]$SnapshotName = "Create snapshot for $($ForUser) [$($VirtualMachine)]"
)

Begin
{
    function Get-ScheduledTaskManager([VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl] $VirtualMachine)
    {
        $null = (get-vm $VirtualMachine | Select-Object Uid ) -match "\S+\@(?'viserver'\S+):"
        $ServiceInstance = Get-View -ID "ServiceInstance" -Server $Matches['viserver']
        return (Get-View $ServiceInstance.Content.ScheduledTaskManager -Server $Matches['viserver'])
    }

    function Get-ScheduledSnapshots([VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl] $VirtualMachine, 
        [VMware.Vim.ScheduledTaskManager] $ScheduledTaskManager)
    {
        $ScheduledTasks = @()
        foreach ($Task in $ScheduledTaskManager.ScheduledTask)
        {
            $ScheduledTasks += get-view $Task
        } 
        $ScheduledTasks | Where-Object {$_.Info.Entity -contains $VirtualMachine.Id}
    }

    function New-ScheduledSnapshot([VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl] $VirtualMachine, 
        [VMware.Vim.ScheduledTaskManager] $ScheduledTaskManager)
    {
        $ScheduledTaskSpec = New-Object VMware.Vim.ScheduledTaskSpec
        $ScheduledTaskSpec.Name = $SnapshotName
        $ScheduledTaskSpec.Description = "Scheduled snapshot created by $($env:userdomain)\$($env:username) with Schedule-Snapshot.ps1."
        $ScheduledTaskSpec.Enabled = $true
        if ($Notify)
        {
            [string] $Notification = $Notify
            $ScheduledTaskSpec.Notification = $Notification
        }

        $ScheduledTaskSpec.Scheduler = New-Object VMware.Vim.OnceTaskScheduler
        $ScheduledTaskSpec.Scheduler.runat = $Date.ToUniversalTime()

        $ScheduledTaskSpec.Action = New-Object VMware.Vim.MethodAction
        $ScheduledTaskSpec.Action.Name = "CreateSnapshot_Task"

        $snapDescription = "Scheduled snapshot created by $($env:userdomain)\$($env:username) with Schedule-Snapshot.ps1."
        @($ForUser,$snapDescription,$false,$true) | ForEach-Object{ # $false for memory, $true for quiesce filesystem
            $arg = New-Object VMware.Vim.MethodActionArgument
            $arg.Value = $_
            $ScheduledTaskSpec.Action.Argument += $arg
        }

        Get-View $ScheduledTaskManager.CreateObjectScheduledTask($VirtualMachine.ExtensionData.MoRef, $ScheduledTaskSpec)
        
    }

    function Update-ScheduledSnapshot([VMware.Vim.ScheduledTask] $ScheduledTask)
    {
        $ScheduledTaskSpec = $ScheduledTask.Info
        $ScheduledTaskSpec.Scheduler.runat = $Date.ToUniversalTime()
        $ScheduledTaskSpec.Action = New-Object VMware.Vim.MethodAction
        $ScheduledTaskSpec.Action.Name = "CreateSnapshot_Task"

        $snapDescription = "Scheduled snapshot created by $($env:userdomain)\$($env:username) with Schedule-Snapshot.ps1."
        @($ForUser,$snapDescription,$false,$true) | ForEach-Object{ # $false for memory, $true for quiesce filesystem
            $arg = New-Object VMware.Vim.MethodActionArgument
            $arg.Value = $_
            $ScheduledTaskSpec.Action.Argument += $arg
        }
        
        $ScheduledTask.ReconfigureScheduledTask($ScheduledTaskSpec)
        Get-View $ScheduledTask.MoRef
        
    }

    function Remove-ScheduledSnapshot([VMware.Vim.ScheduledTask] $ScheduledTask)
    {
        $ScheduledTask.RemoveScheduledTask()
    }

}

Process
{
    $VirtualMachineObject = Get-VM $VirtualMachine
    $ScheduledTaskManager = Get-ScheduledTaskManager $VirtualMachineObject
    $VMScheduledSnapshots = Get-ScheduledSnapshots $VirtualMachineObject $ScheduledTaskManager

    if ($Create)
    {
        if ($VMScheduledSnapshots.Info.Name -NotContains $SnapshotName)
        {
            $VMSCheduledSnapshots = New-ScheduledSnapshot $VirtualMachineObject $ScheduledTaskManager
        } 
        else 
        {
            Write-Host "Scheduled task `"$SnapshotName`" already exists." -ForegroundColor Red
        }
    } 
    elseif ($Update)
    {
        if ($VMScheduledSnapshots.Info.Name -Contains $SnapshotName)
        {
            $VMSCheduledSnapshots = Update-ScheduledSnapshot ($VMScheduledSnapshots | Where-Object {$_.Info.Name  -eq $SnapshotName})
        } 
        else 
        {
            Write-Host "Scheduled task `"$SnapshotName`" does not exist." -ForegroundColor Red
        }   
    }
    elseif($Remove)
    {
        if ($VMScheduledSnapshots.Info.Name -Contains $SnapshotName)
        {
            Remove-ScheduledSnapshot ($VMScheduledSnapshots | Where-Object {$_.Info.Name  -eq $SnapshotName})
            $VMScheduledSnapshots = Get-ScheduledSnapshots $VirtualMachineObject (Get-ScheduledTaskManager $VirtualMachineObject)
        }
        else 
        {
            Write-Host "Scheduled task `"$SnapshotName`" does not exist." -ForegroundColor Red
        } 
    } 
}

End
{
    if($VMScheduledSnapshots.Info)
    {
        Write-Output $VMScheduledSnapshots.Info
    }
    else 
    {
        Write-Host "*** No scheduled tasks for $($virtualMachineObject.Name) ***`n" -ForegroundColor DarkYellow
    }
}
