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

# containerlab deploy (init config)
containerlab deploy -t topology.yml

# Ansible コンテナを起動
echo "[INFO] Ansible コンテナを起動します"
docker run -d \
  --name ansible-lab-l3evpn \
  --network clab \
  -v /etc/hosts:/etc/hosts:ro \
  -v "$(pwd)/ansible":/ansible \
  ansible-eos \
  sleep infinity

# --full の場合は Ansible で設定を自動投入
if [ "$AUTO_APPLY" = true ]; then
  echo "[INFO] 全ノードの eAPI 起動を待機します..."
  NODES=(
    clab-lab-l3evpn-spine1
    clab-lab-l3evpn-spine2
    clab-lab-l3evpn-leaf1
    clab-lab-l3evpn-leaf2
    clab-lab-l3evpn-host1
    clab-lab-l3evpn-host2
    clab-lab-l3evpn-host3
  )
  for node in "${NODES[@]}"; do
    echo -n "  $node ..."
    until curl -s -o /dev/null -u "admin:admin" "http://$node/command-api" 2>/dev/null; do
      sleep 3
    done
    echo " ready"
  done

  echo "[INFO] Ansible で L3 EVPN 設定を投入します"
  docker exec ansible-lab-l3evpn \
    ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/site.yml
  echo "[INFO] Ansible による設定投入が完了しました"
fi

echo ""
echo "[INFO] Ansible コンテナにログインするには:"
echo "  docker exec -it ansible-lab-l3evpn bash"
echo ""
echo "[INFO] playbook を手動実行するには:"
echo "  docker exec ansible-lab-l3evpn ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/site.yml"
echo "  docker exec ansible-lab-l3evpn ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/verify.yml"
