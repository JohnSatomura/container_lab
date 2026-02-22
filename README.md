# containerlab 検証環境 セットアップ手順

## このリポジトリについて

Windows + WSL2 上に containerlab を使って Arista cEOS の仮想ネットワーク検証環境を構築するための手順書。
BGP・OSPF・EVPN/VXLAN などのプロトコル検証や、Ansible による自動化の練習を目的としている。

ネットワーク機器の実機を用意しなくても、ノートPC1台でルーターを複数台起動して設定を試せる。

---

## 前提条件

- Windows + WSL2
- Docker インストール済み
- arista.com アカウント（cEOS ダウンロード用）

---

## 1. WSL2 メモリ増量

デフォルトの WSL2 はメモリが少ないため、`C:\Users\<ユーザー名>\.wslconfig` を作成して増量する。
cEOS は 1 台あたり約 1GB のメモリを消費するため、複数台起動する場合は特に重要。

```ini
[wsl2]
memory=12GB
processors=12
swap=2GB
```

設定後、PowerShell で再起動：

```powershell
wsl --shutdown
```

### 確認

```bash
free -h
# Mem: 12GB 程度であること
```

---

## 2. cEOS イメージの取得

cEOS（cEOS-lab）は Arista が提供する Docker 向けの仮想 EOS。
実機と同じ EOS ソフトウェアがコンテナとして動くため、実際のコマンド体系でそのまま練習できる。

1. [arista.com](https://www.arista.com) にログイン
2. Support → Software Downloads → cEOS-lab
3. `cEOS64-lab-4.34.4M.tar.xz` をダウンロード（64bit・Mリリース推奨）
4. WSL2 の作業ディレクトリに配置

### Docker に取り込む

```bash
docker import os-images/cEOS64-lab-4.34.4M.tar.xz ceos:4.34.4M
```

> **Note:** Windows からコピーした場合、拡張子が `.tar.tar` になることがある。
> `file <ファイル名>` で `XZ compressed data` と表示されれば問題なくそのまま実行できる。

### 確認

```bash
docker images ceos
# ceos:4.34.4M が表示されること
```

---

## 3. containerlab のインストール

containerlab はネットワーク機器のコンテナを「トポロジーファイル（YAML）」で定義して
一括起動・停止できるツール。仮想リンクの結線や管理ネットワークの払い出しも自動でやってくれる。

```bash
sudo bash -c "$(curl -sL https://get.containerlab.dev)"
```

> **Note:** `sudo` を付けないとパスワード入力エラーになる。

### 確認

```bash
containerlab version
# version: 0.73.0 程度が表示されること
```

---

## 4. sudo なし実行のためのグループ設定

containerlab はデフォルトで `sudo` が必要。`clab_admins` グループに追加することで不要になる。
毎回 sudo を入力する手間が省けるほか、Ansible などのスクリプトから呼び出すときにも都合がよい。

```bash
sudo usermod -aG clab_admins $USER
# 設定反映のため WSL2 を再起動
wsl --shutdown
```

### 確認

```bash
containerlab version
# sudo なしでバージョンが表示されること
```

---

## 5. ラボ一覧

各ラボの構成図・設定内容・起動手順・確認コマンドは各 LAB_GUIDE.md を参照。
よく使うコマンドは [CLI_REFERENCE.md](./CLI_REFERENCE.md) にまとめている。

---

### [lab01-basic](./lab01-basic/LAB_GUIDE.md) — 2ノード シンプル接続

**目的:** containerlab と cEOS の基本操作を習得する。ルーティング設定は行わず、コンテナの起動・停止・EOS CLI へのアクセス方法を確認することがゴール。後続ラボを進めるための土台として位置付けている。

| 項目 | 内容 |
|------|------|
| 構成 | ceos1 -- ceos2（2台直結）|
| 台数 | 2台 |
| ハンズオンで設定すること | なし（環境確認のみ）|

---

### [lab02-ospf](./lab02-ospf/LAB_GUIDE.md) — OSPF マルチエリア + DR/BDR

**目的:** OSPF のマルチエリア構成を自分で設定することで、エリア設計の考え方・DR/BDR 選出のメカニズム・ABR がどのようにエリア間でルートを伝播するかを体験的に理解する。単に覚えるだけでなく「なぜそう動くか」を実機に近い環境で確認できる。

| 項目 | 内容 |
|------|------|
| 構成 | 5台・3エリア（Area0/1/2）|
| 台数 | 5台 |
| ハンズオンで設定すること | `router ospf`（router-id・network コマンド・エリア割り当て）|

---

### [lab03-bgp](./lab03-bgp/LAB_GUIDE.md) — BGP iBGP + eBGP 基礎

**目的:** 3AS 構成で iBGP・eBGP を自分で設定することで、AS 間ルーティングの仕組み・next-hop-self が必要な理由・AS-PATH による経路制御の基本を実感する。DC ネットワークやクラウド接続で必須となる BGP の土台を身につけることが目的。

| 項目 | 内容 |
|------|------|
| 構成 | 5台・3AS（AS65001/65002/65003）|
| 台数 | 5台 |
| ハンズオンで設定すること | `router bgp`（neighbor・remote-as・next-hop-self・network 広告）|

---

### [lab04-ansible](./lab04-ansible/LAB_GUIDE.md) — Ansible による Leaf-Spine OSPF 自動設定

**目的:** 8台の Leaf-Spine 構成に対して Ansible（arista.eos コレクション）で OSPF を一括設定することで、ネットワーク自動化の価値を体感する。手動設定の手間と自動化の効率を比較しながら、inventory/group_vars/host_vars/playbook の構造と eAPI 接続の仕組みを理解することがゴール。

| 項目 | 内容 |
|------|------|
| 構成 | Leaf-Spine（Spine×2・Leaf×4・Host×2）|
| 台数 | 8台 |
| ハンズオンで設定すること | Ansible playbook で OSPF を一括投入（`eos_config` / `eos_command` モジュール）|

---

### ラボの起動・停止

全ラボ共通で `deploy.sh` / `destroy.sh` を使って操作する。

```bash
cd ~/git/container_lab/<ラボ名>

# 起動
./deploy.sh

# 停止・削除
./destroy.sh
```

> **Note:** ラボによっては `deploy.sh` 内で Linux bridge の作成など追加処理が行われる場合がある。
> 各ラボの詳細は LAB_GUIDE.md を参照。

---

## 6. cEOS への接続方法と sshpass について

### なぜ sshpass を試みたか

セットアップ中、SSH でパスワードを自動入力して非対話的に EOS コマンドを実行しようとした。
`ssh admin@172.20.20.2 "show version"` をスクリプトから呼び出すには、
パスワードを自動で渡す手段が必要であり、`sshpass` がその用途に使われる定番ツールである。

### sshpass の危険性（本番環境では使用禁止）

`sshpass` はパスワードをコマンドライン引数として渡す仕組みのため、以下のリスクがある：

| リスク | 内容 |
|--------|------|
| プロセス一覧に露出 | `ps aux` を実行すると同一ホストの他ユーザーにパスワードが見える |
| シェル履歴に残る | `~/.bash_history` にパスワード付きコマンドが記録される |
| ログに残る | sudo ログや監査ログにパスワードが記録される場合がある |

**本番ネットワーク機器・共有サーバーでは絶対に使ってはいけない。**
この検証環境（ローカルの WSL2 内）に限り、利便性のために検討した経緯がある。

### 結論：この環境では docker exec を使う

cEOS はデフォルトで公開鍵認証のみ受け付ける設定になっており、
パスワード認証では `Permission denied (publickey,keyboard-interactive)` となる。
`sshpass` を使う以前に、そもそもパスワード SSH が通らないため意味がない。

**この環境では `docker exec` 経由の接続を標準とする：**

```bash
# 対話モード（実機ターミナルと同じ操作感）
docker exec -it <コンテナ名> Cli

# 非対話（スクリプト・確認用）
docker exec <コンテナ名> /usr/bin/Cli -c "show version"
```

コンテナ名は `containerlab inspect -t topology.yml` で確認できる。
各ラボでの具体的なコンテナ名は各 LAB_GUIDE.md を参照。

SSH を使いたい場合は、startup-config に公開鍵を仕込むか、
topology.yml の `startup-config` オプションでパスワード認証を有効化する方法がある（別途検討）。

---

## 注意事項・ハマりポイント

| 事象 | 原因 | 対処 |
|------|------|------|
| `containerlab: command not found` | グループ設定前に sudo なし実行した | `sudo usermod -aG clab_admins $USER` 後に WSL2 再起動 |
| `cEOS64-lab-*.tar.tar` になる | Windows からのコピーで拡張子が二重になる | そのまま `docker import` で OK（中身は XZ 圧縮） |
| SSH で `Permission denied` | cEOS デフォルトは公開鍵認証のみ | `docker exec -it <コンテナ名> Cli` で代替 |
| `Unable to init module loader` | WSL2 カーネルに modules.dep がない | 警告のみ・動作には影響なし |
| `the input device is not a TTY` | `docker exec -it` を非対話シェルから実行 | `-it` を外して `docker exec <コンテナ名> /usr/bin/Cli -c "..."` |
| startup-config を修正しても反映されない | `containerlab destroy` 後も `clab-<lab名>/` ディレクトリが残り古い設定が使われる | `destroy` 後に `rm -rf clab-<lab名>/` を実行してから再デプロイ |

### cEOS の Ethernet インターフェースについて

cEOS の Ethernet インターフェースはデフォルトで **L2（switchport）モード** になっている。
L3 ルーティングで IP アドレスを設定する場合は `no switchport` を明示的に入れる必要がある。
入れ忘れると running-config に `ip address` が入っているように見えても実際には機能しない。

```
interface Ethernet1
   no switchport        ← L3 として使う場合は必須
   ip address 10.0.0.1/24
```

`show ip interface Ethernet1` で `does not support IP` と表示されたら、`no switchport` 不足が原因。

---

## 参考

- [containerlab 公式ドキュメント](https://containerlab.dev)
- [Arista cEOS-lab ドキュメント](https://containerlab.dev/manual/kinds/ceos/)
