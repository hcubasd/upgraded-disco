curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -rf kubectl
kubectl version --client
