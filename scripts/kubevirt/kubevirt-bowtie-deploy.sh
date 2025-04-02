#!/bin/bash
set -e

echo "Starting deployment..."

# 1. Install k3s without Traefik
echo "Installing k3s without Traefik..."
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_EXEC="--disable=traefik" sh -
sleep 30
echo "k3s installation completed."

# Configure kubectl to work without sudo
echo "Configuring kubectl for current user..."
mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config

# 2. Install KubeVirt and CDI
echo "Installing KubeVirt..."
export KUBEVIRT_VERSION="v1.0.0"
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
kubectl -n kubevirt wait kv kubevirt --for condition=Available --timeout=5m

echo "Installing CDI..."
export CDI_VERSION="v1.56.0"
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/${CDI_VERSION}/cdi-cr.yaml
kubectl wait -n cdi cdi cdi --for condition=Available --timeout=5m

# 3. Create a namespace for the application
echo "Creating application namespace..."
kubectl create namespace bowtie

# 4. Create cloud-init secret
echo "Creating cloud-init secret..."
kubectl create secret -n bowtie generic cloudinit-userdata-secret --from-file=userdata=cloud-init.yaml

# 5. Create Bowtie VM and Service with LoadBalancer
echo "Creating Bowtie VM and LoadBalancer Services..."
kubectl apply -n bowtie -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: bowtie-vm
spec:
  source:
    http:
      url: "https://api.bowtie.works/api/v1/package/latest/?package_type=qcow-efi"
  pvc:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 64Gi
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: bowtie-vm
  annotations:
    kubevirt.io/allow-privileged: "true"
spec:
  runStrategy: Always
  template:
    metadata:
      labels:
        kubevirt.io/domain: bowtie-vm
    spec:
      domain:
        cpu:
          cores: 4
        devices:
          disks:
          - disk:
              bus: virtio
            name: bootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            masquerade: {}
            ports:
              - port: 443
                protocol: TCP
              - port: 22
                protocol: TCP
              - port: 443
                protocol: UDP
        firmware:
          bootloader:
            efi:
              secureBoot: false
        machine:
          type: q35
        resources:
          requests:
            memory: 8192M
      networks:
      - name: default
        pod: {}
      volumes:
      - name: bootdisk
        dataVolume:
          name: bowtie-vm
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloudinit-userdata-secret
---
# TCP Service for HTTPS and SSH
apiVersion: v1
kind: Service
metadata:
  name: bowtie-tcp-service
  namespace: bowtie
spec:
  type: LoadBalancer
  ports:
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
  - name: ssh
    protocol: TCP
    port: 2222
    targetPort: 22
  selector:
    kubevirt.io/domain: bowtie-vm
---
# UDP Service for WireGuard
apiVersion: v1
kind: Service
metadata:
  name: bowtie-udp-service
  namespace: bowtie
spec:
  type: LoadBalancer
  ports:
  - name: wireguard
    port: 443
    targetPort: 443
    protocol: UDP
  selector:
    kubevirt.io/domain: bowtie-vm
EOF

# 6. Wait for VM to be ready
echo "Waiting for Bowtie VM to be running..."
kubectl wait -n bowtie virtualmachine/bowtie-vm--for condition=Ready --timeout=15m

# 7. Wait for LoadBalancer services to receive IPs
echo "Waiting for LoadBalancer services to be assigned IPs..."
echo "This can take a few minutes..."

kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' service/bowtie-tcp-service -n bowtie --timeout=5m || true
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' service/bowtie-udp-service -n bowtie --timeout=5m || true

echo "Deployment completed successfully!"
echo "TCP Service Details (HTTPS and SSH):"
kubectl get svc -n bowtie bowtie-tcp-service
echo "UDP Service Details (WireGuard):"
kubectl get svc -n bowtie bowtie-udp-service

# Print connection instructions
echo ""
echo "======================== CONNECTION INSTRUCTIONS ========================"
TCP_IP=$(kubectl get svc -n bowtie bowtie-tcp-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
UDP_IP=$(kubectl get svc -n bowtie bowtie-udp-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Fetch the external IP from GCP metadata (switch out if not using GoogleCloud)
EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip 2>/dev/null || echo "unknown")

if [ "$TCP_IP" != "" ] && [ "$EXTERNAL_IP" != "unknown" ]; then
  echo "HTTPS: https://$EXTERNAL_IP"
  echo "SSH: ssh -p 2222 root@$EXTERNAL_IP"
else
  echo "TCP LoadBalancer IP not available yet or external IP not detected. Check with:"
  echo "kubectl get svc -n bowtie bowtie-tcp-service"
fi
echo "========================================================================"