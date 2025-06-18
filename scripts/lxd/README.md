# Bowtie LXD Deployment

Steps for deploying a Bowtie Controller on an LXD environment.

## Setup process

### 1. Prepare the LXD environment

```bash
# Update the system
sudo apt update && sudo apt upgrade -y

# Check LXC version
lxc --version

# If version is 4.0.10, upgrade to 5.21
sudo snap refresh lxd --channel=5.21/stable

# Verify the upgrade
lxc --version

# Initialize LXD (use defaults except increase loop device size)
lxd init

# Check network configuration
lxc network list

# Note the IPv4 address of the new bridge interface (e.g., 10.157.207.1/24)
```

### 2. Configure cloud-init and network-config

[Create a cloud-init configuration file](https://github.com/bowtieworks/deployment-tools/tree/main/tools/cloud-init-generator) and save it as (`cloud-init.yaml`) on your host VM.

If needing static IP assignment (no DHCP available), create a network configuration file at `network-config.yaml`:

```yaml
version: 2
ethernets:
  enp5s0:
    dhcp4: false
    addresses:
      - 10.157.207.100/24 # Replace with static IP from the CIDR assigned to the bridge interface
    gateway4: 10.157.207.1 # Replace with gateway assigned to bridge interface
    nameservers:
      addresses:
        - 1.1.1.1 # Replace with preferred resolver to be used
```

### 3. Download and prepare the Bowtie image

```bash
# Download the latest Bowtie controller image (https://api.bowtie.works/platforms/KVM)
# Be sure to use "qcow-efi"
wget -O bowtie-controller-qcow-efi-25.06.002.qcow2.gz "https://api.bowtie.works/api/v1/package/4657/download/"

# Decompress the image
gunzip bowtie-controller-qcow-efi-25.06.002.qcow2.gz
```

Create a metadata file (`metadata.yaml`):

```yaml
architecture: x86_64
creation_date: 1743127808
properties:
  description: Bowtie Controller
  os: linux
  release: 25.06.002
```

Package and import the image:

```bash
# Create a metadata archive
tar -cf metadata.tar metadata.yaml

# Import the VM image
lxc image import metadata.tar bowtie-controller-qcow-efi-25.06.002.qcow2 --alias bowtie-controller-image
```

### 4. Create and configure the VM

```bash
# Initialize the VM with 2 CPUs and 4GB memory
lxc init bowtie-controller-image bowtie-vm --vm -c limits.cpu=2 -c limits.memory=4GB -s default

# Disable secure boot
lxc config set bowtie-vm security.secureboot false

# Apply cloud-init configuration
incus config set bowtie-vm cloud-init.user-data - < user-data.yaml

# Apply network configuration (if using static IP)
lxc config set bowtie-vm cloud-init.network-config - < network-config.yaml

# Attach cloud-init disk to devices
lxc config device add bowtie-vm config disk source=cloud-init:config

# Validate VM configuration
lxc config show bowtie-vm
```

### 5. Start and access the VM

#### Option A: With external port forwarding

```bash
# Start the VM
lxc start bowtie-vm

# Configure ports on external firewall/ingress
```

#### Option B: With host-level port forwarding

Assign the static IP to the device:

```bash
# Replace with static IP to be assigned to the instance
lxc profile device set default eth0 ipv4.address=10.157.207.100
```

Configure port forwarding rules:

```bash
# Find the host's internal IP address (10.128.0.4 in this case)
ip route show
# Example output:
# default via 10.128.0.1 dev ens4 proto dhcp src 10.128.0.4 metric 100

# Set up TCP proxy for HTTPS (443)
lxc config device add bowtie-vm https-tcp proxy listen=tcp:10.128.0.4:443 connect=tcp:10.157.207.100:443 nat=true

# Set up UDP proxy for WG (443)
lxc config device add bowtie-vm wg-udp proxy listen=udp:10.128.0.4:443 connect=udp:10.157.207.100:443 nat=true

# Optional: Set up SSH proxy (port 2222)
lxc config device add bowtie-vm ssh proxy listen=tcp:10.128.0.4:2222 connect=tcp:10.157.207.100:22 nat=true

# Start the VM
lxc start bowtie-vm
```

## Verification and troubleshooting

After deployment, you can verify the VM status with:

```bash
# Check VM status
lxc list

# View serial console
lxc console bowtie-vm
```
