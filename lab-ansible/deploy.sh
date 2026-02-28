#!/bin/bash
set -e
cd "$(dirname "$0")"

AUTO_APPLY=false

if [ "$1" = "--full" ]; then
  AUTO_APPLY=true
  echo "[INFO] フルモード（configs-init で起動し Ansible で設定を自動投入します）"
else
  echo "[INFO] ハンズオンモード（configs-init で起動します）"
fi

# ansible-eos イメージのビルド
echo "[INFO] ansible-eos イメージをビルドします"
docker build -t ansible-eos .

# containerlab deploy
containerlab deploy -t topology.yml

# Ansible コンテナを起動
echo "[INFO] Ansible コンテナを起動します"
docker run -d \
  --name ansible-lab04 \
  --network clab \
  -v /etc/hosts:/etc/hosts:ro \
  -v "$(pwd)/ansible":/ansible \
  ansible-eos \
  sleep infinity

# --full の場合は Ansible で設定を自動投入
if [ "$AUTO_APPLY" = true ]; then
  echo "[INFO] 全ノードの eAPI 起動を待機します..."
  NODES=(
    clab-lab-ansible-ceos1
    clab-lab-ansible-ceos2
    clab-lab-ansible-ceos3
    clab-lab-ansible-ceos4
    clab-lab-ansible-ceos5
    clab-lab-ansible-ceos6
    clab-lab-ansible-ceos7
    clab-lab-ansible-ceos8
  )
  for node in "${NODES[@]}"; do
    echo -n "  $node ..."
    until curl -s -o /dev/null -u "admin:admin" "http://$node/command-api" 2>/dev/null; do
      sleep 3
    done
    echo " ready"
  done

  echo "[INFO] Ansible で OSPF 設定を投入します"
  docker exec ansible-lab04 \
    ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/site.yml
  echo "[INFO] Ansible による OSPF 設定投入が完了しました"
fi

echo "[INFO] Ansible コンテナにログインするには: docker exec -it ansible-lab04 bash"
