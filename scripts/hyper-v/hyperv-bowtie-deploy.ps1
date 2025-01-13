 # Define parameters
$isoDir = "C:\bowtie-iso"  
$outputIso = "C:\bowtie.iso"
$vhdxPath = "C:\Users\Administrator\Downloads\nixos-hyperv-x86_64-linux.vhdx"
$vmName = "BowtieController"
$switchName = "VirtualNatSwitch"
$userDataPath = "C:\Users\Administrator\Documents\cloud-init.yaml" 
$enablePortForwarding = $true
$enableSSH = $true
$vmCores = 4
$vmMemory = 4GB
$diskSize = 60GB

# Network configuration for NAT
$natNetworkName = "NATNetwork"
$natGatewayIP = "192.168.100.1"
$vmStaticIP = "192.168.100.2/24"
$natSubnetPrefix = "192.168.100.0/24"
$nameServer = "8.8.8.8"

# Function to check and set permissions
function Set-VHDPermissions {
   param($Path)
   Write-Host "Setting permissions for VHDX file..."
   $acl = Get-Acl $Path
   $identity = "NT VIRTUAL MACHINE\Virtual Machines"
   $fileSystemRights = "Read,Write"
   $type = "Allow"
   $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $fileSystemRights, $type)
   $acl.AddAccessRule($rule)
   Set-Acl -Path $Path -AclObject $acl
}

# Setup NAT networking
Write-Host "Configuring NAT networking..."
if (!(Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)) {
   Write-Host "Creating new NAT switch..."
   New-VMSwitch -SwitchName $switchName -SwitchType Internal
}

# Configure NAT gateway IP if not exists
$natAdapter = Get-NetAdapter -Name "vEthernet ($switchName)" -ErrorAction SilentlyContinue
if (!(Get-NetIPAddress -IPAddress $natGatewayIP -ErrorAction SilentlyContinue)) {
   Write-Host "Configuring NAT gateway IP..."
   New-NetIPAddress -IPAddress $natGatewayIP -PrefixLength 24 -InterfaceAlias "vEthernet ($switchName)"
}

# Check and remove existing NAT if needed
$existingNat = Get-NetNat -Name $natNetworkName -ErrorAction SilentlyContinue
if ($existingNat) {
    Write-Host "Removing existing NAT network..."
    Remove-NetNat -Name $natNetworkName -Confirm:$false
}

# Configure NAT network
Write-Host "Creating NAT network..."
try {
    New-NetNat -Name $natNetworkName -InternalIPInterfaceAddressPrefix $natSubnetPrefix -ErrorAction Stop
} catch {
    Write-Host "Error creating NAT network: $_"
    Write-Host "Current NAT configurations:"
    Get-NetNat | Format-Table Name, InternalIPInterfaceAddressPrefix
    exit
}

# Configure port forwarding rules if enabled
if ($enablePortForwarding) {
    Write-Host "Setting up port forwarding rules..."
    $nat = Get-NetNat -Name $natNetworkName -ErrorAction SilentlyContinue
    if (!$nat) {
        Write-Host "Error: NAT network '$natNetworkName' not found. Cannot configure port forwarding."
        exit
    }

    # Strip the subnet mask for NAT rules
    $internalIP = $vmStaticIP.Split('/')[0]

    # Define port forwarding rules
    $portMappings = @(
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "TCP" },
        @{ ExternalPort = 443; InternalPort = 443; Protocol = "UDP" }
    )

    # Add SSH port forwarding if enabled
    if ($enableSSH) {
        $portMappings += @{ ExternalPort = 2222; InternalPort = 22; Protocol = "TCP" }
    }

    foreach ($mapping in $portMappings) {
        $existingMapping = Get-NetNatStaticMapping -NatName $natNetworkName -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.ExternalPort -eq $mapping.ExternalPort -and 
                $_.Protocol -eq $mapping.Protocol 
            }
        
        if (!$existingMapping) {
            Write-Host "Adding port forwarding rule: External ${mapping.Protocol}:$($mapping.ExternalPort) -> Internal ${mapping.Protocol}:$($mapping.InternalPort)..."
            try {
                Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0" `
                    -ExternalPort $mapping.ExternalPort `
                    -Protocol $mapping.Protocol `
                    -InternalIPAddress $internalIP `
                    -InternalPort $mapping.InternalPort `
                    -NatName $natNetworkName -ErrorAction Stop
            } catch {
                Write-Host "Error adding port forwarding rule: $_"
            }
        }
    }
} else {
    Write-Host "Port forwarding is disabled. Skipping port forwarding setup..."
}

# Verify VHDX exists and set permissions
if (Test-Path $vhdxPath) {
   Write-Host "VHDX file found. Setting permissions..."
   Set-VHDPermissions $vhdxPath
} else {
   Write-Host "Error: VHDX file not found at $vhdxPath"
   exit
}

# Verify user-data file exists
if (!(Test-Path $userDataPath)) {
   Write-Host "Error: user-data file not found at $userDataPath"
   exit
}

# Create directory for ISO contents
Write-Host "Creating ISO directory..."
New-Item -ItemType Directory -Path $isoDir -Force

# Copy the external user-data file
Write-Host "Copying user-data file..."
Copy-Item $userDataPath -Destination "$isoDir\user-data"

# Create minimal meta-data file
Write-Host "Creating meta-data file..."
$metaDataContent = @"
"@
Set-Content -Path "$isoDir\meta-data" -Value $metaDataContent

# Create network-config file
Write-Host "Creating network-config file..."
$networkConfig = @"
# Network configuration
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - $vmStaticIP
      gateway4: $natGatewayIP
      nameservers:
        addresses: [$nameServer]
"@
Set-Content -Path "$isoDir\network-config" -Value $networkConfig

# Create the ISO using oscdimg
Write-Host "Creating cloud-init ISO..."
$oscdimgPath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
& $oscdimgPath -o -m -n -d -lCIDATA $isoDir $outputIso

# Create the VM with elevated permissions
Write-Host "Creating VM..."
$vm = New-VM -Name $vmName -MemoryStartupBytes $vmMemory -VHDPath $vhdxPath -Generation 2 -SwitchName $switchName

if ($vm) {
   # Configure VM settings
   Write-Host "Configuring VM settings..."
   Set-VMProcessor -VMName $vmName -Count $vmCores
   Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes $vmMemory
   
   Write-Host "Resizing VHD..."
   Resize-VHD -Path $vhdxPath -SizeBytes $diskSize
   
   # Add the DVD drive with cloud-init ISO
   Write-Host "Adding cloud-init ISO..."
   Add-VMDvdDrive -VMName $vmName -Path $outputIso

   # Disable Secure Boot
   Write-Host "Disabling Secure Boot..."
   Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

   # Set boot order (Hard Drive first, then DVD, then Network)
   Write-Host "Setting boot order..."
   $vmDvd = Get-VMDvdDrive -VMName $vmName
   $vmHdd = Get-VMHardDiskDrive -VMName $vmName
   $vmNetwork = Get-VMNetworkAdapter -VMName $vmName
   Set-VMFirmware -VMName $vmName -FirstBootDevice $vmHdd
   
   Write-Host "VM setup complete! You can now start the VM."
} else {
   Write-Host "Error: Failed to create VM. Please check permissions and paths."
} 
