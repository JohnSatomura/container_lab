# lab-l3evpn - L3 EVPN (VRF / Type-5) ラボガイド

## 概要

lab-evpn で学んだ L2 EVPN (Type-2/3) を発展させ、L3 EVPN を実装する。
VRF による L3 テナント分離と、BGP EVPN Type-5 (IP Prefix) ルートによるサブネット間ルーティングを学ぶ。

### 学習目標

1. VRF 内の異なるサブネット間を L3 EVPN (Type-5) でルーティングする
2. L3VNI (VRF 専用 VNI) の動作を理解する
3. Anycast Gateway (分散ゲートウェイ) の動作を確認する
4. VRF 分離 (TENANT_A vs TENANT_B) を検証する

---

## トポロジ

```
      [Spine1 AS65000]      [Spine2 AS65000]
      Lo0:1.1.1.1                  Lo0:2.2.2.2
       Et1:10.1.0.1  Et2:10.1.0.5   Et1:10.2.0.1  Et2:10.2.0.5
            |              |               |               |
       10.1.0.2       10.1.0.6       10.2.0.2        10.2.0.6
      [Leaf1 AS65001]                [Leaf2 AS65002]
      Lo0:3.3.3.3                     Lo0:4.4.4.4
      VLAN10 GW:192.168.10.254        VLAN20 GW:192.168.20.254
      VLAN30 GW:192.168.30.254
           |         |                       |
        Et3(VLAN10) Et4(VLAN30)           Et3(VLAN20)
           |         |                       |
      [Host1]       [Host3]           [Host2]
      192.168.10.10  192.168.30.10      192.168.20.10
      (TENANT_A)     (TENANT_B)         (TENANT_A)
```

### ノード一覧

| Node   | 役割   | AS    | Lo0     | 備考 |
|--------|--------|-------|---------|------|
| spine1 | Spine1 | 65000 | 1.1.1.1 | アンダーレイ+オーバーレイ集約 |
| spine2 | Spine2 | 65000 | 2.2.2.2 | 冗長 |
| leaf1  | Leaf1  | 65001 | 3.3.3.3 | TENANT_A VLAN10 + TENANT_B VLAN30 |
| leaf2  | Leaf2  | 65002 | 4.4.4.4 | TENANT_A VLAN20 |
| host1  | Host1  | -     | -       | TENANT_A / 192.168.10.10/24 |
| host2  | Host2  | -     | -       | TENANT_A / 192.168.20.10/24 |
| host3  | Host3  | -     | -       | TENANT_B / 192.168.30.10/24 |

### リンク構成

| リンク | アドレス |
|--------|----------|
| Spine1(Et1) <-> Leaf1(Et1) | 10.1.0.0/30 (.1 / .2) |
| Spine1(Et2) <-> Leaf2(Et1) | 10.1.0.4/30 (.5 / .6) |
| Spine2(Et1) <-> Leaf1(Et2) | 10.2.0.0/30 (.1 / .2) |
| Spine2(Et2) <-> Leaf2(Et2) | 10.2.0.4/30 (.5 / .6) |
| Leaf1(Et3) <-> Host1(Et1)  | VLAN10 access |
| Leaf1(Et4) <-> Host3(Et1)  | VLAN30 access |
| Leaf2(Et3) <-> Host2(Et1)  | VLAN20 access |

---

## VRF / VLAN / VNI 設計

### TENANT_A

| 項目 | 値 |
|------|----|
| VRF | TENANT_A |
| L3VNI | 50001 |
| L3VNI transit VLAN | 100 |
| VRF Route-Target | 100:100 |

| VLAN | L2VNI | サブネット | Anycast GW | 存在 Leaf |
|------|-------|------------|------------|-----------|
| 10 | 10010 | 192.168.10.0/24 | 192.168.10.254 | Leaf1 |
| 20 | 10020 | 192.168.20.0/24 | 192.168.20.254 | Leaf2 |

### TENANT_B

| 項目 | 値 |
|------|----|
| VRF | TENANT_B |
| L3VNI | 50002 |
| L3VNI transit VLAN | 110 |
| VRF Route-Target | 200:200 |

| VLAN | L2VNI | サブネット | Anycast GW | 存在 Leaf |
|------|-------|------------|------------|-----------|
| 30 | 10030 | 192.168.30.0/24 | 192.168.30.254 | Leaf1 |

### Anycast Gateway MAC (全 Leaf 共通)

```
ip virtual-router mac-address 00:1c:73:00:00:01
```

---

## デプロイ手順

### フルモード (推奨 - Ansible が L3 EVPN 設定を自動投入)

```bash
cd lab-l3evpn
./deploy.sh --full
```

処理の流れ:
1. `ansible-eos` Docker イメージをビルド (python:3.11-slim + ansible + arista.eos)
2. `containerlab deploy` で全ノードを configs-init で起動
3. `ansible-lab-l3evpn` コンテナを起動
4. 全ノードの eAPI 起動を待機
5. `site.yml` を実行して L3 EVPN 設定を一括投入

完了後の操作:

```bash
# Ansible コンテナにログイン
docker exec -it ansible-lab-l3evpn bash

# 動作確認 playbook を実行
docker exec ansible-lab-l3evpn ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/verify.yml

# 設定を再投入したい場合
docker exec ansible-lab-l3evpn ansible-playbook -i /ansible/inventory.yml /ansible/playbooks/site.yml
```

### ハンズオンモード (手動設定練習)

```bash
cd lab-l3evpn
./deploy.sh
```

init 設定: Spine は P2P IP アドレスのみ。Leaf は Loopback + P2P IP のみ。
BGP / EVPN / VRF / VLAN / VXLAN は手動で設定する。

`ansible-lab-l3evpn` コンテナのみ起動しており、設定投入は行われない。手動設定後に verify.yml で確認できる。

完成形の設定は `configs-full/` を参照:
- `configs-full/spine1.cfg`, `spine2.cfg`: Spine の BGP 設定
- `configs-full/leaf1.cfg`, `leaf2.cfg`: Leaf の VRF / VXLAN / BGP EVPN 設定
- `configs-full/host1.cfg`, `host2.cfg`, `host3.cfg`: Host の VLAN / IP 設定

---

## 検証コマンド

### Step 1: アンダーレイ確認 (BGP IPv4)

```bash
# Spine1 で Leaf の Loopback が学習されていること
docker exec -it clab-l3evpn-spine1 Cli -p 15 -c "show bgp summary"
docker exec -it clab-l3evpn-spine1 Cli -p 15 -c "show ip route"

# Leaf1 で Spine 経由の Loopback 到達性確認
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "ping 4.4.4.4 source 3.3.3.3"
```

### Step 2: オーバーレイ確認 (BGP EVPN セッション)

```bash
# Leaf1 の EVPN ピア確認
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show bgp evpn summary"

# Leaf2 の EVPN ピア確認
docker exec -it clab-l3evpn-leaf2 Cli -p 15 -c "show bgp evpn summary"
```

### Step 3: VRF / VXLAN 確認

```bash
# Leaf1 の VRF 状態
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show vrf"

# Leaf1 の VNI マッピング (L2VNI + L3VNI が表示されること)
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show vxlan vni"

# Leaf2 の VNI マッピング
docker exec -it clab-l3evpn-leaf2 Cli -p 15 -c "show vxlan vni"
```

### Step 4: Type-5 ルート確認

```bash
# Leaf1 で TENANT_A の IP Prefix (Type-5) ルートを確認
# 192.168.20.0/24 (Leaf2 側) が学習されていること
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show bgp evpn route-type ip-prefix"

# Leaf2 で TENANT_A の IP Prefix ルートを確認
# 192.168.10.0/24 (Leaf1 側) が学習されていること
docker exec -it clab-l3evpn-leaf2 Cli -p 15 -c "show bgp evpn route-type ip-prefix"
```

### Step 5: VRF ルーティングテーブル確認

```bash
# Leaf1 TENANT_A ルーティングテーブル
# 192.168.20.0/24 が EVPN 経由 (VTEP: 4.4.4.4) で存在すること
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route vrf TENANT_A"

# Leaf1 TENANT_B ルーティングテーブル
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route vrf TENANT_B"

# Leaf2 TENANT_A ルーティングテーブル
# 192.168.10.0/24 が EVPN 経由 (VTEP: 3.3.3.3) で存在すること
docker exec -it clab-l3evpn-leaf2 Cli -p 15 -c "show ip route vrf TENANT_A"
```

### Step 6: エンドツーエンド疎通確認

```bash
# [成功] Host1(TENANT_A) -> Host2(TENANT_A): 異なるサブネット間 L3 EVPN ルーティング
docker exec -it clab-l3evpn-host1 Cli -p 15 -c "ping 192.168.20.10 source 192.168.10.10"

# [失敗] Host1(TENANT_A) -> Host3(TENANT_B): VRF 分離 - 到達不可であること
docker exec -it clab-l3evpn-host1 Cli -p 15 -c "ping 192.168.30.10 source 192.168.10.10"

# [成功] Host2(TENANT_A) -> Host1(TENANT_A): 逆方向
docker exec -it clab-l3evpn-host2 Cli -p 15 -c "ping 192.168.10.10 source 192.168.20.10"
```

---

## 主要概念説明

### Symmetric IRB (Integrated Routing and Bridging)

L3 EVPN では Symmetric IRB モデルを使用する。

```
送信方向: Host1 -> Host2

1. Host1 が default GW (192.168.10.254) に向けてパケット送信
2. Leaf1 が TENANT_A VRF でルーティング
   - 宛先 192.168.20.0/24 -> EVPN Type-5 ルート -> VTEP: 4.4.4.4
3. Leaf1 が VXLAN 二重カプセル化
   - 外側ヘッダ: src=3.3.3.3, dst=4.4.4.4, VNI=50001 (L3VNI)
4. Leaf2 が受信し L3VNI (50001) でデカプセル
   - TENANT_A VRF で 192.168.20.10 を検索
5. Leaf2 が VLAN20 SVI 経由で Host2 へ転送
```

特徴:
- 行きも帰りも L3VNI (50001) を使う = "Symmetric" (対称)
- Ingress Leaf と Egress Leaf 両方でルーティングが発生する
- Type-5 (IP Prefix) ルートでサブネット広告

### L3VNI (L3 VXLAN Network Identifier)

L3VNI は VRF 専用の VXLAN トンネル識別子。
L2VNI がVLAN 単位なのに対し、L3VNI は VRF 単位でアサインされる。

```
Leaf 設定:
  vxlan vrf TENANT_A vni 50001   <- VRF TENANT_A のパケットは VNI 50001 でカプセル化

BGP VRF セクション:
  vrf TENANT_A
    route-target import evpn 100:100
    route-target export evpn 100:100
    redistribute connected         <- Type-5 ルート広告
```

### Anycast Gateway (分散ゲートウェイ)

全 Leaf に同一 MAC アドレス・同一 IP アドレスのゲートウェイを設定する仕組み。

```
ip virtual-router mac-address 00:1c:73:00:00:01  <- 全 Leaf 共通 MAC

interface Vlan10
  vrf TENANT_A
  ip address virtual 192.168.10.254/24           <- Anycast GW IP
```

メリット:
- Host は Leaf を移動しても GW の ARP 解決が不要
- 最寄りの Leaf でルーティングが完結 (通信効率が良い)

### L3VNI transit VLAN

Arista EOS では L3VNI 動作のために専用の transit VLAN が必要。
データ転送には使われず、VRF - VNI マッピングの内部処理に使用される。

```
vlan 100           <- TENANT_A 専用 transit VLAN

interface Vlan100
  vrf TENANT_A
  ip address unnumbered Loopback0   <- IP は Loopback と共用
```

### Type-5 ルート (IP Prefix Route)

EVPN Route Type 5。サブネット単位の IP プレフィックスを EVPN で広告する。

```
BGP VRF TENANT_A の redistribute connected により自動生成:
  192.168.10.0/24 (Leaf1 が広告) -> RT 100:100, VTEP 3.3.3.3, L3VNI 50001
  192.168.20.0/24 (Leaf2 が広告) -> RT 100:100, VTEP 4.4.4.4, L3VNI 50001
```

確認コマンド:
```
show bgp evpn route-type ip-prefix
```

---

## トラブルシューティング

### BGP セッションが確立しない

```bash
# アンダーレイ疎通確認 (P2P リンク)
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show interface Ethernet1"
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "ping 10.1.0.1"

# Loopback 経路の確認
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route 1.1.1.1"
```

### Type-5 ルートが学習されない

```bash
# VRF の redistribute connected が設定されているか確認
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show running-config | section router bgp"

# VRF の route-target が一致しているか確認
# Leaf1 (RT export 100:100) <-> Leaf2 (RT import 100:100) が一致していること
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show bgp evpn route-type ip-prefix"
```

### ping が通らない (L3 EVPN)

```bash
# Leaf1 で TENANT_A の宛先サブネットのルートがあるか
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route vrf TENANT_A 192.168.20.0/24"

# Anycast GW の MAC が設定されているか
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip virtual-router"

# Vlan SVI が up しているか
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show interface Vlan10"
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show interface Vlan100"
```

### VRF 分離の確認

```bash
# Leaf1 の TENANT_A と TENANT_B が分離していること
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route vrf TENANT_A"
docker exec -it clab-l3evpn-leaf1 Cli -p 15 -c "show ip route vrf TENANT_B"

# Host1 (TENANT_A) から Host3 (TENANT_B) は到達不可であること
docker exec -it clab-l3evpn-host1 Cli -p 15 -c "ping 192.168.30.10 source 192.168.10.10"
```

---

## ラボ削除

```bash
./destroy.sh
```

以下をまとめて削除する:
- containerlab ノード全台
- `ansible-lab-l3evpn` コンテナ
- `ansible-eos` Docker イメージ
- `clab-l3evpn/` ディレクトリ
