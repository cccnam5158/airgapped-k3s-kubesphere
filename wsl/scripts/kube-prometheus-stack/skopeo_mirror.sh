# 설치 예 (Ubuntu)
# sudo apt-get install -y skopeo

# 단일 아키텍처만 복사 (amd64)
skopeo copy \
  --override-os linux --override-arch amd64 \
  docker://registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2 \
  docker://gaiderunner.ai:5000/registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.2

# 멀티아키 전체 복사(가능하면 이게 베스트)
skopeo copy --all \
  docker://registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.17.0 \
  docker://gaiderunner.ai:5000/registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.17.0

