# Bowtie Kubevirt Deployment 

Script for deploying a Bowtie Controller in a Kubernetes cluster using K3s and KubeVirt.

## Overview

This script automates the following deployment steps:

1. Installs K3s (without Traefik ingress controller)
2. Configures kubectl
3. Installs KubeVirt and CDI (used for pulling down the latest KVM Controller image from Bowtie's API)
4. Creates a dedicated namespace for the Bowtie application
5. Ingests and applies the cloud-init configuration for pre-seeding the deployment
7. Creates TCP and UDP LoadBalancer services for:
   - HTTPS (TCP port 443)
   - SSH (TCP port 22, exposed as 2222)
   - WireGuard (UDP port 443)

## Prerequisites

- Linux VM that supports nested virtualization
- At least 4GB RAM and 4 CPU cores available
- At least 64GB of free disk space
- A `cloud-init.yaml` file in the same directory as the script 

## Usage

1. Use the [cloud-init-generator](https://github.com/bowtieworks/deployment-tools/tree/main/tools/cloud-init-generator) tool to generate the cloud-init file
2. Save the file as `cloud-init.yaml`, and place it next to this script on the host where the VM is to be deployed
2. Make the script executable: 
   ```bash
   sudo chmod +x deploy-bowtie.sh
   ```
3. Run the script:
   ```bash
   sudo ./deploy-bowtie.sh
   ```

## This script assumes...

- the deployment is in GoogleCloud, but should work in any networking environment in which the public IP address to the network can NAT traffic to the loadbalancer services
- the firewall rules at the edge of the network are configured to allow `tcp443`, `udp443`, and `tcp2222`
- that a host VM (which supports nested virtualization) is already deployed and able to be accessed
- that Bowtie will handle the certificate provisioning and management. [If preferred to self-manage the certificate](https://docs.bowtie.works/controller.html#bootstrapping), then that can be accomplished by uploading the certificate and private key to the controller once deployed. 
- the ingress solution will be the k3s default loadbalancer services, but can be switched out for whatever is preferred or already running
- DNS settings will be configured for the hostname supplied in the `cloud-init.yaml` file to point to the external IP address of the cluster

## Final notes
- Bowtie by default runs wireguard traffic over `udp443`. If needing to run on a different port, for whatever reason, it requires two changes: 
    1. The cloud-init file used should be modified to express the port that wireguard traffic should run on. Here's an example: 
    ```none
      #cloud-config
      fqdn: kubevirt-demo.bowtie.works
      hostname: kubevirt-demo.bowtie.works
      preserve_hostname: false
      prefer_fqdn_over_hostname: true
      write_files:
      - path: /etc/bowtie-server.d/custom.conf
        content: |
          SITE_ID=60d2e5be-46d8-4bf9-a0d2-215f303f47fc
          BOWTIE_SYNC_PSK=3dd44b0f-804d-4df4-857c-b506955786e2
          BOWTIE_WIREGUARD_PORT=51820
    ```
    2. The `bowtie-udp-service` in the deployment script needs its wireguard ports updated to reflect this change: 
    ```none
    - name: wireguard
    port: 51820
    targetPort: 51820
    protocol: UDP
    ```
- Once the deployment is finished, you can verify the deployment by accessing your Bowtie controller at it's hostname and then login to continue post-deployment setup

## Misc
Reach out to support@bowtie.works if you have any questions or need any assistance.