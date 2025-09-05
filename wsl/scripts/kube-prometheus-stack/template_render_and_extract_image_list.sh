helm template airgapped-kube-prom-stack ./kube-prometheus-stack \
  | grep -oE 'image:\s*["'\'']?[^"'\'' ]+["'\'']?' \
  | awk '{print $2}' | sed 's/"//g' | sort -u > images.txt
