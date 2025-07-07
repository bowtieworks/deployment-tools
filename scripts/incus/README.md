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

Creating and applying a `user-data` configuration file to cloud-init is entirely optional. This is primarily useful for supplying a public SSH key for console access or if preferring to configure the instance from code directly. If a `user-data` configuration is desired, you can use the [cloud-init-generator](https://github.com/bowtieworks/deployment-tools/tree/main/tools/cloud-init-generator) tool to generate a well-formed `user-data` file, or if only wanting to supply a public ssh key, you can copy the below template and replace the sample SSH key with your own. 

```yaml
#cloud-config
users:
- name: root
  ssh_authorized_keys:
  - ssh-ed25519 AAAA example_public_ssh_key
  lock_passwd: false
```

If created, save the `user-data` as `user-data.yaml`.

Creating and applying a `network-config` file is **necessary** for static IP assignment. Unless otherwise preferred, copy the below template, modify it's values according to the comments below, and then save it as `network-config.yaml`. 

```yaml
version: 2
ethernets:
  enp5s0:
    dhcp4: false
    addresses:
      - 10.89.113.100/24 # Replace with any static IP from the CIDR assigned to the bridge interface
    gateway4: 10.89.113.1 # Replace with gateway assigned to bridge interface
    nameservers:
      addresses:
        - 1.1.1.1 # Replace with preferred public resolver to be used
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

# If utilizing user-data, apply user-data to cloud-init configuration
incus config set bowtie-vm cloud-init.user-data - < user-data.yaml

# If assigning a static IP, apply network-config to cloud-init configuration
incus config set bowtie-vm cloud-init.network-config - < network-config.yaml

# Attach the bundled cloud-init configuration
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

# Create network forwarder
lxc network forward create <bridge_interface> 10.128.0.4

# Configure TCP/443 forwarding, replacing host IP and static IP assigned to VM
lxc network forward port add <bridge_interface> 10.128.0.4 tcp 443 10.89.113.100

# Configure UDP/443 forwarding, replacing host IP and static IP assigned to VM
lxc network forward port add <bridge_interface> 10.128.0.4 udp 443 10.89.113.100

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

## Additional notes
- If accessing the console, try to do so immediately after booting the VM. If upon doing so and no logs are visible, restart the VM and hit the console access command thereafter
- While both approaches are viable, and up to the administrator to decide which route is preferred, the above instructions generally assume the VM is being assigned an IP from a bridge interface, rather than being assigned an address via DHCP on the same LAN as the host machine
