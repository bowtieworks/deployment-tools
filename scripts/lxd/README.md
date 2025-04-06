# Bowtie LXD Deployment

Steps for deploying a Bowtie controller on LXD.

## Setup Process

### 1. Prepare the LXD Environment

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

### 2. Configure Cloud-Init and Network-Config

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

If port forwarding is required on the host VM, set a static IP in the default profile:

```bash
# Replace with static IP to be assigned to the instance
lxc profile device set default eth0 ipv4.address=10.157.207.100
```

### 3. Download and Prepare the Bowtie Image

```bash
# Download the latest Bowtie controller image
wget -O bowtie-controller-qcow-efi-25.03.003.qcow2.gz https://api.bowtie.works/api/v1/package/4337/download/

# Decompress the image
gunzip bowtie-controller-qcow-efi-25.03.003.qcow2.gz
```

Create a metadata file (`metadata.yaml`):

```yaml
architecture: x86_64
creation_date: 1743127808
properties:
  description: Bowtie Controller
  os: linux
  release: 25.03.03
```

Package and import the image:

```bash
# Create a metadata archive
tar -cf metadata.tar metadata.yaml

# Import the VM image
lxc image import metadata.tar bowtie-controller-qcow-efi-25.03.003.qcow2 --alias bowtie
```

### 4. Create and Configure the VM

```bash
# Initialize the VM with 2 CPUs and 4GB memory
lxc init bowtie bowtie-vm --vm -c limits.cpu=2 -c limits.memory=4GB -s default

# Disable secure boot
lxc config set bowtie-vm security.secureboot false

# Apply cloud-init configuration
lxc config set bowtie-vm cloud-init.user-data - < cloud-init.yaml

# Apply network configuration (if using static IP)
lxc config set bowtie-vm cloud-init.network-config - < network-config.yaml

# Attach cloud-init disk to devices
lxc config device add bowtie-vm config disk source=cloud-init:config

# Validate VM configuration
lxc config show bowtie-vm
```

### 5. Start and Access the VM

#### Option A: With External Port Forwarding

```bash
# Start the VM
lxc start bowtie-vm

# Configure ports on external firewall/ingress
```

#### Option B: With Host VM Port Forwarding

```bash
# Find the host's internal IP address (10.128.0.4 in this case)
ip route show
# Example output:
# default via 10.128.0.1 dev ens4 proto dhcp src 10.128.0.4 metric 100
# 10.128.0.1 dev ens4 proto dhcp scope link src 10.128.0.4 metric 100
# 10.157.207.0/24 dev lxdbr0 proto kernel scope link src 10.157.207.1 linkdown

# Set up TCP proxy for HTTPS (443)
lxc config device add bowtie-vm https-tcp proxy listen=tcp:10.128.0.4:443 connect=tcp:10.157.207.100:443 nat=true

# Set up UDP proxy for WG (443)
lxc config device add bowtie-vm wg-udp proxy listen=udp:10.128.0.4:443 connect=udp:10.157.207.100:443 nat=true

# Optional: Set up SSH proxy (port 2222)
lxc config device add bowtie-vm ssh proxy listen=tcp:10.128.0.4:2222 connect=tcp:10.157.207.100:22 nat=true

# Start the VM
lxc start bowtie-vm
```

## Verification and Troubleshooting

After deployment, you can verify the VM status with:

```bash
# Check VM status
lxc list

# View VM logs
lxc console bowtie-vm
```
