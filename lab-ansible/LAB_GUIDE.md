# lab-ansible — Ansible による Leaf-Spine OSPF 自動設定

## 目的

8台の Leaf-Spine 構成に対して Ansible（arista.eos コレクション）で OSPF を一括設定することで、
**ネットワーク自動化の価値を体感する**ことがゴール。

手動で1台設定する面倒さを体感した後に Ansible で残り7台を一発設定し、
「なぜ自動化が必要か」を自分の手で確認する。

### このラボで学べること

- **Ansible の基本構造**：inventory / group_vars / host_vars / playbook の役割分担
- **arista.eos コレクション**：`eos_config` / `eos_command` モジュールの使い方
- **eAPI 接続**：Ansible が EOS に HTTP で接続する仕組み（httpapi connection plugin）
- **Leaf-Spine トポロジー**：DC ネットワークの標準構成と OSPF での full mesh 到達性
- **IaC の考え方**：設定をコードで管理し、冪等性（何度実行しても同じ結果）を確認する

---

## 構成図

```
                    [Spine1: ceos1]          [Spine2: ceos2]
                    Lo: 1.1.1.1/32           Lo: 2.2.2.2/32
                   /   |   |   \            /   |   |   \
          Et1    Et2  Et3  Et4  Et1       Et2  Et3  Et4
           |      |    |    |    |         |    |    |
          Et1    Et1  Et1  Et1  Et2       Et2  Et2  Et2
        [Leaf1] [Leaf2][Leaf3][Leaf4]  [Leaf1][Leaf2][Leaf3][Leaf4]
        ceos3   ceos4  ceos5  ceos6    ceos3  ceos4  ceos5  ceos6
        3.3.3.3 4.4.4.4 5.5.5.5 6.6.6.6
          |                      |
         Et3                    Et3
          |                      |
         Et1                    Et1
       [Host1: ceos7]        [Host2: ceos8]
       Lo: 7.7.7.7/32        Lo: 8.8.8.8/32
```

### インターフェース一覧

| リンク | 左側ノード/IF | アドレス | アドレス | 右側ノード/IF |
|--------|--------------|----------|----------|--------------|
| Spine1-Leaf1 | ceos1 Et1 | 10.1.0.1/30 | 10.1.0.2/30 | ceos3 Et1 |
| Spine1-Leaf2 | ceos1 Et2 | 10.1.0.5/30 | 10.1.0.6/30 | ceos4 Et1 |
| Spine1-Leaf3 | ceos1 Et3 | 10.1.0.9/30 | 10.1.0.10/30 | ceos5 Et1 |
| Spine1-Leaf4 | ceos1 Et4 | 10.1.0.13/30 | 10.1.0.14/30 | ceos6 Et1 |
| Spine2-Leaf1 | ceos2 Et1 | 10.2.0.1/30 | 10.2.0.2/30 | ceos3 Et2 |
| Spine2-Leaf2 | ceos2 Et2 | 10.2.0.5/30 | 10.2.0.6/30 | ceos4 Et2 |
| Spine2-Leaf3 | ceos2 Et3 | 10.2.0.9/30 | 10.2.0.10/30 | ceos5 Et2 |
| Spine2-Leaf4 | ceos2 Et4 | 10.2.0.13/30 | 10.2.0.14/30 | ceos6 Et2 |
| Leaf1-Host1 | ceos3 Et3 | 10.3.0.1/30 | 10.3.0.2/30 | ceos7 Et1 |
| Leaf4-Host2 | ceos6 Et3 | 10.3.0.5/30 | 10.3.0.6/30 | ceos8 Et1 |

---

## ファイル構成

```
lab-ansible/
├── topology.yml            # containerlab トポロジー定義（8ノード・10リンク）
├── deploy.sh               # 起動スクリプト（--full オプションあり）
├── destroy.sh              # 停止・削除スクリプト
├── LAB_GUIDE.md            # このファイル
├── configs-init/           # ハンズオンモード（hostname + interface IP + eAPI のみ）
│   ├── ceos1.cfg〜ceos8.cfg
├── configs-full/           # フルコンフィグ（OSPF 設定済み・参照用）
│   ├── ceos1.cfg〜ceos8.cfg
└── ansible/
    ├── inventory.yml       # ノード一覧とグループ定義
    ├── group_vars/
    │   ├── all.yml         # 全ノード共通（eAPI 接続設定）
    │   ├── spine.yml       # Spine グループ共通変数
    │   ├── leaf.yml        # Leaf グループ共通変数
    │   └── host.yml        # Host グループ共通変数
    ├── host_vars/          # ノード固有変数（router-id・OSPF ネットワーク）
    │   ├── ceos1.yml〜ceos8.yml
    └── playbooks/
        ├── site.yml        # OSPF 設定投入（全ノード一括）
        └── verify.yml      # 疎通確認（Host1 → Host2 ping）
```

---

## 事前準備

### Ansible と arista.eos コレクションのインストール

```bash
# Python 仮想環境を使うと管理しやすい（推奨）
python3 -m venv ~/.venv/ansible
source ~/.venv/ansible/bin/activate

# Ansible 本体のインストール
pip install ansible

# Arista EOS コレクションのインストール
ansible-galaxy collection install arista.eos

# インストール確認
ansible --version
ansible-galaxy collection list | grep arista
```

### 動作確認

```bash
# Ansible が EOS に接続できるか確認（lab-ansible が起動済みの状態で）
cd ~/git/container_lab/lab-ansible/ansible
ansible all -i inventory.yml -m arista.eos.eos_command -a "commands='show version'" | head -20
```

---

## 起動・停止

```bash
cd ~/git/container_lab/lab-ansible

# 起動（ハンズオンモード：interface IP のみ設定済み・OSPF は手動または Ansible で投入）
./deploy.sh

# 起動（フルコンフィグモード：OSPF 含む全設定済み・動作確認用）
./deploy.sh --full

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除
./destroy.sh
```

---

## ハンズオンの流れ

### Step 1: 8台を起動する

```bash
cd ~/git/container_lab/lab-ansible
./deploy.sh
```

起動後、各ノードには hostname・interface IP・eAPI 設定のみが入っている。
OSPF 設定はまだない。

### Step 2: 手動で1台だけ OSPF を設定してみる

まず1台（ceos1）だけ手動で設定して、「8台分やる気になれない…」を体感する。

```bash
docker exec -it clab-ansible-ceos1 Cli
```

```
configure
router ospf 1
  router-id 1.1.1.1
  network 1.1.1.1/32 area 0.0.0.0
  network 10.1.0.0/30 area 0.0.0.0
  network 10.1.0.4/30 area 0.0.0.0
  network 10.1.0.8/30 area 0.0.0.0
  network 10.1.0.12/30 area 0.0.0.0
end
```

この時点で ceos1 だけ OSPF を持っているが、他のノードが設定されていないので隣接は形成されない。
**「残り7台を同じように設定するのは大変だ」というのを体感したら Step 3 へ。**

### Step 3: Ansible で全台に OSPF を一括投入

```bash
cd ~/git/container_lab/lab-ansible/ansible

# 全8台に OSPF を一括設定（ceos1 は上書きになるが冪等性があるので問題ない）
ansible-playbook -i inventory.yml playbooks/site.yml
```

実行後、8台すべてに同じ OSPF 設定が投入される。
所要時間は手動設定の 1/8 以下。

### Step 4: 疎通確認 playbook を実行する

```bash
ansible-playbook -i inventory.yml playbooks/verify.yml
```

Host1（ceos7、7.7.7.7）から Host2（ceos8、8.8.8.8）への ping が通れば成功。

### Step 5: playbook と host_vars を読んで「なぜ動いたか」を理解する

- `host_vars/ceos1.yml` を見て、どのネットワークが OSPF に含まれているか確認する
- `playbooks/site.yml` を読んで、Jinja2 変数がどこで展開されているか確認する
- `group_vars/all.yml` を見て、Ansible がどうやって EOS に接続しているか確認する

---

## Ansible ファイルの解説

### inventory.yml

ノードをグループ（spine / leaf / host）に分類して管理する。
`ansible_host` には containerlab が `/etc/hosts` に登録するホスト名を指定している。

```yaml
spine:
  hosts:
    ceos1:
      ansible_host: clab-ansible-ceos1   # /etc/hosts に自動登録される
```

### group_vars/all.yml

全ノード共通の接続設定。arista.eos コレクションは `httpapi` 接続プラグインを使って
eAPI（HTTP/HTTPS）経由で EOS に接続する。

```yaml
ansible_connection: httpapi          # SSH ではなく HTTP API を使う
ansible_httpapi_use_ssl: false       # HTTP を使う（lab 環境では SSL 不要）
ansible_httpapi_port: 80             # eAPI の HTTP ポート
ansible_network_os: arista.eos.eos  # 接続先が Arista EOS であることを明示
ansible_user: admin
ansible_password: ""
```

### host_vars/ceos1.yml（例）

ノード固有の変数。playbook が `{{ ospf_router_id }}` や `{{ ospf_networks }}` を
参照したとき、各ノードのファイルの値が展開される。

```yaml
ospf_router_id: "1.1.1.1"
ospf_networks:
  - prefix: "1.1.1.1/32"
    area: "0.0.0.0"
  - prefix: "10.1.0.0/30"
    area: "0.0.0.0"
  # ...
```

### playbooks/site.yml

`eos_config` モジュールを使って設定を投入する。
`parents` で設定を入れるブロック（`router ospf 1`）を指定し、
`loop` で `ospf_networks` リストを繰り返し処理する。

```yaml
- name: OSPF ネットワーク設定
  arista.eos.eos_config:
    lines:
      - "network {{ item.prefix }} area {{ item.area }}"
    parents: "router ospf {{ ospf_process_id }}"
  loop: "{{ ospf_networks }}"
```

---

## 確認コマンド

### OSPF 隣接関係の確認

```bash
# Spine1（ceos1）の OSPF 隣接：4台（Leaf1〜Leaf4）が Full になっていること
docker exec clab-ansible-ceos1 /usr/bin/Cli -c "show ip ospf neighbor"

# Host1（ceos7）の OSPF 隣接：Leaf1（ceos3）のみ Full になっていること
docker exec clab-ansible-ceos7 /usr/bin/Cli -c "show ip ospf neighbor"
```

期待される出力（ceos1）：
```
Neighbor ID     Pri   State     Dead Time   Address         Interface
3.3.3.3         1     Full/DR   00:00:38    10.1.0.2        Ethernet1
4.4.4.4         1     Full/DR   00:00:38    10.1.0.6        Ethernet2
5.5.5.5         1     Full/DR   00:00:38    10.1.0.10       Ethernet3
6.6.6.6         1     Full/DR   00:00:38    10.1.0.14       Ethernet4
```

### ルーティングテーブルの確認

```bash
# Host1 のルーティングテーブル：8.8.8.8/32 が OSPF 経由で学習されていること
docker exec clab-ansible-ceos7 /usr/bin/Cli -c "show ip route ospf"
```

期待される出力（抜粋）：
```
O     8.8.8.8/32 [110/40] via 10.3.0.1, Ethernet1
```

### エンドツーエンド ping（手動確認）

```bash
# Host1 から Host2 の Loopback0 へ ping
docker exec clab-ansible-ceos7 /usr/bin/Cli -p 15 -c "ping 8.8.8.8 source 7.7.7.7"
```

期待される出力：
```
PING 8.8.8.8 (8.8.8.8) from 7.7.7.7 : 72(100) bytes of data.
80 bytes from 8.8.8.8: icmp_seq=1 ttl=60 time=... ms
5 packets transmitted, 5 received, 0% packet loss
```

### EOS CLI に入って対話的に確認する

```bash
docker exec -it clab-ansible-ceos1 Cli
```

```
show ip ospf neighbor          # OSPF 隣接関係（Full になっているか）
show ip ospf database          # OSPF LSA データベース
show ip route ospf             # OSPF で学習したルート一覧
show ip route 8.8.8.8          # 特定の宛先への経路
ping 8.8.8.8 source 1.1.1.1   # エンドツーエンド疎通確認
```

---

## Ansible 冪等性の確認

```bash
# 同じ playbook を2回実行しても設定が重複しないことを確認する
ansible-playbook -i inventory.yml playbooks/site.yml
ansible-playbook -i inventory.yml playbooks/site.yml  # 2回目は "changed=0" になるはず
```

`eos_config` モジュールは設定の差分を確認してから投入するため、
すでに存在する設定は再投入されない（冪等性）。

---

## トラブルシューティング

| 症状 | 確認コマンド | 原因候補 |
|------|------------|---------|
| Ansible が接続できない | `ansible all -i inventory.yml -m ping` | コンテナ未起動・eAPI 未有効化 |
| `Connection refused` エラー | `docker exec clab-ansible-ceos1 /usr/bin/Cli -c "show management api http-commands"` | management api http-commands が無効 |
| OSPF 隣接が形成されない | `show ip ospf neighbor` | OSPF 設定未投入・インターフェース DOWN |
| ping が通らない | `show ip route 8.8.8.8` | OSPF 経路が RIB に入っていない |
| `module not found: arista.eos` | `ansible-galaxy collection list` | コレクション未インストール |
