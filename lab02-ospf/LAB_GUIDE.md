# lab02-ospf — OSPF 基礎検証（マルチエリア + DR/BDR）

## 目的

- **DR/BDR 選出**：Area0 のブロードキャストセグメントで3台が選出を行う動作を確認する
- **マルチエリア OSPF**：Area0（バックボーン）・Area1・Area2 の3エリア構成を確認する
- **ABR 動作**：ceos1・ceos2 がエリア間でルートを Type3 LSA として伝播する動作を確認する
- **inter-area ルート**：ceos4（Area1）と ceos5（Area2）が互いの Loopback へ到達できることを確認する
- **LSA タイプ**：Type1（Router）/ Type2（Network）/ Type3（Summary）の違いを確認する

---

## 構成図

```
              Area 0（バックボーン）
              10.0.0.0/24 ブロードキャストセグメント
              Linux bridge (br-area0) 経由 → DR/BDR 選出が発生
         ┌──────────────────────────────────┐
         │                                  │
      ceos1(ABR)       ceos2(ABR)        ceos3
      Lo:1.1.1.1       Lo:2.2.2.2       Lo:3.3.3.3
      Et1:10.0.0.1     Et1:10.0.0.2     Et1:10.0.0.3
         │                    │
    Et2:10.1.0.1/30      Et2:10.2.0.1/30
         │                    │
    Area 1（P2P）        Area 2（P2P）
         │                    │
    Et1:10.1.0.2/30      Et1:10.2.0.2/30
      ceos4                ceos5
      Lo:4.4.4.4           Lo:5.5.5.5
   （内部ルーター）      （内部ルーター）
```

### インターフェース一覧

| ノード | 役割 | インターフェース | アドレス | エリア |
|--------|------|----------------|----------|--------|
| ceos1 | ABR | Loopback0 | 1.1.1.1/32 | Area0 |
| ceos1 | ABR | Ethernet1 | 10.0.0.1/24 | Area0（Broadcast）|
| ceos1 | ABR | Ethernet2 | 10.1.0.1/30 | Area1（P2P）|
| ceos2 | ABR | Loopback0 | 2.2.2.2/32 | Area0 |
| ceos2 | ABR | Ethernet1 | 10.0.0.2/24 | Area0（Broadcast）|
| ceos2 | ABR | Ethernet2 | 10.2.0.1/30 | Area2（P2P）|
| ceos3 | Backbone | Loopback0 | 3.3.3.3/32 | Area0 |
| ceos3 | Backbone | Ethernet1 | 10.0.0.3/24 | Area0（Broadcast）|
| ceos4 | Internal | Loopback0 | 4.4.4.4/32 | Area1 |
| ceos4 | Internal | Ethernet1 | 10.1.0.2/30 | Area1（P2P）|
| ceos5 | Internal | Loopback0 | 5.5.5.5/32 | Area2 |
| ceos5 | Internal | Ethernet1 | 10.2.0.2/30 | Area2（P2P）|

---

## ファイル構成

```
lab02-ospf/
├── topology.yml        # containerlab トポロジー定義
├── LAB_GUIDE.md        # このファイル
└── configs/            # 各ノードの startup-config
    ├── ceos1.cfg       # ABR（Area0 + Area1）
    ├── ceos2.cfg       # ABR（Area0 + Area2）
    ├── ceos3.cfg       # バックボーンルーター（Area0 のみ）
    ├── ceos4.cfg       # 内部ルーター（Area1）
    └── ceos5.cfg       # 内部ルーター（Area2）
```

---

## 設定内容

### DR/BDR 選出について

Area0 の3台は Router Priority がデフォルト（1）のため、**Router ID が最も大きいノードが DR** になる。

| ノード | Router ID | 期待される役割 |
|--------|-----------|----------------|
| ceos3 | 3.3.3.3 | DR（最大）|
| ceos2 | 2.2.2.2 | BDR |
| ceos1 | 1.1.1.1 | DROther |

> **DROther とは**
> DR でも BDR でもないルーターを指す。DROther は DR/BDR とのみ FULL 状態になり、
> DROther 同士は 2-Way 状態にとどまる。これが DR/BDR の存在意義（隣接数の削減）。

### 各ノードの OSPF 設定概要

| ノード | router-id | Area0 | Area1 | Area2 |
|--------|-----------|-------|-------|-------|
| ceos1 | 1.1.1.1 | 10.0.0.0/24, 1.1.1.1/32 | 10.1.0.0/30 | — |
| ceos2 | 2.2.2.2 | 10.0.0.0/24, 2.2.2.2/32 | — | 10.2.0.0/30 |
| ceos3 | 3.3.3.3 | 10.0.0.0/24, 3.3.3.3/32 | — | — |
| ceos4 | 4.4.4.4 | — | 10.1.0.0/30, 4.4.4.4/32 | — |
| ceos5 | 5.5.5.5 | — | — | 10.2.0.0/30, 5.5.5.5/32 |

---

## 起動・停止

```bash
cd ~/git/container_lab/lab02-ospf
containerlab deploy -t topology.yml

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除
containerlab destroy -t topology.yml
```

---

## 確認手順

### 1. DR/BDR 選出の確認

```bash
docker exec clab-lab02-ospf-ceos1 /usr/bin/Cli -c "show ip ospf neighbor"
```

期待される出力（ceos3 が DR、ceos2 が BDR）：

```
Neighbor ID  State      Interface    Role
3.3.3.3      FULL/DR    Ethernet1    DROther（自分は DROther）
2.2.2.2      FULL/BDR   Ethernet1    DROther
```

ceos3 から見ると自分が DR になっているはず：

```bash
docker exec clab-lab02-ospf-ceos3 /usr/bin/Cli -c "show ip ospf neighbor"
```

### 2. マルチエリア・ABR の確認

```bash
docker exec clab-lab02-ospf-ceos1 /usr/bin/Cli -c "show ip ospf"
```

`This router is an ABR` と表示されることを確認する。

### 3. Type3 LSA（inter-area ルート）の確認

ceos4（Area1）から Area2 のルートが Type3 として学習されていること：

```bash
docker exec clab-lab02-ospf-ceos4 /usr/bin/Cli -c "show ip ospf database summary"
```

ceos5（Area2）から Area1 のルートが Type3 として学習されていること：

```bash
docker exec clab-lab02-ospf-ceos5 /usr/bin/Cli -c "show ip ospf database summary"
```

### 4. ルーティングテーブルの確認

```bash
# ceos4 から Area2 の 5.5.5.5/32 が O IA（inter-area）で見えること
docker exec clab-lab02-ospf-ceos4 /usr/bin/Cli -c "show ip route ospf"

# ceos5 から Area1 の 4.4.4.4/32 が O IA（inter-area）で見えること
docker exec clab-lab02-ospf-ceos5 /usr/bin/Cli -c "show ip route ospf"
```

期待される出力（ceos4）：

```
O IA     2.2.2.2/32 [110/...] via 10.1.0.1, Ethernet1
O IA     5.5.5.5/32 [110/...] via 10.1.0.1, Ethernet1
O IA     10.0.0.0/24 [110/...] via 10.1.0.1, Ethernet1
O IA     10.2.0.0/30 [110/...] via 10.1.0.1, Ethernet1
```

### 5. エリアをまたいだ ping（到達性確認）

```bash
# ceos4（Area1）→ ceos5（Area2）の Loopback
docker exec clab-lab02-ospf-ceos4 /usr/bin/Cli -c "ping 5.5.5.5 source 4.4.4.4"

# 逆方向：ceos5（Area2）→ ceos4（Area1）の Loopback
docker exec clab-lab02-ospf-ceos5 /usr/bin/Cli -c "ping 4.4.4.4 source 5.5.5.5"
```

### 6. LSA データベースの確認（全体像）

```bash
# Area0 の DR が生成する Type2（Network LSA）を確認
docker exec clab-lab02-ospf-ceos1 /usr/bin/Cli -c "show ip ospf database"
```

| LSA タイプ | 生成者 | 内容 |
|------------|--------|------|
| Type1（Router LSA）| 全ルーター | 自身のリンク情報 |
| Type2（Network LSA）| DR のみ | ブロードキャストセグメントの情報 |
| Type3（Summary LSA）| ABR | 他エリアのルート要約 |

### EOS CLI に入って対話的に確認する場合

```bash
docker exec -it clab-lab02-ospf-ceos1 Cli
```

```
show ip ospf neighbor          # 隣接関係と DR/BDR 役割
show ip ospf                   # OSPF プロセス全体の状態（ABR 表示など）
show ip ospf interface         # インターフェースごとの OSPF 情報
show ip ospf database          # LSA データベース全体
show ip ospf database summary  # Type3 LSA のみ表示
show ip route ospf             # OSPF で学習したルート（O / O IA の区別）
```
