# lab03-bgp — BGP 基礎検証（iBGP + eBGP）

## 目的

- **eBGP セッション確立**：異なる AS 間で BGP ピアが Established になる動作を確認する
- **iBGP セッション確立**：同一 AS 内で BGP ピアが Established になる動作を確認する
- **next-hop-self の効果**：ASBR が iBGP ピアに対して nexthop を自分自身に書き換える動作を確認する
- **AS-PATH 属性**：eBGP を通過するたびに AS 番号が追加される動作を確認する
- **エンドツーエンド到達性**：AS65001 の stub（ceos1）から AS65003 の stub（ceos5）まで ping が通ることを確認する

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
├── deploy.sh           # containerlab deploy（Linux bridge 不要）
├── destroy.sh          # containerlab destroy + clab ディレクトリ削除
├── LAB_GUIDE.md        # このファイル
└── configs/            # 各ノードの startup-config
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
AS-PATH: 65001 65002 65003
         ↑          ↑
         ceos2 が   ceos4 が
         追加        追加
```

---

## 起動・停止

このラボは全リンクが P2P（eth1/eth2 直結）のため、Linux bridge は不要。

```bash
cd ~/git/container_lab/lab03-bgp

# 起動
./deploy.sh

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除
./destroy.sh
```

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
# ceos1 に B E（eBGP 由来）と B I（iBGP 由来）の経路が入っているか
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -c "show ip route bgp"
```

### 5. エンドツーエンド ping（ceos1 Lo → ceos5 Lo）

```bash
docker exec clab-lab03-bgp-ceos1 /usr/bin/Cli -p 15 -c "ping 5.5.5.5 source 1.1.1.1"
```

期待される出力：

```
PING 5.5.5.5 (5.5.5.5) from 1.1.1.1 : 72(100) bytes of data.
80 bytes from 5.5.5.5: icmp_seq=1 ttl=62 time=... ms
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
