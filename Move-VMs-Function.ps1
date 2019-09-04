Function Move-VMs
{
    Param(
    [string]$SourceDatastore,
        [string]$DestinationDatastore,
        [int]$MinumumFreeGB=475,
        [switch]$Move
    )

    $SourceDatastoreObject = Get-Datastore $SourceDatastore
    $DestinationDatastoreObject = Get-Datastore $DestinationDatastore

    $MaxVMSize = [int]$DestinationDatastoreObject.FreeSpaceGB - $MinumumFreeGB
    $VMTotalGB = 0 
    $VMToMove = @()
    $VMMoved = @()

    Write-Host "Copying up to $($MaxVMSize)GB to $DestinationDatastore" -ForegroundColor Green
    foreach ($VM in ($SourceDatastoreObject | Get-VM))
    {
        
        if (($VMTotalGB + $VM.ProvisionedSpaceGB) -lt $MaxVMSize)
        {
            Write-Host "`t$($VM.Name)`t$([int]$VM.ProvisionedSpaceGB)GB" -ForegroundColor Yellow
            $VMToMove += $VM
            $VMTotalGB += $VM.ProvisionedSpaceGB
        }
    }

    Write-Host -NoNewline "`nFound $($VmToMove.Count) VMs totaling " -ForegroundColor Cyan
    Write-Host -NoNewLine "$([int]$VMTotalGB) GB`n" -ForegroundColor Yellow

    if ($Move)
    {
        foreach ($VM in $VMToMove)
        {
            Write-Host "Moving $($VM.Name)" -ForegroundColor Magenta
            $VMMoved += Move-VM -VM $VM -Datastore $DestinationDatastoreObject -VMotionPriority High -DiskStorageFormat EagerZeroedThick
        }
    }

    $VMMoved
}