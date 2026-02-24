# lab05-evpn — BGP EVPN / VXLAN L2 ストレッチ

## 目的

Leaf-Spine ファブリック上で **BGP EVPN + VXLAN** を構成し、異なる Leaf に接続されたホスト同士が L2 レベルで通信できることを確認する。
アンダーレイの eBGP でルータブル基盤を作り、オーバーレイの BGP EVPN でトンネル(VTEP)を自動発見する仕組みを体感することがゴール。

### このラボで学べること

- **アンダーレイ eBGP**: Spine-Leaf 間 P2P リンクの eBGP で Loopback 到達性を確立する
- **オーバーレイ eBGP EVPN**: Loopback 間 `ebgp-multihop` セッションで EVPN ルートを交換する
- **VTEP 自動発見**: Leaf が BGP EVPN Type-3 ルートを広告し、対向 Leaf が VTEP アドレスを自動学習する
- **MAC 学習(Type-2 ルート)**: ホストから MAC/IP が学習されると EVPN BGP で全 Leaf に伝播する
- **`next-hop-unchanged`**: Spine がオーバーレイ経路の next-hop(VTEP IP)を書き換えないことで VXLAN が正常動作する理由を理解する
- **Route Target**: 同一 RT を持つ Leaf 間でのみ EVPN ルートがインポートされる仕組みを理解する

---

## 構成図

### 図1: トポロジ全体

```
  ┌──────────────────────┐             ┌──────────────────────┐
  │       Spine1         │             │       Spine2         │
  │  spine1 / AS65000    │             │  spine2 / AS65000    │
  │  Loopback: 1.1.1.1   │             │  Loopback: 2.2.2.2   │
  └────┬─────────────────┘             └─────────┬────────────┘
       │ <- EVPN オーバーレイ(合計 8 セッション) ->  │
       │ <- eBGP アンダーレイ(合計 8 P2P リンク)->  │
  ┌────┴─────┐  ┌──────────┐  ┌──────────┐  ┌────┴─────┐
  │  Leaf1   │  │  Leaf2   │  │  Leaf3   │  │  Leaf4   │
  │  leaf1   │  │  leaf2   │  │  leaf3   │  │  leaf4   │
  │ AS65001  │  │ AS65002  │  │ AS65003  │  │ AS65004  │
  │ 3.3.3.3  │  │ 4.4.4.4  │  │ 5.5.5.5  │  │ 6.6.6.6  │
  │VNI:10010 │  │VNI:10010 │  │VNI:10010 │  │VNI:10010 │
  └──┬───────┘  └──────────┘  └──────────┘  └───────┬──┘
     │ Et3 (access vlan10)        Et3 (access vlan10)│
  ┌──┴───────┐                               ┌───────┴──┐
  │  Host1   │<----- VXLAN VNI10010 -------->│  Host2   │
  │  host1   │       L2 ストレッチ            │  host2   │
  │.10.1/24  │   (同一セグメント扱い)        │.10.2/24  │
  └──────────┘                               └──────────┘
```

---

### 図2: アンダーレイ接続詳細(eBGP P2P リンク IP)

```
Spine1 (spine1, AS65000, Lo:1.1.1.1)
  ├─ Et1: 10.1.0.1/30  ────  10.1.0.2/30 :Et1  Leaf1 (leaf1, AS65001, Lo:3.3.3.3)
  ├─ Et2: 10.1.0.5/30  ────  10.1.0.6/30 :Et1  Leaf2 (leaf2, AS65002, Lo:4.4.4.4)
  ├─ Et3: 10.1.0.9/30  ──── 10.1.0.10/30 :Et1  Leaf3 (leaf3, AS65003, Lo:5.5.5.5)
  └─ Et4: 10.1.0.13/30 ──── 10.1.0.14/30 :Et1  Leaf4 (leaf4, AS65004, Lo:6.6.6.6)

Spine2 (spine2, AS65000, Lo:2.2.2.2)
  ├─ Et1: 10.2.0.1/30  ────  10.2.0.2/30 :Et2  Leaf1 (leaf1)
  ├─ Et2: 10.2.0.5/30  ────  10.2.0.6/30 :Et2  Leaf2 (leaf2)
  ├─ Et3: 10.2.0.9/30  ──── 10.2.0.10/30 :Et2  Leaf3 (leaf3)
  └─ Et4: 10.2.0.13/30 ──── 10.2.0.14/30 :Et2  Leaf4 (leaf4)

Leaf1 (leaf1) ── Et3 (access vlan10) ── Et1 (access vlan10) ── Host1 (host1, Vlan10: 192.168.10.1/24)
Leaf4 (leaf4) ── Et3 (access vlan10) ── Et1 (access vlan10) ── Host2 (host2, Vlan10: 192.168.10.2/24)
```

---

### 図3: オーバーレイ接続(BGP EVPN セッション)

各 Leaf は Spine1・Spine2 の両方に EVPN セッションを張る(合計 8 セッション)。

```
                        ┌────────────┐   ┌────────────┐
                        │   Spine1   │   │   Spine2   │
                        │  1.1.1.1   │   │  2.2.2.2   │
                        └─────┬──────┘   └──────┬─────┘
                              │  next-hop-unchanged  │
  Leaf1 (3.3.3.3) ────────────┼──────────────────────┤
  Leaf2 (4.4.4.4) ────────────┼──────────────────────┤
  Leaf3 (5.5.5.5) ────────────┼──────────────────────┤
  Leaf4 (6.6.6.6) ────────────┴──────────────────────┘

  ebgp-multihop 3 + update-source Loopback0 で Loopback 間セッション確立
  Spine は受け取った EVPN ルートを next-hop-unchanged で全 Leaf に転送
```

---

## インターフェース一覧

### Spine

| ノード | AS | Loopback0 | Ethernet1 | Ethernet2 | Ethernet3 | Ethernet4 |
|-------|-----|-----------|-----------|-----------|-----------|-----------|
| spine1 | 65000 | 1.1.1.1/32 | 10.1.0.1/30 -> Leaf1 | 10.1.0.5/30 -> Leaf2 | 10.1.0.9/30 -> Leaf3 | 10.1.0.13/30 -> Leaf4 |
| spine2 | 65000 | 2.2.2.2/32 | 10.2.0.1/30 -> Leaf1 | 10.2.0.5/30 -> Leaf2 | 10.2.0.9/30 -> Leaf3 | 10.2.0.13/30 -> Leaf4 |

### Leaf

| ノード | AS | Loopback0 | Ethernet1 (Spine1) | Ethernet2 (Spine2) | Ethernet3 |
|-------|-----|-----------|--------------------|--------------------|-----------|
| leaf1 | 65001 | 3.3.3.3/32 | 10.1.0.2/30 | 10.2.0.2/30 | access vlan10 -> Host1 |
| leaf2 | 65002 | 4.4.4.4/32 | 10.1.0.6/30 | 10.2.0.6/30 | - |
| leaf3 | 65003 | 5.5.5.5/32 | 10.1.0.10/30 | 10.2.0.10/30 | - |
| leaf4 | 65004 | 6.6.6.6/32 | 10.1.0.14/30 | 10.2.0.14/30 | access vlan10 -> Host2 |

### Host / VXLAN

| ノード | 役割 | Vlan10 SVI | 接続先 |
|-------|------|-----------|-------|
| host1 | ホスト | 192.168.10.1/24 | Leaf1(leaf1) Et3 |
| host2 | ホスト | 192.168.10.2/24 | Leaf4(leaf4) Et3 |
| VLAN 10 | L2 セグメント | VNI 10010 | Route-Target 65001:10010 |

---

## ファイル構成

```
lab05-evpn/
├── topology.yml        # containerlab トポロジー定義
├── deploy.sh           # 起動スクリプト(--full オプションあり)
├── destroy.sh          # 停止・削除スクリプト
├── LAB_GUIDE.md        # このファイル
├── configs-init/       # ハンズオンモード(L3 IF + VLAN 定義のみ)
│   ├── spine1.cfg      # Spine1: Loopback + P2P リンク IP
│   ├── spine2.cfg      # Spine2: Loopback + P2P リンク IP
│   ├── leaf1.cfg       # Leaf1:  L3 uplink + access vlan10(Et3)
│   ├── leaf2.cfg       # Leaf2:  L3 uplink + vlan 10 定義
│   ├── leaf3.cfg       # Leaf3:  L3 uplink + vlan 10 定義
│   ├── leaf4.cfg       # Leaf4:  L3 uplink + access vlan10(Et3)
│   ├── host1.cfg       # Host1:  Vlan10 SVI 192.168.10.1/24
│   └── host2.cfg       # Host2:  Vlan10 SVI 192.168.10.2/24
└── configs-full/       # フルコンフィグモード(BGP EVPN + VXLAN 全設定済み)
    ├── spine1.cfg      # Spine1: eBGP underlay + EVPN (next-hop-unchanged)
    ├── spine2.cfg      # Spine2: eBGP underlay + EVPN (next-hop-unchanged)
    ├── leaf1.cfg       # Leaf1:  eBGP + EVPN + Vxlan1
    ├── leaf2.cfg       # Leaf2:  eBGP + EVPN + Vxlan1
    ├── leaf3.cfg       # Leaf3:  eBGP + EVPN + Vxlan1
    ├── leaf4.cfg       # Leaf4:  eBGP + EVPN + Vxlan1
    ├── host1.cfg       # Host1:  configs-init と同一
    └── host2.cfg       # Host2:  configs-init と同一
```

---

## 起動・停止

```bash
cd ~/git/container_lab/lab05-evpn

# 起動(ハンズオンモード：L3 IF + VLAN のみ・BGP EVPN は手動で入力)
./deploy.sh

# 起動(フルコンフィグモード：BGP EVPN + VXLAN 全設定済み)
./deploy.sh --full

# 停止・削除
./destroy.sh
```

---

## ハンズオンモードの設定タスク

`./deploy.sh`(オプションなし)で起動した場合、L3 インターフェース IP と VLAN 定義のみ設定済み。
以下のタスクを手動で設定することがこのラボの目的。

### 全ノード共通

- `service routing protocols model multi-agent` が設定済みであることを確認
- BGP プロセスを有効化し、自分の AS 番号と `router-id` を設定する
- `no bgp default ipv4-unicast` を設定する

### Spine(spine1・spine2)

```
router bgp 65000
   router-id 1.1.1.1
   no bgp default ipv4-unicast
   !
   neighbor LEAF_UNDERLAY peer group
   neighbor LEAF_UNDERLAY send-community extended
   !
   neighbor LEAF_OVERLAY peer group
   neighbor LEAF_OVERLAY ebgp-multihop 3
   neighbor LEAF_OVERLAY update-source Loopback0
   neighbor LEAF_OVERLAY send-community extended
   neighbor LEAF_OVERLAY next-hop-unchanged      # <- VTEP IP を保持するため必須
   !
   neighbor 10.1.0.2 peer group LEAF_UNDERLAY
   neighbor 10.1.0.2 remote-as 65001
   ... (各 Leaf の P2P IP を追加)
   !
   neighbor 3.3.3.3 peer group LEAF_OVERLAY
   neighbor 3.3.3.3 remote-as 65001
   ... (各 Leaf の Loopback IP を追加)
   !
   address-family ipv4
      neighbor LEAF_UNDERLAY activate
      network 1.1.1.1/32
   !
   address-family evpn
      neighbor LEAF_OVERLAY activate
```

### Leaf(leaf1〜leaf4)

```
! Vxlan インターフェース
interface Vxlan1
   vxlan source-interface Loopback0
   vxlan udp-port 4789
   vxlan vlan 10 vni 10010

! BGP(leaf1 の例 / AS65001)
router bgp 65001
   router-id 3.3.3.3
   no bgp default ipv4-unicast
   !
   neighbor SPINE_UNDERLAY peer group
   neighbor SPINE_UNDERLAY send-community extended
   !
   neighbor SPINE_OVERLAY peer group
   neighbor SPINE_OVERLAY ebgp-multihop 3
   neighbor SPINE_OVERLAY update-source Loopback0
   neighbor SPINE_OVERLAY send-community extended
   !
   neighbor 10.1.0.1 peer group SPINE_UNDERLAY
   neighbor 10.1.0.1 remote-as 65000
   neighbor 10.2.0.1 peer group SPINE_UNDERLAY
   neighbor 10.2.0.1 remote-as 65000
   !
   neighbor 1.1.1.1 peer group SPINE_OVERLAY
   neighbor 1.1.1.1 remote-as 65000
   neighbor 2.2.2.2 peer group SPINE_OVERLAY
   neighbor 2.2.2.2 remote-as 65000
   !
   vlan 10
      rd 3.3.3.3:10010          # <- Leaf ごとに一意(Loopback0:VNI)
      route-target import 65001:10010   # <- 全 Leaf 共通(相互インポート)
      route-target export 65001:10010
      redistribute learned
   !
   address-family ipv4
      neighbor SPINE_UNDERLAY activate
      network 3.3.3.3/32
   !
   address-family evpn
      neighbor SPINE_OVERLAY activate
```

---

## 確認手順(フルコンフィグ起動後)

### Step 1: アンダーレイ BGP セッション確認

```bash
# Leaf1 の BGP セッション(Spine1・Spine2 と Estab になること)
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show bgp summary"

# Spine1 の BGP セッション(全 Leaf と Estab になること)
docker exec clab-lab05-evpn-spine1 /usr/bin/Cli -c "show bgp summary"
```

### Step 2: アンダーレイ経路確認(Loopback 到達性)

```bash
# Leaf1 が全 Leaf の Loopback を学習していること
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show ip route bgp"

# Leaf1 → Leaf4(VTEP IP = 6.6.6.6)への疎通確認
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -p 15 -c "ping 6.6.6.6 source 3.3.3.3"
```

### Step 3: EVPN セッション確認

```bash
# Spine1 の EVPN セッション(全 Leaf と Estab になること)
docker exec clab-lab05-evpn-spine1 /usr/bin/Cli -c "show bgp evpn summary"

# Leaf1 の EVPN セッション(Spine1・Spine2 と Estab になること)
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show bgp evpn summary"
```

### Step 4: VTEP 自動発見確認(Type-3 ルート)

```bash
# Leaf1 が学習した VTEP 一覧(Leaf1〜Leaf4 の Loopback が並ぶこと)
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show vxlan vtep"
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show vxlan vni"

# Spine1 が保持する全 EVPN ルート
docker exec clab-lab05-evpn-spine1 /usr/bin/Cli -c "show bgp evpn"
```

### Step 5: エンドツーエンド ping(L2 VXLAN ストレッチ確認)

```bash
# Host1 → Host2(異なる Leaf 間の L2 延伸を確認)
docker exec clab-lab05-evpn-host1 /usr/bin/Cli -p 15 -c "ping 192.168.10.2 source 192.168.10.1 repeat 5"
```

### Step 6: MAC 学習確認(Type-2 ルート)

```bash
# ping 後に MAC テーブルを確認
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show mac address-table"
docker exec clab-lab05-evpn-leaf4 /usr/bin/Cli -c "show mac address-table"

# EVPN MAC-IP ルートの確認
docker exec clab-lab05-evpn-leaf1 /usr/bin/Cli -c "show bgp evpn route-type mac-ip"
docker exec clab-lab05-evpn-spine1 /usr/bin/Cli -c "show bgp evpn route-type mac-ip"
```

---

## 期待される動作

| 確認項目 | 期待値 |
|---------|--------|
| アンダーレイ BGP | 各 Leaf: Spine1・Spine2 と Estab(計 2 セッション)|
| | 各 Spine: 全 4 Leaf と Estab(計 4 セッション)|
| Loopback 到達性 | `ping 6.6.6.6 source 3.3.3.3` が成功 |
| EVPN BGP | 各 Leaf: Spine1・Spine2 と Estab(計 2 EVPN セッション)|
| VTEP 発見 | Leaf1 の `show vxlan vtep` に Leaf4(6.6.6.6)が表示 |
| E2E ping | `192.168.10.1 -> 192.168.10.2` が成功(VXLAN L2 延伸)|
| MAC 学習 | Leaf1 の MAC テーブルに Host2 の MAC が EVPN 経由で登録 |

---

## トラブルシューティング

| 症状 | 確認コマンド | 原因候補 |
|------|------------|---------|
| アンダーレイ BGP が Established にならない | `show bgp neighbors` | IP アドレス誤り・remote-as 誤り |
| Loopback に ping が届かない | `show ip route bgp` | `network` コマンドで Loopback を BGP に入れていない |
| EVPN BGP が Established にならない | `show bgp evpn summary` | `ebgp-multihop 3` または `update-source Loopback0` の設定漏れ・Loopback 未到達 |
| VTEP が表示されない | `show vxlan vtep` | EVPN Type-3 ルートが伝播していない(`send-community extended` 漏れ等)|
| MAC がインポートされない | `show bgp evpn route-type mac-ip` | `route-target import/export` の値が不一致 |
| VXLAN ping が通らない | `show vxlan vni` / `show mac address-table` | `next-hop-unchanged` が Spine に設定されていない(VTEP IP が書き換わる)|
| MAC テーブルに Host が学習されない | `show mac address-table dynamic` | `redistribute learned` の設定漏れ・ホスト側の vlan 設定ミス |

---

## 重要な設定ポイント(ハマりポイント)

### `next-hop-unchanged`(Spine で必須)
eBGP では通常 next-hop を自分の IP に書き換える。EVPN オーバーレイでは Leaf の Loopback(VTEP IP)を保持しないと対向 Leaf が VXLAN を張れない。

### `send-community extended`(全 EVPN ピアで必須)
Extended Community に RT(Route Target)が入っている。これを付けないと RT がストリップされて MAC がインポートされない。

### `route-target import/export` を全 Leaf で統一
RT が一致しないと EVPN ルートがインポートされない。全 Leaf で `65001:10010` に統一する。

### `service routing protocols model multi-agent`(全ノードで必須)
Arista EOS の EVPN は multi-agent モデルが必要。configs-init から設定済み。

### `ebgp-multihop 3` + `update-source Loopback0`
EVPN セッションは Loopback 間(2ホップ先)で peer する。multihop なしでは TCP 接続が確立しない。

---

## EOS CLI で対話的に確認

```bash
docker exec -it clab-lab05-evpn-leaf1 Cli
```

```
show bgp summary                          # BGP セッション全体
show bgp evpn summary                     # EVPN セッション
show bgp evpn                             # EVPN BGP テーブル
show bgp evpn route-type mac-ip           # MAC-IP Type2 ルート
show bgp evpn route-type imet             # IMET Type3 ルート(VTEP 発見)
show vxlan vtep                           # 発見済み VTEP 一覧
show vxlan vni                            # VNI <-> VLAN マッピング
show mac address-table                    # MAC テーブル
show ip route bgp                         # アンダーレイ BGP 経路
```
