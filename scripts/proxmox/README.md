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

## Initializing the Bowtie Controller VM

The Bowtie image for Proxmox is a `.vma.zst`, which is used through the "restore VM" option, opposed to creating anew. Unfortuantely, Proxmox doesn't allow for uploading `.vma.zst` through the UI, so it must be `rsync`'d or `scp`'d to the host filesystem and then placed under `/var/lib/vz/dump/`.

`scp ~/Downloads/vzdump-qemu-bowtie-controller-25.08.002.vma.zst root@192.168.86.241:/var/lib/vz/dump/`

Once pushed, the following script can be run (or run as individual commands) to stand up a networking bridge, create and attach the cloud-init network file, configure host-level port forwarding, and then start the VM:

```bash
#!/bin/bash

# === 1. Create vmbr1 bridge (for private NAT) ===
cat <<EOF | tee -a /etc/network/interfaces

auto vmbr1
iface vmbr1 inet static
    address 192.168.100.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF

systemctl restart networking

# === 2. Restore your VM from VMA backup ===
VMID=100
VMA_FILE="vzdump-qemu-bowtie-controller-25.08.002.vma.zst"  # replace with your downloaded version
qmrestore /var/lib/vz/dump/$VMA_FILE $VMID

# === 3. Define static network config for cloud-init ===
sudo mkdir -p /var/lib/vz/snippets
cat <<EOF | tee /var/lib/vz/snippets/static-network.yaml
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
qm set $VMID --cicustom "network=local:snippets/static-network.yaml"
qm cloudinit update $VMID

# === 5. Update NIC to use vmbr1 bridge ===
qm set $VMID --net0 virtio,bridge=vmbr1,firewall=0

# === 6. Add port forwarding from AWS host to VM ===
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 192.168.100.10:443
iptables -t nat -A PREROUTING -p udp --dport 443 -j DNAT --to-destination 192.168.100.10:443
iptables -t nat -A POSTROUTING -s 0.0.0.0/0 -d 192.168.100.0/24 -j MASQUERADE

# === 7. Persist iptables across reboots ===
apt-get install -y iptables-persistent
netfilter-persistent save

# === 8. Start the VM ===
qm start $VMID

echo "✅ VM $VMID started at 192.168.100.10 and port 443 is forwarded"
```

## Misc
Reach out to support@bowtie.works if you have any questions or need any assistance.
