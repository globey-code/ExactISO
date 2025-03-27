param (
    [string]$SourceDrive = "C:\",
    [string]$WorkingDir = "C:\Users\KyleEul\source\repos\ExactISO\ExactISO",
    [string]$ForceBootMode = ""
)

# Normalize source drive path
if ($SourceDrive -notlike "*\") { $SourceDrive += "\" }

# Define paths and variables
$ImageName = "DriveClone"
$WimPath = "$WorkingDir\DriveCapture.wim"
$WinPEPath = "$WorkingDir\WinPE"
$ISOOutput = "$WorkingDir\DriveClone.iso"
$IsBootable = Test-Path "$SourceDrive\Windows\System32\config\SYSTEM"
$IsUEFI = $false

# Determine boot mode (BIOS or UEFI)
if ($ForceBootMode -eq "UEFI") {
    $IsUEFI = $true
} elseif ($ForceBootMode -eq "BIOS") {
    $IsUEFI = $false
} else {
    $firmware = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction SilentlyContinue
    if ($firmware.PEFirmwareType -eq 2) {
        $IsUEFI = $true
    }
}

# Step 1: Capture the source drive into a WIM file
Write-Host "`n[STEP 1] Capturing image using DISM..."
dism /Capture-Image /ImageFile:$WimPath /CaptureDir:$SourceDrive /Name:$ImageName /Compress:maximum /CheckIntegrity

# Step 2: Prepare Windows PE environment
Write-Host "`n[STEP 2] Preparing Windows PE environment..."
$ADKPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit"
$WinPEAMD64 = "$ADKPath\Windows Preinstallation Environment\amd64"
$WinPEMedia = "$WinPEAMD64\Media"
$WinPEFW = "$WinPEAMD64\en-us\winpe.wim"

# Create WinPE working directory and copy files
New-Item -ItemType Directory -Force -Path $WinPEPath | Out-Null
Copy-Item -Path $WinPEMedia -Destination $WinPEPath -Recurse -Force
Copy-Item -Path $WinPEFW -Destination "$WinPEPath\sources\boot.wim" -Force

# Mount WinPE WIM
$MountPath = "$WorkingDir\Mount"
New-Item -ItemType Directory -Force -Path $MountPath | Out-Null
dism /Mount-Image /ImageFile:"$WinPEPath\sources\boot.wim" /Index:1 /MountDir:$MountPath

# Add captured WIM to WinPE
New-Item -ItemType Directory -Force -Path "$MountPath\sources" | Out-Null
Copy-Item -Path $WimPath -Destination "$MountPath\sources\DriveCapture.wim" -Force

# Create restore script for cloning
$RestoreScript = @"
@echo off
echo [INFO] Listing available disks...
diskpart /s listdisk.txt
echo.
echo Please select the target disk number:
set /p DiskNumber=
echo.
echo [INFO] Creating partitions...
if "$IsBootable" == "True" (
    if "$IsUEFI" == "True" (
        echo select disk %DiskNumber%
        echo clean
        echo convert gpt
        echo create partition efi size=100
        echo format quick fs=fat32 label="System"
        echo assign letter=S
        echo create partition primary
        echo format quick fs=ntfs label="OS"
        echo assign letter=X
        echo exit
    ) else (
        echo select disk %DiskNumber%
        echo clean
        echo create partition primary
        echo format quick fs=ntfs label="OS"
        echo assign letter=X
        echo active
        echo exit
    )
) else (
    echo select disk %DiskNumber%
    echo clean
    echo create partition primary
    echo format quick fs=ntfs label="Data"
    echo assign letter=X
    echo exit
)
diskpart /s createpart.txt

echo [INFO] Applying image to target drive...
dism /Apply-Image /ImageFile:\sources\DriveCapture.wim /Index:1 /ApplyDir:X:\

if "$IsBootable" == "True" (
    echo [INFO] Configuring boot loader...
    if "$IsUEFI" == "True" (
        bcdboot X:\Windows /s S: /f UEFI
    ) else (
        bcdboot X:\Windows /s X: /f BIOS
    )
)

echo [DONE] Cloning completed successfully.
pause
"@

# Save the restore script and diskpart script
$RestoreScript | Out-File -FilePath "$MountPath\restore.bat" -Encoding ASCII
"list disk" | Out-File -FilePath "$MountPath\listdisk.txt" -Encoding ASCII

# Unmount WinPE WIM with changes
dism /Unmount-Image /MountDir:$MountPath /Commit

# Step 3: Build the ISO
Write-Host "`n[STEP 3] Building ISO with oscdimg..."
$OscdimgPath = "$ADKPath\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
& "$OscdimgPath" -b"$WinPEPath\fwfiles\etfsboot.com" -u2 -udfver102 -lDriveClone -o -h "$WinPEPath" "$ISOOutput"

# Output completion message
Write-Host "`n[DONE] ISO created at: $ISOOutput"
Write-Host "[INFO] ISO size: $((Get-Item $ISOOutput).Length / 1MB) MB"