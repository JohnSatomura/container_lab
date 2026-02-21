# lab01-basic — 2ノード シンプル接続

## 概要

Arista cEOS 2台を Ethernet1 で直接接続した、最もシンプルな検証トポロジー。
ルーティングプロトコル（OSPF・BGP など）の動作確認や、Ansible による自動設定の
動作確認ベースとして使う想定で作成した。

---

## 構成図

```
           172.20.20.0/24（containerlab 管理ネットワーク / Docker bridge: clab）
           ┌─────────────────────────────────────────────────┐
           │                                                 │
           │ Ma0: 172.20.20.2/24              Ma0: 172.20.20.3/24
  ┌────────┴──────────┐                  ┌────────┴──────────┐
  │      ceos1        │                  │      ceos2        │
  │  Arista cEOSLab   │                  │  Arista cEOSLab   │
  │  EOS  4.34.4M     │                  │  EOS  4.34.4M     │
  │                   │                  │                   │
  │              Et1  ├──────────────────┤  Et1              │
  └───────────────────┘   1Gbps / Full   └───────────────────┘
```

### インターフェース一覧

| ノード | インターフェース | アドレス / 接続先           |
|--------|----------------|-----------------------------|
| ceos1  | Management0    | 172.20.20.2/24              |
| ceos1  | Ethernet1      | ceos2:Ethernet1 に直結      |
| ceos2  | Management0    | 172.20.20.3/24              |
| ceos2  | Ethernet1      | ceos1:Ethernet1 に直結      |

> **Management0** は containerlab が自動的に作成する管理ネットワーク用インターフェース。
> ホスト（WSL2）から `172.20.20.x` 宛に ping や SSH が届く。
> **Ethernet1** はノード間のデータプレーン用インターフェース。topology.yml の `links` 定義で結線される。

---

## ファイル構成

```
lab01-basic/
├── topology.yml          # containerlab トポロジー定義
├── LAB_GUIDE.md          # このファイル（構成図・設定内容・操作手順）
└── clab-lab01-basic/     # deploy 後に自動生成されるディレクトリ（Git 管理外）
    ├── ceos1/flash/      # ceos1 の設定・ログ
    └── ceos2/flash/      # ceos2 の設定・ログ
```

---

## 設定内容

containerlab が deploy 時に自動生成する初期設定（startup-config）の内容を記載する。
各ノードの `clab-lab01-basic/<ノード名>/flash/startup-config` に保存されている。

### 共通設定（ceos1 / ceos2 共通）

| 項目 | 設定値 | 備考 |
|------|--------|------|
| ユーザー | `admin` / privilege 15 | パスワードは SHA-512 ハッシュで保存 |
| ルーティングモデル | `multi-agent` | EOS の新しいルーティングアーキテクチャ。EVPN/BGP 等に必要 |
| Spanning Tree | MSTP | cEOS デフォルト |
| Management API（HTTP）| 有効（no shutdown）| eAPI（REST API）用。Ansible arista.eos モジュールが使う |
| Management API（gNMI）| 有効 | gRPC ベースのテレメトリ・設定管理用 |
| Management API（NETCONF）| 有効 | SSH 経由の NETCONF 用 |
| デフォルトゲートウェイ | `0.0.0.0/0 via 172.20.20.1` | containerlab が払い出す管理ネットワークの GW |
| ip routing | 無効（`no ip routing`）| この lab ではルーティングを設定していないため |

> **multi-agent モデルについて**
> EOS には `ribd`（従来）と `multi-agent`（新）の 2 種類のルーティングアーキテクチャがある。
> BGP EVPN や高度な機能を使う場合は `multi-agent` が必要なため、最初から有効にしている。
> 変更後は再起動が必要になるため、後から変えると手間がかかる。

### ceos1 固有の設定

```
hostname ceos1

interface Management0
   ip address 172.20.20.2/24
   ipv6 address 3fff:172:20:20::2/64

interface Ethernet1
   ! 未設定（この lab ではデータプレーンの IP アドレスを割り当てていない）

no ip routing
ip route 0.0.0.0/0 172.20.20.1
```

### ceos2 固有の設定

```
hostname ceos2

interface Management0
   ip address 172.20.20.3/24
   ipv6 address 3fff:172:20:20::3/64

interface Ethernet1
   ! 未設定（この lab ではデータプレーンの IP アドレスを割り当てていない）

no ip routing
ip route 0.0.0.0/0 172.20.20.1
```

### 現時点での制限・未設定項目

| 項目 | 状態 | 次のステップ |
|------|------|-------------|
| Ethernet1 の IP アドレス | 未設定 | OSPF / BGP 検証時に設定する |
| ip routing | 無効 | ルーティング検証時に `ip routing` を有効化する |
| パスワード認証 SSH | 無効 | cEOS デフォルトは公開鍵認証のみ。`docker exec` で代替 |

---

## 起動・停止

```bash
cd ~/git/container_lab/lab01-basic

# 起動
./deploy.sh

# 状態確認
containerlab inspect -t topology.yml

# 停止・削除
./destroy.sh
```

---

## 手動確認コマンド

### ラボ全体の状態確認

```bash
# ノードの IP・状態を一覧表示
containerlab inspect -t topology.yml

# Docker コンテナとして直接確認（Status: Up であること）
docker ps --filter "label=containerlab=lab01-basic"
```

### EOS CLI に入る（対話モード）

```bash
docker exec -it clab-lab01-basic-ceos1 Cli
docker exec -it clab-lab01-basic-ceos2 Cli
```

CLI に入ったら以下のコマンドで確認する：

```
# バージョン・ハードウェア情報
ceos1# show version

# インターフェース状態（Et1 が connected であること）
ceos1# show interfaces status

# インターフェース詳細（カウンタ・MAC アドレス等）
ceos1# show interfaces

# 管理 IP アドレス確認
ceos1# show management interface

# 直近のログ
ceos1# show logging last 20
```

### 非対話でコマンドを実行する（スクリプト・確認用）

```bash
# 全ノードに同じコマンドを一括実行
containerlab exec -t topology.yml --cmd "/usr/bin/Cli -c 'show version'"
containerlab exec -t topology.yml --cmd "/usr/bin/Cli -c 'show interfaces status'"

# 特定ノードのみ
docker exec clab-lab01-basic-ceos1 /usr/bin/Cli -c "show version"
docker exec clab-lab01-basic-ceos2 /usr/bin/Cli -c "show interfaces status"
```
