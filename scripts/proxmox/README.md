# Bowtie Proxmox Deployment

Steps for deploying a Bowtie controller on Proxmox.

## Standing up Proxmox

If a Proxmox host is needed, it can be stood up on a cloud instance that supports nested virtualization (ie `z1d.metal` on AWS). 

For the example below, we're using the `Debian 12` AMI.

SSH into the host and run:

```bash
sudo apt update

# Add gpg
sudo apt install gnupg

# Add Proxmox repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | sudo tee /etc/apt/sources.list.d/pve-install.list

# Add Proxmox GPG key
wget -qO - https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release.gpg

# Update system and install Proxmox VE
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y proxmox-ve postfix open-iscsi

# Reboot into Proxmox kernel
sudo reboot
```

*Note: There will be several prompts during installation, in all cases opt for using the existing installation packages rather than those provided by the update.*



After reboot, access the UI: **[https://public-ip:8006](https://public-ip:8006)**

Login as `root`

*Note: You will likely need to set a password for root: `sudo passwd root`*

## Restore & Configure the VM

First, upload or SCP the vma to the local storage: 

`scp vzdump-qemu-*.vma.zst root@<instance-ip>:/var/lib/vz/dump/`

Then, create and run this setup script (replace variables as needed):

```bash
#!/bin/bash

# === 1. Create vmbr1 bridge (for private NAT) ===
cat <<EOF | sudo tee -a /etc/network/interfaces

auto vmbr1
iface vmbr1 inet static
    address 192.168.100.1/24
    bridge_ports none
    bridge_stp off
    bridge_fd 0
EOF

sudo systemctl restart networking

# === 2. Restore your VM from VMA backup ===
VMID=100
VMA_FILE="vzdump-qemu-yourvm-25.06.001.vma.zst"  # replace as needed
sudo qmrestore /var/lib/vz/dump/$VMA_FILE $VMID

# === 3. Define static network config for cloud-init ===
sudo mkdir -p /var/lib/vz/snippets
cat <<EOF | sudo tee /var/lib/vz/snippets/static-network.yaml
version: 2
ethernets:
  ens18:
    dhcp4: false
    addresses: [192.168.100.10/24]
    gateway4: 192.168.100.1
    nameservers:
      addresses: [1.1.1.1, 8.8.8.8]
EOF

# === 4. Apply the cloud-init network config ===
sudo qm set $VMID --cicustom "network=local:snippets/static-network.yaml"
sudo qm cloudinit update $VMID

# === 5. Update NIC to use vmbr1 bridge ===
sudo qm set $VMID --net0 virtio,bridge=vmbr1,firewall=0

# === 6. Add port forwarding from AWS host to VM ===
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 192.168.100.10:443
sudo iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination 192.168.100.10:443
sudo iptables -t nat -A POSTROUTING -s 0.0.0.0/0 -d 192.168.100.0/24 -j MASQUERADE

# === 7. Persist iptables across reboots ===
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save

# === 8. Start the VM ===
sudo qm start $VMID

echo "✅ VM $VMID started at 192.168.100.10 and port 443 is forwarded"
```

This will stand up a networking bridge, create and attach the cloud-init network file, configure host-level port forwarding, and start the VM. 

## Misc
Reach out to support@bowtie.works if you have any questions or need any assistance.
