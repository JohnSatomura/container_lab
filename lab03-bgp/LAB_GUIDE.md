# lab03-bgp — BGP 基礎検証（iBGP + eBGP）

## 目的

3AS 構成で iBGP・eBGP を自分で設定することで、AS 間ルーティングの仕組みと BGP 特有の動作を実感する。
DC ネットワーク・クラウド接続・ISP 環境で必須となる BGP の土台を身につけることがゴール。

### このラボで学べること

- **iBGP と eBGP の違い**：同一 AS 内（iBGP）と AS 間（eBGP）でセッションの扱いがどう異なるかを理解する
- **next-hop-self の必要性**：iBGP がなぜ nexthop を書き換えないのか、それがなぜ問題になるかを実際に体験する
- **AS-PATH 属性**：eBGP を通過するたびに AS 番号が追加されるループ防止の仕組みを理解する
- **ASBR の役割**：AS 境界ルーターが iBGP と eBGP の橋渡しをする設計パターンを理解する
- **ハンズオン設定スキル**：`router bgp` の基本設定（neighbor・remote-as・next-hop-self・network 広告）を自分で入力できるようにする

---

## 構成図

```
AS65001                    AS65002                    AS65003
                         (transit)

[ceos1]──iBGP──[ceos2]──eBGP──[ceos3]──eBGP──[ceos4]──iBGP──[ceos5]
Lo:1.1.1.1   Lo:2.2.2.2   Lo:3.3.3.3   Lo:4.4.4.4   Lo:5.5.5.5
 (stub)        (ASBR)      (transit)      (ASBR)       (stub)
```

### インターフェース一覧

| ノード | 役割 | インターフェース | アドレス | セッション種別 |
|--------|------|----------------|----------|----------------|
| ceos1 | AS65001 stub | Loopback0 | 1.1.1.1/32 | — |
| ceos1 | AS65001 stub | Ethernet1 | 10.0.12.1/30 | iBGP（to ceos2）|
| ceos2 | AS65001 ASBR | Loopback0 | 2.2.2.2/32 | — |
| ceos2 | AS65001 ASBR | Ethernet1 | 10.0.12.2/30 | iBGP（to ceos1）|
| ceos2 | AS65001 ASBR | Ethernet2 | 10.0.23.1/30 | eBGP（to ceos3）|
| ceos3 | AS65002 transit | Loopback0 | 3.3.3.3/32 | — |
| ceos3 | AS65002 transit | Ethernet1 | 10.0.23.2/30 | eBGP（to ceos2）|
| ceos3 | AS65002 transit | Ethernet2 | 10.0.34.1/30 | eBGP（to ceos4）|
| ceos4 | AS65003 ASBR | Loopback0 | 4.4.4.4/32 | — |
| ceos4 | AS65003 ASBR | Ethernet1 | 10.0.34.2/30 | eBGP（to ceos3）|
| ceos4 | AS65003 ASBR | Ethernet2 | 10.0.45.1/30 | iBGP（to ceos5）|
| ceos5 | AS65003 stub | Loopback0 | 5.5.5.5/32 | — |
| ceos5 | AS65003 stub | Ethernet1 | 10.0.45.2/30 | iBGP（to ceos4）|

---

## ファイル構成

```
lab03-bgp/
├── topology.yml        # containerlab トポロジー定義
├── deploy.sh           # 起動スクリプト（--full オプションあり）
├── destroy.sh          # 停止・削除スクリプト
├── LAB_GUIDE.md        # このファイル
├── configs-init/       # ハンズオンモード用（hostname + interface IP のみ）
│   ├── ceos1.cfg
│   ├── ceos2.cfg
│   ├── ceos3.cfg
│   ├── ceos4.cfg
│   └── ceos5.cfg
└── configs-full/       # フルコンフィグモード用（BGP 含む完全設定）
    ├── ceos1.cfg       # AS65001 stub（iBGP only）
    ├── ceos2.cfg       # AS65001 ASBR（iBGP + eBGP、next-hop-self）
    ├── ceos3.cfg       # AS65002 transit（eBGP only）
    ├── ceos4.cfg       # AS65003 ASBR（eBGP + iBGP、next-hop-self）
    └── ceos5.cfg       # AS65003 stub（iBGP only）
```

---

## 設定内容

### next-hop-self について

iBGP のルールとして、**iBGP ピアは受け取った経路の nexthop を書き換えない**。
そのため、ceos1 が ceos2 から eBGP 経由の経路を受け取ると、nexthop が ceos3（10.0.23.2）のままになる。
ceos1 は 10.0.23.2 への経路を持たないため、そのままでは転送できない。

これを解決するのが `next-hop-self`。ASBR（ceos2・ceos4）が iBGP ピアに広告する際に
nexthop を自分のアドレスに書き換えることで、iBGP ピアが nexthop に到達できるようにする。

| ノード | 設定 | 効果 |
|--------|------|------|
| ceos2 | `neighbor 10.0.12.1 next-hop-self` | ceos1 への広告の nexthop を 10.0.12.2 に書き換える |
| ceos4 | `neighbor 10.0.45.2 next-hop-self` | ceos5 への広告の nexthop を 10.0.45.1 に書き換える |

### AS-PATH 属性

BGP 経路が eBGP を通過するたびに AS 番号が先頭に追加される（AS-PATH prepend）。
ceos1 から見た ceos5（5.5.5.5/32）の AS-PATH は以下のようになる：

```
AS-PATH: 65002 65003
         ↑     ↑
         ceos3 が   ceos4 が
         追加        追加
```

> **Note:** iBGP（同一 AS 内）では AS 番号は付加されない。AS65001 は ceos1 視点では AS-PATH に現れない。

---

## 起動・停止

このラボは全リンクが P2P（eth1/eth2 直結）のため、Linux bridge は不要。

```bash
cd ~/git/container_lab/lab03-bgp

# 起動（ハンズオンモード：interface IP のみ設定済み・BGP は手動で入力）
./deploy.sh

# 起動（フルコンフィグモード：BGP 含む全設定済み）
./deploy.sh --full

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除
./destroy.sh
```

---

## ハンズオンモードの設定タスク

`./deploy.sh`（オプションなし）で起動した場合、各ノードには hostname と interface IP のみ設定されている。
以下のタスクを自分で設定することがこのラボの目的。

### 全ノード共通

- BGP プロセスを有効化し、自分の AS 番号を設定する
- `router-id` を Loopback0 のアドレスと同じ値に設定する
- 各 BGP ピアに対して `neighbor` コマンドで接続先 IP と `remote-as` を設定する
  - `remote-as` が自分の AS と同じ → iBGP、異なる → eBGP
- IPv4 アドレスファミリで各ピアを `activate` する
- Loopback0 のアドレスを BGP で広告（`network` コマンド）する

### ノード別の設定ポイント

| ノード | AS | 役割 | 追加で必要な設定 |
|--------|----|------|-----------------|
| ceos1 | 65001 | stub | iBGP ピア（ceos2）のみ設定 |
| ceos2 | 65001 | ASBR | iBGP（ceos1）と eBGP（ceos3）の両方・ceos1 への `next-hop-self` |
| ceos3 | 65002 | transit | eBGP（ceos2・ceos4）の両方を設定 |
| ceos4 | 65003 | ASBR | eBGP（ceos3）と iBGP（ceos5）の両方・ceos5 への `next-hop-self` |
| ceos5 | 65003 | stub | iBGP ピア（ceos4）のみ設定 |

### next-hop-self が必要な理由

iBGP は受け取った経路の nexthop を書き換えない。
ceos2 が next-hop-self を設定しないと、ceos1 が受け取る外部経路の nexthop が
ceos3（10.0.23.2）のままになり、ceos1 はその nexthop に到達できずルートが使われない。

### 設定完了の確認ポイント

- 全ピアで BGP セッションが Established になること
- ceos1 の BGP テーブルで 5.5.5.5/32 の nexthop が 10.0.12.2（ceos2）になること
- ceos1 から ceos5 の Loopback（5.5.5.5）へ ping が通ること

---

## 確認手順

### 1. BGP セッション確認（Established になっているか）

```bash
# ceos2：iBGP（ceos1）と eBGP（ceos3）の両方が Established
docker exec clab-lab03-bgp-ceos2 /usr/bin/Cli -c "show bgp neighbors"

# ceos3：eBGP（ceos2・ceos4）が Established
docker exec clab-lab03-bgp-ceos3 /usr/bin/Cli -c "show bgp neighbors"
```

期待される出力（State: Established）：

```
BGP neighbor is 10.0.12.1, remote AS 65001, internal link
  BGP state is Established
```

### 2. BGP テーブル確認（AS-PATH・nexthop を確認）

```bash
# ceos1 の BGP テーブル：外部経路の AS-PATH が 65002 65003 になっているか
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -c "show ip bgp"

# ceos3 の BGP テーブル：AS-PATH が両方向で正しく付いているか
docker exec clab-lab03-bgp-ceos3 /usr/bin/Cli -c "show ip bgp"
```

### 3. next-hop-self の効果確認

```bash
# ceos1 で 5.5.5.5/32 の nexthop が 10.0.12.2（ceos2）になっているか確認
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -c "show ip bgp 5.5.5.5"
```

期待される出力：

```
BGP routing table entry for 5.5.5.5/32
  Paths: 1 available
    65002 65003
      10.0.12.2 from 10.0.12.2 (2.2.2.2)
        ↑
        next-hop-self の効果で ceos2 のアドレスになっている
```

### 4. ルーティングテーブル確認

```bash
# ceos1：iBGP ピアしか持たないため全経路が B I（iBGP 由来）で表示される
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -c "show ip route bgp"

# ceos2：eBGP（ceos3）から受けた経路が B E、iBGP（ceos1）から受けた経路が B I で表示される
docker exec clab-lab03-bgp-ceos2 /usr/bin/Cli -c "show ip route bgp"
```

### 5. エンドツーエンド ping（ceos1 Lo → ceos5 Lo）

```bash
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -p 15 -c "ping 5.5.5.5 source 1.1.1.1"
```

期待される出力：

```
PING 5.5.5.5 (5.5.5.5) from 1.1.1.1 : 72(100) bytes of data.
80 bytes from 5.5.5.5: icmp_seq=1 ttl=61 time=... ms
...
5 packets transmitted, 5 received, 0% packet loss
```

### EOS CLI に入って対話的に確認する場合

```bash
docker exec -it clab-lab03-bgp-ceos1 Cli
```

```
show bgp neighbors                   # BGP セッション状態（State: Established か確認）
show ip bgp                          # BGP テーブル全体（AS-PATH・nexthop・best 選択）
show ip bgp 5.5.5.5                  # 特定プレフィックスの詳細（nexthop-self 確認）
show ip route bgp                    # BGP で学習したルート（B E / B I の区別）
show bgp summary                     # ピア一覧とメッセージ統計
```

---

## トラブルシューティング

| 症状 | 確認コマンド | 原因候補 |
|------|------------|---------|
| BGP が Established にならない | `show bgp neighbors` | IP アドレス誤り・remote-as 誤り |
| nexthop が到達不能（iBGP 経路が使われない） | `show ip bgp` で nexthop 確認 | next-hop-self 未設定 |
| ping が通らない | `show ip route bgp` | BGP 経路が RIB に入っていない |
| AS-PATH が想定と異なる | `show ip bgp` | eBGP 設定の remote-as 誤り |
