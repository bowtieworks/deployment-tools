# Bowtie Hyper-V Deployment 

Script for deploying a Bowtie Controller on Hyper-V.

## Prerequisites

- Hyper-V and Administrator privileges
- [Latest Bowtie Hyper-V Controller Image](https://api.bowtie.works/platforms/Hyper-V) 
- At least 4GB RAM and 4 CPU cores available to assign
- At least 64GB of free disk space avaialble to assign
- [Windows ADK (oscdimg.exe)](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install) (used for ISO generation)


## Usage

Three different network modes are supported when deploying the VM:

1. Create a new private NAT with static IP assignment and host-level port forwarding (NetNatStaticMapping)
2. Use a pre-existing external switch with static IP assignment
3. Use a pre-existing external switch with DHCP

- Network modes (1) and (2) leverage cloud-init to set the static IP
- Network modes (2) and (3) don't include port forwarding, as that will likely be handled at the network's edge.

Upon running, the script will: 

1. Decompress the gz virtual disk (always overwriting the existing one)
2. Configure the network 
3. Configure port forwarding (if necessary)
4. Configure cloud-init files (if necessary)
5. Generate and attach ISO (if necessary)
6. Size disk and memory for the VM 
7. Deploy the VM

## Examples

See script details for details on each possible configuration option.

```
    # NAT with static IP and port forwarding
    PS C:\Users\Administrator> .\bowtie-hyperv-new.ps1 `
        -gzPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx.gz" `
        -vhdxPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx" `
        -vmName "BowtieController" `
        -networkMode nat-static-portfwd `
        -vmStaticIP "192.168.100.223/24" `
        -natGatewayIP "192.168.100.1" `
        -natSubnetPrefix "192.168.100.0/24"
```

```
    # External switch with static IP
    PS C:\Users\Administrator> .\bowtie-hyperv-new.ps1 `
        -gzPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx.gz" `
        -vhdxPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx" `
        -vmName "BowtieController" `
        -networkMode ext-switch-static `
        -existingSwitchName "External Network Switch" `
        -vmStaticIP "192.168.1.240/24" `
        -natGatewayIP "192.168.1.1"
```

```
    # External switch with DHCP
    PS C:\Users\Administrator> .\bowtie-hyperv-new.ps1 `
        -gzPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx.gz" `
        -vhdxPath "C:\Users\Administrator\Downloads\bowtie-controller-hyperv-25.06.001.vhdx" `
        -vmName "BowtieController" `
        -networkMode ext-switch-dhcp `
        -existingSwitchName "External Network Switch"
```

*Note: If cloud-init is not used, it can take up to 5 minutes before the VM has completed it's initial bootstrapping process.*

## Misc
Reach out to support@bowtie.works if you have any questions or need any assistance.