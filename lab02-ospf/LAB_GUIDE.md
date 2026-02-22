# lab02-ospf — OSPF 基礎検証（マルチエリア + DR/BDR）

## 目的

OSPF のマルチエリア構成を自分で設定することで、エリア設計の考え方と OSPF の内部動作を体験的に理解する。
「設定を覚える」だけでなく「なぜそう動くか」を実機に近い環境で確認することがゴール。

### このラボで学べること

- **DR/BDR 選出**：ブロードキャストセグメントで隣接数を減らす仕組みと、Router ID による選出ルールを理解する
- **マルチエリア設計**：Area0（バックボーン）を中心に複数エリアを設計する理由と構成方法を理解する
- **ABR の役割**：2つのエリアに接続するルーターがエリア間でルートを Type3 LSA として伝播する動作を理解する
- **LSA タイプの違い**：Type1（Router）/ Type2（Network）/ Type3（Summary）それぞれの生成者と用途を理解する
- **ハンズオン設定スキル**：`router ospf` の基本設定（router-id・network コマンド・エリア割り当て）を自分で入力できるようにする

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
├── deploy.sh           # 起動スクリプト（--full オプションあり）
├── destroy.sh          # 停止・削除スクリプト
├── LAB_GUIDE.md        # このファイル
├── configs-init/       # ハンズオンモード用（hostname + interface IP のみ）
│   ├── ceos1.cfg
│   ├── ceos2.cfg
│   ├── ceos3.cfg
│   ├── ceos4.cfg
│   └── ceos5.cfg
└── configs-full/       # フルコンフィグモード用（OSPF 含む完全設定）
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

このラボは Area0 にブロードキャストセグメントが必要なため、Linux bridge（br-area0）を使用する。
スクリプトが bridge の作成・削除を自動で行う。sudo パスワードの入力が1回必要。

```bash
cd ~/git/container_lab/lab02-ospf

# 起動（ハンズオンモード：interface IP のみ設定済み・OSPF は手動で入力）
./deploy.sh

# 起動（フルコンフィグモード：OSPF 含む全設定済み）
./deploy.sh --full

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除（containerlab destroy + bridge 削除）
./destroy.sh
```

> **Note:** WSL2 を再起動すると bridge が消えるが、`./deploy.sh` を実行すれば自動で再作成される。

---

## ハンズオンモードの設定タスク

`./deploy.sh`（オプションなし）で起動した場合、各ノードには hostname と interface IP のみ設定されている。
以下のタスクを自分で設定することがこのラボの目的。

### 全ノード共通

- OSPF プロセス（プロセス番号: 1）を有効化する
- `router-id` を Loopback0 のアドレスと同じ値に設定する
- 各インターフェースが所属するエリアに対して `network` コマンドでアドレスを宣言する
  - Loopback0 も忘れずにエリアに含める

### ノード別の設定ポイント

| ノード | 役割 | 設定すべきエリア |
|--------|------|-----------------|
| ceos1 | ABR | Area0（Et1・Lo0）と Area1（Et2）の両方 |
| ceos2 | ABR | Area0（Et1・Lo0）と Area2（Et2）の両方 |
| ceos3 | Backbone | Area0（Et1・Lo0）のみ |
| ceos4 | Internal | Area1（Et1・Lo0）のみ |
| ceos5 | Internal | Area2（Et1・Lo0）のみ |

### 設定完了の確認ポイント

- 各ノードで OSPF 隣接関係が FULL になること
- ceos1・ceos2 が ABR として認識されること
- ceos4 から ceos5 の Loopback（5.5.5.5）への経路が O IA で見えること

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
