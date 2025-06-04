<#
.SYNOPSIS
    Deploys a Bowtie Controller as a VM on Hyper-V. Comes with support for NAT or external switch networking.

.DESCRIPTION
    Deploys the VM with three modes:
    1. NAT with static IP (cloud-init) and host-level port forwarding.
    2. External switch with static IP (cloud-init).
    3. External switch with DHCP (no cloud-init).
    Always decompresses the .gz file, overwriting the VHDX. Logs to 'deploy-vm.log'.

.PARAMETER gzPath
    Path to the compressed VHDX (.gz) file.
.PARAMETER vhdxPath
    Destination path for decompressed VHDX.
.PARAMETER vmName
    Name of the VM.
.PARAMETER vmCores
    CPU cores (1-16, default 4).
.PARAMETER vmMemory
    Memory in bytes (1GB-16GB, default 4GB).
.PARAMETER diskSize
    VHDX size in bytes (8GB-1TB, default 64GB).
.PARAMETER isoDir
    Directory for cloud-init ISO (default: C:\Temp\bowtie-iso).
.PARAMETER outputIso
    Path for cloud-init ISO (default: C:\Temp\bowtie.iso).
.PARAMETER networkMode
    Network mode: 'nat-static-portfwd', 'ext-switch-static', or 'ext-switch-dhcp'.
.PARAMETER existingSwitchName
    Name of existing virtual switch (for ext-switch modes).
.PARAMETER staticIP
    Static IP in CIDR (e.g., "192.168.100.222/24" for NAT, "10.0.1.222/24" for ext-switch).
.PARAMETER natNetworkName
    NAT network name (for nat-static-portfwd, default: PrivateNAT).
.PARAMETER natSwitchName
    NAT switch name (for nat-static-portfwd, default: VirtualNatSwitch).
.PARAMETER natGatewayIP
    NAT gateway IP (for nat-static-portfwd, default: 192.168.100.1).
.PARAMETER natSubnetPrefix
    NAT subnet (for nat-static-portfwd, default: 192.168.100.0/24).
.PARAMETER nameServer
    DNS server IP (default: 8.8.8.8).

.EXAMPLE
    # NAT with static IP and port forwarding (ie metal on AWS)
    .\bowtie-hyperv.ps1 -gzPath "C:\Downloads\bowtie.vhdx.gz" -vhdxPath "C:\VMs\bowtie.vhdx" -vmName "BowtieController" -networkMode nat-static-portfwd -staticIP "192.168.100.222/24"

.EXAMPLE
    # External switch with static IP (on-premises)
    .\bowtie-hyperv.ps1 -gzPath "C:\Downloads\bowtie.vhdx.gz" -vhdxPath "C:\VMs\bowtie.vhdx" -vmName "BowtieController" -networkMode ext-switch-static -existingSwitchName "External Virtual Switch" -staticIP "10.0.1.222/24"

.EXAMPLE
    # External switch with DHCP (on-premises)
    .\bowtie-hyperv.ps1 -gzPath "C:\Downloads\bowtie.vhdx.gz" -vhdxPath "C:\VMs\bowtie.vhdx" -vmName "BowtieController" -networkMode ext-switch-dhcp -existingSwitchName "External Virtual Switch"

.NOTES
    - Requires Hyper-V and Administrator privileges.
    - Windows ADK (oscdimg.exe) needed for cloud-init ISO (modes 1 and 2).
    - Logs to 'deploy-vm.log'.
    - For cloud-based metal, use nat-static-portfwd. For on-premises, use ext-switch-static or ext-switch-dhcp; port forwarding should be handled at the network edge.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$gzPath,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path (Split-Path $_ -Parent) -PathType Container})]
    [string]$vhdxPath,

    [Parameter(Mandatory=$true)]
    [string]$vmName,

    [ValidateRange(1,16)]
    [int]$vmCores = 4,

    [ValidateRange(1GB,16GB)]
    [long]$vmMemory = 4GB,

    [ValidateRange(8GB,1TB)]
    [long]$diskSize = 64GB,

    [string]$isoDir = "C:\Temp\bowtie-iso",

    [string]$outputIso = "C:\Temp\bowtie.iso",

    [Parameter(Mandatory=$true)]
    [ValidateSet("nat-static-portfwd", "ext-switch-static", "ext-switch-dhcp")]
    [string]$networkMode,

    [string]$existingSwitchName,

    [string]$staticIP,

    [string]$natNetworkName = "PrivateNAT",

    [string]$natSwitchName = "VirtualNatSwitch",

    [string]$natGatewayIP = "192.168.100.1",

    [string]$natSubnetPrefix = "192.168.100.0/24",

    [string]$nameServer = "8.8.8.8"
)

# Logging function
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath "deploy-vm.log" -Append
    if ($Level -eq "ERROR") { Write-Error $Message }
    elseif ($Level -eq "WARNING") { Write-Warning $Message }
    else { Write-Verbose $Message }
}

# Cleanup function
function Clean-Up {
    param($vmName, $isoDir, $vhdxPath, $natNetworkName)
    Write-Host "Cleaning up resources..."
    Write-Log "Cleaning up resources..."
    if (Test-Path $isoDir) { Remove-Item $isoDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $vhdxPath) { Remove-Item $vhdxPath -Force -ErrorAction SilentlyContinue }
    if (Get-NetNat -Name $natNetworkName -ErrorAction SilentlyContinue) {
        Remove-NetNat -Name $natNetworkName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

# Set VHD permissions
function Set-VHDPermissions {
    param($Path)
    try {
        $acl = Get-Acl $Path -ErrorAction Stop
        $identity = "NT VIRTUAL MACHINE\Virtual Machines"
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, "ReadAndExecute,Write", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
        Write-Log "Permissions set on ${Path}."
    } catch {
        Write-Log "Failed to set permissions on ${Path}: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Validate inputs
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: Run as Administrator."
    Write-Log "Script requires Administrator privileges." -Level "ERROR"
    exit 1
}

if ($networkMode -in "ext-switch-static", "ext-switch-dhcp" -and -not $existingSwitchName) {
    Write-Host "Error: existingSwitchName required for ${networkMode}."
    Write-Log "existingSwitchName is required for ${networkMode}." -Level "ERROR"
    exit 1
}

if ($networkMode -in "nat-static-portfwd", "ext-switch-static" -and -not ($staticIP -match "^\d+\.\d+\.\d+\.\d+/\d+$")) {
    Write-Host "Error: Valid staticIP required for ${networkMode}."
    Write-Log "Valid staticIP (e.g., 192.168.100.222/24) required for ${networkMode}." -Level "ERROR"
    exit 1
}

# Decompress GZ file
Write-Host "Decompressing VHDX..."
Write-Log "Removing existing VHDX at ${vhdxPath}..."
try {
    if (Test-Path $vhdxPath) { Remove-Item $vhdxPath -Force -ErrorAction Stop }
    Write-Log "Decompressing ${gzPath} to ${vhdxPath}..."
    $in = [IO.Compression.GzipStream]::new([IO.File]::OpenRead($gzPath), [IO.Compression.CompressionMode]::Decompress)
    $out = [IO.File]::Create($vhdxPath)
    $in.CopyTo($out)
    $in.Close(); $out.Close()
    Write-Log "Decompression complete."
} catch {
    Write-Host "Error: Decompression failed."
    Write-Log "Decompression failed: $($_.Exception.Message)" -Level "ERROR"
    Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
    exit 1
}

Set-VHDPermissions -Path $vhdxPath

# Configure network
Write-Host "Configuring network..."
$switchName = $null
if ($networkMode -eq "nat-static-portfwd") {
    try {
        # Ensure WinNat service is running
        if ((Get-Service -Name WinNat).Status -ne "Running") {
            Start-Service -Name WinNat -ErrorAction Stop
            Write-Log "Started WinNat service."
        }
        if (!(Get-VMSwitch -Name $natSwitchName -ErrorAction SilentlyContinue)) {
            Write-Log "Creating NAT switch ${natSwitchName}..."
            New-VMSwitch -SwitchName $natSwitchName -SwitchType Internal -ErrorAction Stop
        }
        $timeout = 10
        while ($timeout -gt 0 -and !(Get-NetAdapter -Name "vEthernet ($natSwitchName)" -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 1
            $timeout--
        }
        if ($timeout -eq 0) {
            Write-Host "Error: NAT switch setup timed out."
            Write-Log "Timed out waiting for vEthernet (${natSwitchName})." -Level "ERROR"
            Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
            exit 1
        }
        if (!(Get-NetIPAddress -IPAddress $natGatewayIP -ErrorAction SilentlyContinue)) {
            New-NetIPAddress -IPAddress $natGatewayIP -PrefixLength 24 -InterfaceAlias "vEthernet ($natSwitchName)" -ErrorAction Stop
        }
        if (Get-NetNat -Name $natNetworkName -ErrorAction SilentlyContinue) {
            Remove-NetNat -Name $natNetworkName -Confirm:$false -ErrorAction Stop
        }
        New-NetNat -Name $natNetworkName -InternalIPInterfaceAddressPrefix $natSubnetPrefix -ErrorAction Stop
        $switchName = $natSwitchName
        Write-Log "NAT network configured."
    } catch {
        Write-Host "Error: NAT setup failed."
        Write-Log "NAT setup failed: $($_.Exception.Message)" -Level "ERROR"
        Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
        exit 1
    }
} else {
    try {
        $switch = Get-VMSwitch -Name $existingSwitchName -ErrorAction SilentlyContinue
        if (!$switch) {
            Write-Host "Error: Switch '${existingSwitchName}' not found."
            Write-Log "Switch '${existingSwitchName}' not found." -Level "ERROR"
            Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
            exit 1
        }
        $switchName = $existingSwitchName
        Write-Log "Using switch ${existingSwitchName}."
    } catch {
        Write-Host "Error: Switch setup failed."
        Write-Log "Switch setup failed: $($_.Exception.Message)" -Level "ERROR"
        Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
        exit 1
    }
}

# Configure port forwarding for NAT mode
if ($networkMode -eq "nat-static-portfwd") {
    Write-Host "Setting up port forwarding..."
    $internalIP = $staticIP.Split('/')[0]
    $portMappings = @(
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "TCP" },
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "UDP" },
        @{ ExternalPort = 80; InternalPort = 80; Protocol = "TCP" }
    )
    try {
        foreach ($mapping in $portMappings) {
            $existing = Get-NetNatStaticMapping -NatName $natNetworkName -ErrorAction SilentlyContinue |
                Where-Object { $_.ExternalPort -eq $mapping.ExternalPort -and $_.Protocol -eq $mapping.Protocol }
            if ($existing) {
                Remove-NetNatStaticMapping -NatName $natNetworkName -ExternalPort $mapping.ExternalPort -Protocol $mapping.Protocol -ErrorAction Stop
            }
            Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0" `
                -ExternalPort $mapping.ExternalPort `
                -Protocol $mapping.Protocol `
                -InternalIPAddress $internalIP `
                -InternalPort $mapping.InternalPort `
                -NatName $natNetworkName -ErrorAction Stop
            Write-Log "Added NAT mapping: $($mapping.ExternalPort)/$($mapping.Protocol) to ${internalIP}:$($mapping.InternalPort)"
        }
        $natMappings = Get-NetNatStaticMapping -NatName $natNetworkName
        Write-Log "NAT mappings:`n$($natMappings | Format-Table | Out-String)"
    } catch {
        Write-Host "Warning: Port forwarding setup failed."
        Write-Log "Port forwarding failed: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Create cloud-init ISO if needed
if ($networkMode -in "nat-static-portfwd", "ext-switch-static") {
    Write-Host "Creating cloud-init ISO..."
    try {
        New-Item -Path $isoDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        $networkConfig = @"
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - $staticIP
      gateway4: $natGatewayIP
      nameservers:
        addresses: [$nameServer]
"@
        Set-Content "$isoDir\user-data" "`n" -ErrorAction Stop
        Set-Content "$isoDir\meta-data" "`n" -ErrorAction Stop
        Set-Content "$isoDir\network-config" $networkConfig -ErrorAction Stop
        $oscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        if (!(Test-Path $oscdimgPath)) {
            Write-Host "Error: oscdimg.exe not found."
            Write-Log "oscdimg.exe not found: ${oscdimgPath}" -Level "ERROR"
            Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
            exit 1
        }
        & $oscdimgPath -o -m -n -d -lCIDATA $isoDir $outputIso
        if (!(Test-Path $outputIso)) {
            Write-Host "Error: Cloud-init ISO creation failed."
            Write-Log "Cloud-init ISO creation failed." -Level "ERROR"
            Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
            exit 1
        }
        Write-Log "Cloud-init ISO created at ${outputIso}."
    } catch {
        Write-Host "Error: Cloud-init ISO failed."
        Write-Log "Cloud-init ISO failed: $($_.Exception.Message)" -Level "ERROR"
        Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
        exit 1
    }
}

# Create VM
Write-Host "Creating VM..."
try {
    $vmParams = @{
        Name = $vmName
        MemoryStartupBytes = $vmMemory
        VHDPath = $vhdxPath
        Generation = 2
        SwitchName = $switchName
    }
    New-VM @vmParams -ErrorAction Stop | Out-Null
    Write-Log "VM created: ${vmName}"
} catch {
    Write-Host "Error: VM creation failed."
    Write-Log "VM creation failed: $($_.Exception.Message)" -Level "ERROR"
    Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
    exit 1
}

# Configure VM
Write-Host "Configuring VM..."
try {
    Set-VMProcessor -VMName $vmName -Count $vmCores -ErrorAction Stop
    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes $vmMemory -ErrorAction Stop
    $vhdInfo = Get-VHD -Path $vhdxPath -ErrorAction Stop
    if ($vhdInfo.Size -lt $diskSize) {
        Write-Log "Resizing VHD to $diskSize bytes..."
        Resize-VHD -Path $vhdxPath -SizeBytes $diskSize -ErrorAction Stop
    }
    Set-VMFirmware -VMName $vmName -EnableSecureBoot Off -ErrorAction Stop
    if ($networkMode -in "nat-static-portfwd", "ext-switch-static" -and (Test-Path $outputIso)) {
        Add-VMDvdDrive -VMName $vmName -Path $outputIso -ErrorAction Stop
        $vmHdd = Get-VMHardDiskDrive -VMName $vmName -ErrorAction Stop
        Set-VMFirmware -VMName $vmName -FirstBootDevice $vmHdd -ErrorAction Stop
        Write-Log "Attached cloud-init ISO."
    }
} catch {
    Write-Host "Error: VM configuration failed."
    Write-Log "VM configuration failed: $($_.Exception.Message)" -Level "ERROR"
    Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
    exit 1
}

# Configure port forwarding for NAT mode
if ($networkMode -eq "nat-static-portfwd") {
    Write-Host "Setting up port forwarding..."
    $internalIP = $staticIP.Split('/')[0]
    $portMappings = @(
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "TCP" },
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "UDP" },
        @{ ExternalPort = 80; InternalPort = 80; Protocol = "TCP" }
    )
    try {
        foreach ($mapping in $portMappings) {
            $existing = Get-NetNatStaticMapping -NatName $natNetworkName -ErrorAction SilentlyContinue |
                Where-Object { $_.ExternalPort -eq $mapping.ExternalPort -and $_.Protocol -eq $mapping.Protocol }
            if ($existing) { continue }
            Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0" `
                -ExternalPort $mapping.ExternalPort `
                -Protocol $mapping.Protocol `
                -InternalIPAddress $internalIP `
                -InternalPort $mapping.InternalPort `
                -NatName $natNetworkName -ErrorAction Stop
            Write-Log "Added NAT mapping: $($mapping.ExternalPort)/$($mapping.Protocol) to ${internalIP}:$($mapping.InternalPort)"
        }
    } catch {
        Write-Host "Warning: Port forwarding setup failed."
        Write-Log "Port forwarding failed: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Start VM
Write-Host "Starting VM..."
try {
    Start-VM -Name $vmName -ErrorAction Stop
    Write-Host "VM ${vmName} started successfully."
    Write-Log "VM ${vmName} started."
} catch {
    Write-Host "Error: Failed to start VM."
    Write-Log "Failed to start VM: $($_.Exception.Message)" -Level "ERROR"
    Clean-Up -vmName $vmName -isoDir $isoDir -vhdxPath $vhdxPath -natNetworkName $natNetworkName
    exit 1
}

# Clean up temporary files
try {
    if (Test-Path $isoDir) { Remove-Item $isoDir -Recurse -Force -ErrorAction Stop }
    Write-Log "Temporary files cleaned up."
} catch {
    Write-Log "Cleanup failed: $($_.Exception.Message)" -Level "WARNING"
}