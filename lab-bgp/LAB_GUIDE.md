# lab-bgp — BGP 経路制御（マルチホーム・AS-PATH prepend）

## 目的

ISP を2社挟んだマルチホーム構成で iBGP・eBGP を設定し、AS-PATH prepend による経路制御を実感する。
「なぜ prepend で経路を誘導できるのか」を BGP のベストパス選択ルールから理解することがゴール。

### このラボで学べること

- **iBGP と eBGP の違い**：同一 AS 内（iBGP）と AS 間（eBGP）でセッションの扱いがどう異なるかを理解する
- **next-hop-self の必要性**：iBGP がなぜ nexthop を書き換えないのか、それがなぜ問題になるかを実際に体験する
- **AS-PATH prepend**：自 AS 番号を余分に付け足して経路を長く見せ、相手の経路選択を誘導する
- **マルチホームの primary/backup 設計**：2本の上流経路を持つ顧客 AS が出口を制御する方法
- **BGP ベストパス選択**：AS-PATH Length が選択基準のひとつであることを `show ip bgp` で確認する

---

## 構成図

```
        AS65001（顧客）
            ceos1
           /       \
     eBGP /         \ eBGP + AS-PATH prepend
         /           \
     ceos2           ceos3     AS65002(ISP-A)  AS65003(ISP-B)
     (ISP-A)         (ISP-B)
       |               |
     iBGP            iBGP
       |               |
     ceos4           ceos5     AS65002(ISP-A)  AS65003(ISP-B)
         \           /
     eBGP \         / eBGP
           \       /
            ceos6
        AS65004（顧客）
```

**iBGP の構造:**
- ISP-A 内部: ceos2 ↔ ceos4（同一 AS65002 内の iBGP）
- ISP-B 内部: ceos3 ↔ ceos5（同一 AS65003 内の iBGP）

**経路制御のポイント（configs-full）:**

ceos1 は ceos3 側（ISP-B）への広告に `AS-PATH prepend 65001 65001` を設定。
→ ceos6 から 1.1.1.1/32 を見たとき：
- `via ceos4`（AS-PATH: `65002 65001`、長さ2）が **primary**
- `via ceos5`（AS-PATH: `65003 65001 65001 65001`、長さ4）が **backup**

---

## インターフェース一覧

| ノード | AS | 役割 | インターフェース | アドレス | 接続先 |
|--------|-----|------|----------------|----------|--------|
| ceos1 | 65001 | 顧客スタブ | Loopback0 | 1.1.1.1/32 | — |
| | | | Ethernet1 | 10.0.12.1/30 | eBGP → ceos2 (ISP-A) primary |
| | | | Ethernet2 | 10.0.13.1/30 | eBGP → ceos3 (ISP-B) backup |
| ceos2 | 65002 | ISP-A | Loopback0 | 2.2.2.2/32 | — |
| | | | Ethernet1 | 10.0.12.2/30 | eBGP → ceos1 |
| | | | Ethernet2 | 10.0.24.1/30 | iBGP → ceos4 |
| ceos3 | 65003 | ISP-B | Loopback0 | 3.3.3.3/32 | — |
| | | | Ethernet1 | 10.0.13.2/30 | eBGP → ceos1 |
| | | | Ethernet2 | 10.0.35.1/30 | iBGP → ceos5 |
| ceos4 | 65002 | ISP-A | Loopback0 | 4.4.4.4/32 | — |
| | | | Ethernet1 | 10.0.24.2/30 | iBGP → ceos2 |
| | | | Ethernet2 | 10.0.46.1/30 | eBGP → ceos6 |
| ceos5 | 65003 | ISP-B | Loopback0 | 5.5.5.5/32 | — |
| | | | Ethernet1 | 10.0.35.2/30 | iBGP → ceos3 |
| | | | Ethernet2 | 10.0.56.1/30 | eBGP → ceos6 |
| ceos6 | 65004 | 顧客スタブ | Loopback0 | 6.6.6.6/32 | — |
| | | | Ethernet1 | 10.0.46.2/30 | eBGP → ceos4 (ISP-A) |
| | | | Ethernet2 | 10.0.56.2/30 | eBGP → ceos5 (ISP-B) |

---

## ファイル構成

```
lab-bgp/
├── topology.yml        # containerlab トポロジー定義
├── deploy.sh           # 起動スクリプト（--full オプションあり）
├── destroy.sh          # 停止・削除スクリプト
├── LAB_GUIDE.md        # このファイル
├── configs-init/       # ハンズオンモード用（hostname + interface IP のみ）
│   ├── ceos1.cfg
│   ├── ceos2.cfg
│   ├── ceos3.cfg
│   ├── ceos4.cfg
│   ├── ceos5.cfg
│   └── ceos6.cfg
└── configs-full/       # フルコンフィグモード用（BGP + AS-PATH prepend 含む完全設定）
    ├── ceos1.cfg       # AS65001: eBGP ×2・ISP-B 向け prepend + export filter
    ├── ceos2.cfg       # AS65002 ISP-A: eBGP(ceos1) + iBGP(ceos4)・next-hop-self
    ├── ceos3.cfg       # AS65003 ISP-B: eBGP(ceos1) + iBGP(ceos5)・next-hop-self
    ├── ceos4.cfg       # AS65002 ISP-A: iBGP(ceos2) + eBGP(ceos6)・next-hop-self
    ├── ceos5.cfg       # AS65003 ISP-B: iBGP(ceos3) + eBGP(ceos6)・next-hop-self
    └── ceos6.cfg       # AS65004: eBGP ×2・export filter（自 prefix のみ広告）
```

---

## 起動・停止

```bash
cd ~/git/container_lab/lab-bgp

# 起動（ハンズオンモード：interface IP のみ設定済み・BGP は手動で入力）
./deploy.sh

# 起動（フルコンフィグモード：BGP + AS-PATH prepend 含む全設定済み）
./deploy.sh --full

# 停止・削除
./destroy.sh
```

---

## ハンズオンモードの設定タスク

`./deploy.sh`（オプションなし）で起動した場合、各ノードには hostname と interface IP のみ設定されている。
以下のタスクを自分で設定することがこのラボの目的。

### 全ノード共通

- `service routing protocols model multi-agent` が設定済みであることを確認
- BGP プロセスを有効化し、自分の AS 番号を設定する
- `router-id` を Loopback0 のアドレスと同じ値に設定する
- 各 BGP ピアに対して `neighbor` コマンドで接続先 IP と `remote-as` を設定する
  - `remote-as` が自分の AS と同じ → iBGP、異なる → eBGP
- IPv4 アドレスファミリで各ピアを `activate` する
- Loopback0 のアドレスを BGP で広告（`network` コマンド）する

### ノード別の設定ポイント

| ノード | AS | 役割 | 追加で必要な設定 |
|--------|----|------|-----------------|
| ceos1 | 65001 | 顧客スタブ | eBGP ピア（ceos2・ceos3）を設定。ceos3 側に prepend を設定（後述）。自 prefix のみ広告する export filter を設定 |
| ceos2 | 65002 | ISP-A | eBGP（ceos1）と iBGP（ceos4）の両方・ceos4 への `next-hop-self` |
| ceos3 | 65003 | ISP-B | eBGP（ceos1）と iBGP（ceos5）の両方・ceos5 への `next-hop-self` |
| ceos4 | 65002 | ISP-A | iBGP（ceos2）と eBGP（ceos6）の両方・ceos2 への `next-hop-self` |
| ceos5 | 65003 | ISP-B | iBGP（ceos3）と eBGP（ceos6）の両方・ceos3 への `next-hop-self` |
| ceos6 | 65004 | 顧客スタブ | eBGP ピア（ceos4・ceos5）を設定。自 prefix のみ広告する export filter を設定 |

### スタブ AS の export filter（ceos1・ceos6 で実施）

スタブ AS は他の AS の transit（中継）をしてはならない。`ip prefix-list` と `route-map` を組み合わせ、自 prefix のみを広告するフィルタを設定する。

### AS-PATH prepend の設定（ceos1 で実施）

ceos3 側（ISP-B）への広告経路を backup にするため、ceos1 の ISP-B 向け `route-map` に `set as-path prepend 65001 65001` を追加する。

これにより ceos3 が受け取る 1.1.1.1/32 の AS-PATH は `65001 65001 65001`（長さ3）になる。
ceos2 経由は `65001`（長さ1）のままなので、ceos6 から見て ISP-A 経由が優先される。

具体的な設定コマンドは「ハンズオン設定手順」セクションを参照。

---

## ハンズオン設定手順

各ノードに接続してから `configure` モードで入力する。

```bash
# 例: ceos1 に接続
docker exec -it clab-bgp-ceos1 Cli
```

接続後:

```
configure
```

### ceos1（AS65001 顧客スタブ - eBGP + AS-PATH prepend + export filter）

スタブ AS は他 AS のルートを中継しないよう、export filter で自 prefix のみを広告する。
ISP-B（ceos3）側の広告に prepend を設定してバックアップパスとして誘導する。

```
ip prefix-list OWN-PREFIX seq 10 permit 1.1.1.1/32
!
route-map EXPORT-TO-ISPA permit 10
   match ip address prefix-list OWN-PREFIX
!
route-map EXPORT-TO-ISPB permit 10
   match ip address prefix-list OWN-PREFIX
   set as-path prepend 65001 65001
!
router bgp 65001
   router-id 1.1.1.1
   neighbor 10.0.12.2 remote-as 65002
   neighbor 10.0.12.2 route-map EXPORT-TO-ISPA out
   neighbor 10.0.13.2 remote-as 65003
   neighbor 10.0.13.2 route-map EXPORT-TO-ISPB out
   !
   address-family ipv4
      neighbor 10.0.12.2 activate
      neighbor 10.0.13.2 activate
      network 1.1.1.1/32
```

### ceos2（AS65002 ISP-A 上流 - eBGP + iBGP + next-hop-self）

```
router bgp 65002
   router-id 2.2.2.2
   neighbor 10.0.12.1 remote-as 65001
   neighbor 10.0.24.2 remote-as 65002
   neighbor 10.0.24.2 next-hop-self
   !
   address-family ipv4
      neighbor 10.0.12.1 activate
      neighbor 10.0.24.2 activate
      network 2.2.2.2/32
```

### ceos3（AS65003 ISP-B 上流 - eBGP + iBGP + next-hop-self）

```
router bgp 65003
   router-id 3.3.3.3
   neighbor 10.0.13.1 remote-as 65001
   neighbor 10.0.35.2 remote-as 65003
   neighbor 10.0.35.2 next-hop-self
   !
   address-family ipv4
      neighbor 10.0.13.1 activate
      neighbor 10.0.35.2 activate
      network 3.3.3.3/32
```

### ceos4（AS65002 ISP-A 下流 - iBGP + eBGP + next-hop-self）

```
router bgp 65002
   router-id 4.4.4.4
   neighbor 10.0.24.1 remote-as 65002
   neighbor 10.0.24.1 next-hop-self
   neighbor 10.0.46.2 remote-as 65004
   !
   address-family ipv4
      neighbor 10.0.24.1 activate
      neighbor 10.0.46.2 activate
      network 4.4.4.4/32
```

### ceos5（AS65003 ISP-B 下流 - iBGP + eBGP + next-hop-self）

```
router bgp 65003
   router-id 5.5.5.5
   neighbor 10.0.35.1 remote-as 65003
   neighbor 10.0.35.1 next-hop-self
   neighbor 10.0.56.2 remote-as 65004
   !
   address-family ipv4
      neighbor 10.0.35.1 activate
      neighbor 10.0.56.2 activate
      network 5.5.5.5/32
```

### ceos6（AS65004 顧客スタブ - eBGP + export filter）

```
ip prefix-list OWN-PREFIX seq 10 permit 6.6.6.6/32
!
route-map EXPORT-OWN-ONLY permit 10
   match ip address prefix-list OWN-PREFIX
!
router bgp 65004
   router-id 6.6.6.6
   neighbor 10.0.46.1 remote-as 65002
   neighbor 10.0.46.1 route-map EXPORT-OWN-ONLY out
   neighbor 10.0.56.1 remote-as 65003
   neighbor 10.0.56.1 route-map EXPORT-OWN-ONLY out
   !
   address-family ipv4
      neighbor 10.0.46.1 activate
      neighbor 10.0.56.1 activate
      network 6.6.6.6/32
```

### 設定のポイント

- **next-hop-self が必要な理由**: iBGP はデフォルトで nexthop を書き換えない。ceos2 が ceos1 からの eBGP ルート（nexthop=10.0.12.1）を ceos4 に iBGP 広告する場合、nexthop はそのまま 10.0.12.1 として伝達される。ceos4 は 10.0.12.1 への経路を持たないためルートが使えない。`next-hop-self` を設定すると nexthop が ceos2 自身の IP（10.0.24.1）に書き換えられ、ceos4 から到達可能になる
- **export filter が必要な理由**: スタブ AS（ceos1・ceos6）で export filter がないと、一方の ISP から受け取ったルートをもう一方の ISP に広告してしまい transit AS として動作する。この場合 ceos6 から見た 1.1.1.1/32 の AS-PATH に transit 経路が混入し、prepend の効果が正しく確認できなくなる
- **route-map の暗黙 deny**: `permit` 句で許可した経路以外は暗黙の `deny` で落とされる。export filter はこの性質を利用して自 prefix のみを通過させる

---

## 確認手順

### 1. BGP セッション確認

```bash
docker exec clab-bgp-ceos2 /usr/bin/Cli -c "show bgp summary"
docker exec clab-bgp-ceos4 /usr/bin/Cli -c "show bgp summary"
```

全ピアの State が `Estab` になっていることを確認。

### 2. AS-PATH prepend の効果確認（ceos6 から見た 1.1.1.1/32）

```bash
docker exec clab-bgp-ceos6 /usr/bin/Cli -c "show ip bgp 1.1.1.1"
```

期待される出力（2経路のうち AS-PATH が短い方に `>` が付く）：

```
BGP routing table entry for 1.1.1.1/32
  Paths: 2 available
 *> 65002 65001
      10.0.46.1 ...          ← ceos4(ISP-A) 経由（primary）AS-PATH 長さ2
    65003 65001 65001 65001
      10.0.56.1 ...          ← ceos5(ISP-B) 経由（backup）AS-PATH 長さ4
```

### 3. エンドツーエンド ping（ceos1 Lo → ceos6 Lo）

```bash
docker exec clab-bgp-ceos1 /usr/bin/Cli -p 15 -c "ping 6.6.6.6 source 1.1.1.1"
docker exec clab-bgp-ceos6 /usr/bin/Cli -p 15 -c "ping 1.1.1.1 source 6.6.6.6"
```

### 4. EOS CLI に入って対話的に確認する場合

```bash
docker exec -it clab-bgp-ceos6 Cli
```

```
show bgp summary                     # ピア一覧と状態
show ip bgp                          # BGP テーブル全体（* は有効、> はベストパス）
show ip bgp 1.1.1.1                  # 特定プレフィックスの詳細（AS-PATH を確認）
show ip route bgp                    # BGP で学習したルート
```

---

## トラブルシューティング

| 症状 | 確認コマンド | 原因候補 |
|------|------------|---------|
| BGP が Established にならない | `show bgp neighbors` | IP アドレス誤り・remote-as 誤り |
| nexthop が到達不能（経路が使われない） | `show ip bgp` で nexthop 確認 | next-hop-self 未設定 |
| prepend の効果が出ない | `show ip bgp 1.1.1.1` で AS-PATH 確認 | route-map の方向（out）・neighbor への適用漏れ |
| prepend しても ceos6 で同じ AS-PATH になる | `show ip bgp 1.1.1.1` | スタブ AS の export filter 未設定（transit 経路が混入） |
| ping が通らない | `show ip route bgp` | BGP 経路が RIB に入っていない |
