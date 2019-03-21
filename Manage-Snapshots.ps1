param(
    [Parameter(Mandatory = $True,Position=0)]
    [string[]]$VirtualMachines,
    [string]$description = "Created by $($env:userdomain)\$($env:username) with Manage-Snapshots.ps1.",
    [switch]$Create,
    [switch]$Delete,
    [string]$SnapshotName
)

#region Begin
Begin
{
    function CheckVIServerConnection()
    {
        if ($global:DefaultViServers.Count) {
            return $true
        } else {
            write-host "`n`nNot connected to a vCenter!" -f red
            return $false
        }
    }

    function CreateSnapshot($VMList, $SnapshotName)
    {
        foreach ($VM in $VMList) {
            $snapshot = New-Snapshot $VM -name $SnapshotName -description $description -Quiesce -WarningAction SilentlyContinue
            if ($snapshot)
            {
                write-host "Created snapshot $SnapshotName on $VM" -f green
            }
        }
    }

    function DeleteSnaphots($VMList, $SnapshotName)
    {
        foreach ($VM in $VMList) {
            $snapshot = Get-Snapshot $VM -name $SnapshotName -EA SilentlyContinue
            if ($snapshot) {
                write-host "********** DELETE **********" -f red
                write-host "VM Name: $VM" -f red
                write-host "Snapshot Name:" $SnapshotName -f red
                $remove_snapshot = Remove-Snapshot $snapshot -Confirm:$true
                write-host "`n`n"
            } else {
                write-host "Snapshot '$SnapshotName' not found." -f magenta
            }
        }
    }

    function ListSnapshots($VMList)
    {
        $snapshots = @()
        foreach ($VM in $VMList) {
            $snapshot = Get-Snapshot $VM | Select-Object name,id,@{L="Created";E={$_.Created.toString("d")}},@{L="SizeGB";E={$_.sizegb.toString("#.##")}},Description
            foreach($snap in $snapshot) {
                $snapshot_PSO = [PSCustomObject]@{
                    SnapshotName = $snap.name
                    vmName = $VM
                    SnapshotID = $snap.id
                    Created = $snap.Created
                    SizeGB = $snap.sizegb
                    Description = $snap.description
                }
                $snapshots += $snapshot_PSO
            }
        }
        if ($snapshots) {
            write-output $snapshots 
        } else {
            write-host "`n`nNo snapshots for $VMList.`n`n" -f red
        }
    }
}
#endregion Begin

Process
{
    if (CheckVIServerConnection)
    {
        if ($Create)
        {
            CreateSnapshot $VirtualMachines $SnapshotName
        }
        elseif ($Delete)
        {
            DeleteSnaphots $VirtualMachines $SnapshotName
        }
        else
        {
            ListSnapshots $VirtualMachines
        }
    }
}
