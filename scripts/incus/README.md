# Bowtie Incus Deployment

Steps for deploying a Bowtie Controller on an Incus environment.

## Setup process

### 1. Prepare the Incus environment

```bash
# Update the system
sudo apt update && sudo apt upgrade -y

# Check Incus version
incus --version

# If not installed
# See https://linuxcontainers.org/incus/docs/main/installing/#installing 

# Add user to incus-admin group to avoid needing to run commands as root
sudo adduser $USER incus-admin
newgrp incus-admin

# Initialize incus (use defaults except increase loop device size)
incus admin init

# Confirm network configuration
incus network list

# Note the IPv4 address of the new bridge interface (e.g., 10.89.113.1/24)
```

### 2. Configure cloud-init and network-config

[Create a cloud-init configuration file](https://github.com/bowtieworks/deployment-tools/tree/main/tools/cloud-init-generator) and save it as (`cloud-init.yaml`) on your host VM.

If needing static IP assignment (no DHCP available), create a network configuration file at `network-config.yaml`:

```yaml
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - 10.89.113.100/24 # Replace with static IP from the CIDR assigned to the bridge interface
    gateway4: 10.89.113.1 # Replace with gateway assigned to bridge interface
    nameservers:
      addresses:
        - 1.1.1.1 # Replace with preferred resolver to be used
```

### 3. Download and prepare the Bowtie image

```bash
# Download the latest Bowtie controller image (https://api.bowtie.works/platforms/Incus)
wget -O bowtie-controller-incus-25.06.002.tar.zst "https://api.bowtie.works/api/v1/package/4654/download/"
```

Package and import the image: 

```bash
# Import the VM image
incus image import bowtie-controller-incus-25.06.002.tar.zst --alias bowtie-controller-image
```

### 4. Create and configure the VM

```bash
# Initialize the VM
incus init bowtie-controller-image bowtie-vm --vm -c limits.cpu=2 -c limits.memory=4GB -s default

# Disable secure boot
incus config set bowtie-vm security.secureboot false

# Apply user-data (if user-data is needed)
incus config set bowtie-vm cloud-init.user-data - < user-data.yaml

# Apply network-config
incus config set bowtie-vm cloud-init.network-config - < network-config.yaml

# Attach cloud-init disk to devices
incus config device add bowtie-vm config disk source=cloud-init:config

# Validate VM configuration
incus config show bowtie-vm
```

### 5. Start and access the VM

#### Option A: With external port forwarding

```bash
# Start the VM
incus start bowtie-vm

# Configure ports on external firewall/ingress
```

#### Option B: With host-level port forwarding

Assign the static IP to the device:

```bash
# Replace with static IP assigned to the instance
incus profile device set default eth0 ipv4.address=10.89.113.100
```

Configure port forwarding rules:

```bash
# Find the host's internal IP address (10.128.0.4 in this case)
ip route show
# Example output:
# default via 10.128.0.1 dev ens4 proto dhcp src 10.128.0.4 metric 100

# Set up TCP proxy for HTTPS (443)
incus config device add bowtie-vm https-tcp proxy listen=tcp:10.128.0.4:443 connect=tcp:10.89.113.100:443 nat=true

# Set up UDP proxy for WG (443)
incus config device add bowtie-vm wg-udp proxy listen=udp:10.128.0.4:443 connect=udp:10.89.113.100:443 nat=true

# Optional: Set up SSH proxy (port 2222)
incus config device add bowtie-vm ssh proxy listen=tcp:10.128.0.4:2222 connect=tcp:10.89.113.100:22 nat=true

# Start the VM
incus start bowtie-vm
```

## Verification and troubleshooting

After deployment, you can verify the VM status with:

```bash
# Check VM status
incus list

# View serial console
incus console bowtie-vm
```