# CLI コマンドリファレンス

このリポジトリで使用する containerlab・docker・EOS CLI コマンドをまとめたリファレンス。
各ラボの LAB_GUIDE.md にある確認コマンドを探す前に、ここで目的のコマンドを探すことを推奨する。

---

## containerlab コマンド

```bash
# トポロジーをデプロイ（各ラボの deploy.sh が内部で呼ぶ）
containerlab deploy -t topology.yml

# ノードの IP アドレス・状態を一覧表示
containerlab inspect -t topology.yml

# 全ノードに同じコマンドを一括実行
containerlab exec -t topology.yml --cmd "/usr/bin/Cli -c 'show version'"

# トポロジーを停止・削除（各ラボの destroy.sh が内部で呼ぶ）
containerlab destroy -t topology.yml
```

---

## EOS CLI への接続

```bash
# 対話モード（実機ターミナルと同じ操作感）
docker exec -it <コンテナ名> Cli

# 非対話（スクリプト・確認用）
docker exec <コンテナ名> /usr/bin/Cli -c "show version"

# 特権モードで非対話実行（-p 15 でレベル15に昇格）
docker exec <コンテナ名> /usr/bin/Cli -p 15 -c "ping 5.5.5.5 source 4.4.4.4"
```

コンテナ名は `containerlab inspect -t topology.yml` で確認できる。
各ラボでのコンテナ名の形式：`clab-<ラボ名>-<ノード名>`

| ラボ | コンテナ名の例 |
|------|--------------|
| lab01-basic | `clab-lab01-basic-ceos1` |
| lab02-ospf | `clab-lab02-ospf-ceos1` |
| lab03-bgp | `clab-lab03-bgp-ceos1` |

---

## EOS CLI 基本コマンド（全ラボ共通）

```
show version                     # EOS バージョン・ハードウェア情報
show running-config              # 現在の設定全体
show interfaces status           # インターフェース一覧（Up/Down・速度・Duplex）
show interfaces                  # インターフェース詳細（カウンタ・MAC・エラー数）
show ip interface brief          # IP アドレス一覧
show management interface        # 管理インターフェース（Ma0）の情報
show ip route                    # ルーティングテーブル全体
show ip route summary            # ルーティングテーブルの集計（プロトコル別件数）
show logging last 20             # 直近 20 行のシステムログ
```

---

## OSPF 確認コマンド（lab02-ospf）

```
show ip ospf neighbor            # 隣接関係一覧（State・DR/BDR 役割）
show ip ospf neighbor detail     # 隣接関係の詳細（Dead timer・Retransmit queue）
show ip ospf                     # OSPF プロセス全体の状態（Router ID・ABR/ASBR 表示）
show ip ospf interface           # インターフェースごとの OSPF 情報（エリア・Cost・タイマー）
show ip ospf interface brief     # インターフェース OSPF 情報の要約
show ip ospf database            # LSDB 全体（Type1/2/3/5 LSA 一覧）
show ip ospf database router     # Type1 LSA（Router LSA）の詳細
show ip ospf database network    # Type2 LSA（Network LSA）の詳細 ← DR が生成
show ip ospf database summary    # Type3 LSA（Summary LSA）の詳細 ← ABR が生成
show ip ospf database external   # Type5 LSA（External LSA）の詳細 ← ASBR が生成
show ip route ospf               # OSPF で学習したルートのみ表示（O / O IA の区別）
```

### DR/BDR 確認の着目点

`show ip ospf neighbor` の出力：

| フィールド | 意味 |
|-----------|------|
| `FULL/DR` | 隣接先が DR（自分は DROther or BDR）|
| `FULL/BDR` | 隣接先が BDR |
| `FULL/  -` | P2P リンク（DR/BDR なし）|
| `2WAY/DROTHER` | DROther 同士（FULL にならない）|

### LSA タイプの早見表

| タイプ | 名称 | 生成者 | フラッディング範囲 |
|--------|------|--------|------------------|
| Type1 | Router LSA | 全ルーター | 同一エリア内 |
| Type2 | Network LSA | DR のみ | 同一エリア内 |
| Type3 | Summary LSA | ABR | エリアをまたぐ |
| Type5 | AS External LSA | ASBR | OSPF ドメイン全体 |

---

## BGP 確認コマンド（lab03-bgp）

```
show bgp summary                 # ピア一覧（State・受信プレフィックス数）
show bgp neighbors               # 全ピアの詳細（State・タイマー・統計）
show bgp neighbors <IP>          # 特定ピアの詳細
show ip bgp                      # BGP テーブル全体（AS-PATH・nexthop・best フラグ）
show ip bgp <prefix>             # 特定プレフィックスの詳細（nexthop・local-pref・MED）
show ip bgp summary              # ピア一覧の要約（show bgp summary と同様）
show ip route bgp                # BGP で学習した経路のみ（B E / B I の区別）
```

### BGP テーブルの読み方

`show ip bgp` の先頭フラグ：

| フラグ | 意味 |
|--------|------|
| `*` | 有効な経路（nexthop が到達可能）|
| `>` | ベストパス（ルーティングテーブルに入る）|
| `i` | iBGP で学習 |
| `e` | eBGP で学習（省略される場合あり）|

`show ip route bgp` のプレフィックス：

| 表記 | 意味 |
|------|------|
| `B I` | iBGP で学習したルート |
| `B E` | eBGP で学習したルート |

### BGP パス選択の順序（上位が優先）

1. Weight（Cisco 互換・ローカルのみ有効）
2. **Local Preference**（AS 内で有効・高い方が優先）
3. locally originated
4. AS-PATH 長（短い方が優先）
5. Origin（IGP > EGP > Incomplete）
6. **MED**（低い方が優先・同一 AS からの経路同士で比較）
7. eBGP > iBGP
8. IGP metric（nexthop への到達コスト）
9. Router ID（低い方が優先）

---

## OSPF + BGP 再配布コマンド（lab06）

```
show ip route                    # OSPF・BGP 両方の経路が混在することを確認
show ip ospf database external   # redistribute bgp で生成された Type5 LSA を確認
show ip bgp                      # redistribute ospf で BGP に入った経路を確認
```

---

## VXLAN 確認コマンド（lab05-evpn / lab06-l3evpn 共通）

```
show vxlan vtep                  # 発見済み VTEP 一覧（Type-3 ルートで自動学習した VTEP IP）
show vxlan vni                   # VNI <-> VLAN マッピング一覧（L2VNI・L3VNI の両方を表示）
show vxlan address-table         # VXLAN 経由で学習した MAC テーブル（リモートホストのエントリ）
show vxlan flood vtep            # BUM トラフィックのフラッディング先 VTEP 一覧
```

### MAC テーブルの見方

`show mac address-table` のポートフィールド:

| 表示 | 意味 |
|------|------|
| `Port: EtX` | ローカルポートから直接学習 |
| `Port: Vx1` | VXLAN (Vxlan1) 経由で学習（リモート VTEP からの Type-2 伝播） |

---

## BGP EVPN 確認コマンド（lab05-evpn / lab06-l3evpn 共通）

```
show bgp evpn summary            # EVPN セッション一覧（ピア IP・State・受信ルート数）
show bgp evpn                    # EVPN BGP テーブル全体（全ルートタイプ）
show bgp evpn route-type mac-ip  # Type-2: MAC/IP ルート（ホストの MAC・IP 学習・伝播）
show bgp evpn route-type imet    # Type-3: VTEP 発見ルート（IMET・どの VTEP が同一 VNI に参加しているか）
show bgp evpn route-type ip-prefix  # Type-5: IP プレフィックスルート（L3 EVPN のサブネット広告）
show mac address-table           # MAC テーブル（ローカル学習 + EVPN 経由のリモートエントリ）
show mac address-table dynamic   # 動的学習エントリのみ表示
```

### EVPN ルートタイプ早見表

| Type | 名前 | 運ぶ情報 | 主な用途 |
|------|------|---------|---------|
| Type-2 | MAC-IP Advertisement | MAC アドレス・IP アドレス | ホスト MAC/IP の学習と全 Leaf への伝播 |
| Type-3 | Inclusive Multicast Ethernet Tag | VTEP IP・VNI | BGP セッション確立後の VTEP 自動発見 |
| Type-5 | IP Prefix Route | IPv4/IPv6 プレフィックス | L3 EVPN によるサブネット間ルーティング |

---

## L3 EVPN / VRF 確認コマンド（lab06-l3evpn）

```
show vrf                              # VRF 一覧（名前・RD・動作プロトコル）
show ip route vrf <VRF名>             # VRF のルーティングテーブル全体
show ip route vrf <VRF名> <prefix>    # VRF 内の特定プレフィックス詳細（nexthop・VTEP IP 確認）
show ip virtual-router                # Anycast Gateway の MAC アドレス・IP アドレス確認
show running-config | section vxlan   # Vxlan インターフェース設定（VNI マッピング・VRF 割り当て）
```

### L2VNI と L3VNI の違い

| 項目 | L2VNI | L3VNI |
|------|-------|-------|
| 割り当て単位 | VLAN ごと | VRF ごと |
| 用途 | L2 ストレッチ（異なる Leaf 間の同一 L2 セグメント延伸） | VRF 内のサブネット間 L3 ルーティング |
| 対応ルートタイプ | Type-2 (MAC-IP)・Type-3 (VTEP 発見) | Type-5 (IP Prefix) |
| EOS 設定 | `vxlan vlan <id> vni <vni>` | `vxlan vrf <VRF名> vni <vni>` |
