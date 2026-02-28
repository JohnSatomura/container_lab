# EVPN / VXLAN 技術メモ

lab-evpn の構築・検証を通じて学んだ EVPN と VXLAN の概念をまとめたメモ。

---

## 1. VXLAN とは何か

### なぜ VXLAN が生まれたか

データセンターの仮想化が進む中で、次の2つの問題が顕在化した。

- **VM ライブマイグレーション**: ゲスト VM を別の物理ラックに移動しても、同じ IP アドレスを保持したい(VMware vMotion 等)。
  ここで「同じ IP を保持する = 移動後も同じ L2 セグメント(サブネット)にいる」ことが必要になる。
  IP アドレスはサブネットに紐づいており、VM が別の L2 セグメントに移動すると新しい IP アドレスが割り当てられてしまうためだ。
  つまり **同じ IP を維持したまま別の物理ラックに VM を移動させるには、移動先にも同じ L2 セグメントを延伸する必要がある**。

- **VLAN 数の上限**: IEEE 802.1Q の VLAN ID は 12bit = 最大 4094 個。大規模マルチテナント DC では到底足りない。

VXLAN はこれらを解決するために生まれた **L2 オーバーレイ技術** である。

RFC: **RFC 7348** - Virtual eXtensible Local Area Network (VXLAN)

---

### VXLAN の仕組み

VXLAN は L2 フレームを UDP でカプセル化し、L3 ネットワーク(アンダーレイ)の上で L2 通信を実現する。

- カプセル化・デカプセル化を行うエンドポイントを **VTEP (VXLAN Tunnel Endpoint)** と呼ぶ
- Leaf スイッチが VTEP の役割を担う
- UDP 宛先ポートは **4789** (IANA 割り当て)

### VNI (VXLAN Network Identifier)

VLAN ID の代わりに使う識別子。

| 比較 | VLAN ID | VNI |
|------|---------|-----|
| ビット数 | 12bit | 24bit |
| 最大数 | 4,094 | 16,777,216 |
| 用途 | 物理スイッチ内のセグメント分離 | VXLAN オーバーレイ内のセグメント分離 |

今回のラボでは `VLAN 10 -> VNI 10010` にマッピングしている。

---

## 2. VXLAN パケットフォーマット

VXLAN カプセル化後のパケット構造を以下に示す。

```
+---------------------------+
|   外側 Ethernet ヘッダ    |  src: 送信元 VTEP のインターフェース MAC
|                           |  dst: 次ホップ(Spine 等)の MAC
+---------------------------+
|   外側 IP ヘッダ          |  src: 自分の VTEP IP (Loopback)
|                           |  dst: 相手の VTEP IP (Loopback)
+---------------------------+
|   外側 UDP ヘッダ         |  src port: 可変 (内側 5-tuple のハッシュ値)
|                           |  dst port: 4789 (固定)
+---------------------------+
|   VXLAN ヘッダ (8 byte)   |  flags(8bit) + Reserved(24bit) + VNI(24bit) + Reserved(8bit)
+---------------------------+
|   内側 Ethernet ヘッダ    |  src: Host1 の MAC, dst: Host2 の MAC
+---------------------------+
|   内側 IP ヘッダ          |  src: 192.168.10.1, dst: 192.168.10.2
+---------------------------+
|   Payload                 |
+---------------------------+
```

#### UDP ポートについて

- **dst port 4789**: IANA が VXLAN に割り当てた固定値。受信 VTEP はこのポート宛のパケットをデカプセル化する。
- **src port 可変**: 内側フレームの 5-tuple(送信元 IP・宛先 IP・プロトコル・送信元ポート・宛先ポート)をハッシュして決定する。フローごとに異なる値になるため、アンダーレイの ECMP で複数パスへの負荷分散が可能になる。


#### なぜ TCP ではなく UDP を使うのか

TCP はコネクション管理(SYN/ACK・再送・フロー制御)のオーバーヘッドを持つ。VTEP ペアごとに TCP コネクションを維持すると、大規模 DC では数百〜数千のコネクション状態を管理しなければならず非現実的になる。

UDP を選んだ主な理由は以下の通り。

| 理由 | 説明 |
|------|------|
| ステートレス | コネクション管理が不要でスケールしやすい |
| 二重信頼性の排除 | 内側の TCP ペイロードがすでに再送制御を持っている |
| **ECMP 負荷分散** | src port を内側フレームの 5-tuple ハッシュ値にすることで、アンダーレイの複数パスにフロー単位で分散できる |

#### VTEP IP に Loopback アドレスを使う理由

VTEP IP として Loopback インターフェースの IP を使うのには明確な理由がある。

```
[物理インターフェース IP を VTEP IP にした場合]

Leaf1 の Et1(Spine1 向き)が VTEP IP: 10.1.0.2
  ↓
Spine1 との間のリンクが切断
  ↓
VTEP IP 10.1.0.2 が到達不能 -> 全 VXLAN トンネルが断絶

[Loopback IP を VTEP IP にした場合]

Leaf1 の Loopback0 が VTEP IP: 3.3.3.3
  ↓
Spine1 との間のリンクが切断
  ↓
アンダーレイ eBGP が Spine2 経由の経路に切り替える
  ↓
3.3.3.3 は引き続き到達可能 -> VXLAN トンネルが維持される
```

Loopback インターフェースは物理リンク障害の影響を受けず常に UP 状態であるため、冗長リンクを持つ環境での耐障害性が高い。今回のラボでも各 Leaf の Loopback0 (3.3.3.3〜6.6.6.6) を VTEP IP として使っている。

---

#### VXLAN ヘッダの Reserved が2つある理由

RFC 7348 の VXLAN ヘッダは 8 byte で構成されている。

```
bit:  0       7 8              31 32             55 56      63
      +--------+----------------+------------------+---------+
      | flags  |   Reserved     |       VNI        | Reserved|
      | 8 bit  |    24 bit      |      24 bit      |  8 bit  |
      +--------+----------------+------------------+---------+
```

VNI を 4 バイト目(32bit 境界)から始めることで byte-aligned な取り出しが容易になる設計になっている。前後の Reserved 領域は将来の拡張のために確保されており、実際に VXLAN-GPE(Generic Protocol Extension)などの拡張仕様ではこれらのビットを活用している。

---

### オーバーヘッドと MTU

VXLAN カプセル化によって **50 byte** のヘッダが増加する。

| ヘッダ | サイズ |
|--------|--------|
| 外側 Ethernet | 14 byte |
| 外側 IP | 20 byte |
| 外側 UDP | 8 byte |
| VXLAN | 8 byte |
| 合計オーバーヘッド | **50 byte** |

#### どのリンクの MTU を変更する必要があるか

**変更が必要なのはアンダーレイのファブリックリンク(Leaf ↔ Spine 間)のみ**。ホスト側のアクセスポートは変更不要。

```
Host --- (MTU: 1500) --- Leaf --- (MTU: 9000) --- Spine --- (MTU: 9000) --- Leaf --- (MTU: 1500) --- Host
         アクセスポート          ファブリックリンク            ファブリックリンク         アクセスポート
          変更不要                 変更必要                    変更必要               変更不要
```

ホスト側は VXLAN カプセル化の存在を知らない(透過的)。VXLAN のカプセル化・デカプセル化は Leaf(VTEP)で行われるため、ファブリックリンクだけが VXLAN ヘッダ分の余裕を持てばよい。

アンダーレイのリンク MTU が 1500 のままだと、カプセル化後のパケット(最大 1550 byte)がそのリンクを通過できず、フラグメントが発生するか破棄される。ジャンボフレーム(MTU 9000)を設定することで内側フレームも余裕を持って通せるようになる。

---

## 3. VXLAN の欠点

EVPN 登場前の VXLAN(フラッディング学習方式)には3つの大きな問題があった。

### 問題 1: VTEP 発見の困難さ

VTEP が BUM トラフィックを転送するには、事前に「同じ VNI に参加している全 VTEP のアドレス」を知っている必要がある。しかし EVPN のような制御プレーンがなければ、この情報を自動的に配布する仕組みがない。EVPN 登場前は以下の2方式で対応していた。

```
方式A: ヘッドエンドレプリケーション(静的設定方式)
  各 VTEP に「他の全 VTEP のアドレス」を静的設定
  -> VTEP が増えるたびに全ノードの設定変更が必要

方式B: マルチキャスト
  BUM トラフィックをマルチキャストグループに送信
  -> マルチキャスト対応の物理ネットワークが必要
  -> 管理・運用コストが高い
```

### 問題 2: BUM トラフィックの爆発

**BUM** は以下の頭文字。

| 文字 | 意味 | 具体例 |
|------|------|--------|
| **B** | Broadcast | ARP リクエスト、DHCP Discover |
| **U** | Unknown unicast | MAC テーブルにない宛先への単体送信 |
| **M** | Multicast | マルチキャストグループ宛て通信 |

MAC が不明な宛先への初回通信は全 VTEP に洪水送信される。VTEP が増えるほど BUM トラフィックが爆発的に増大し、帯域と CPU を圧迫する。

### 問題 3: MAC テーブルを制御できない

実際にパケットが流れて初めて MAC を学習する方式(**データプレーン学習**)では:

- どの Leaf にどの MAC がいるかを事前に把握できない
- MAC の移動(VM ライブマイグレーション等)を即座に検知できない
- 古い MAC エントリが残り、誤った VTEP に転送されるリスクがある

---

## 4. EVPN が解決すること

### EVPN の一言定義

> **MAC アドレスや IP アドレスの情報を、BGP を使って制御プレーンで事前に交換する仕組み**

「パケットが流れて初めて学ぶ(データプレーン学習)」から「BGP でルート情報として事前に配布する(制御プレーン学習)」へ。

### VXLAN と EVPN の役割分担

VXLAN と EVPN はそれぞれ異なるプレーンを担当する。

| プレーン | 担当 | 役割 |
|----------|------|------|
| **データプレーン** | VXLAN | L2 フレームを UDP でカプセル化して物理的に転送する |
| **コントロールプレーン** | BGP EVPN | MAC/IP/VTEP 情報を BGP で配布し、転送に必要な情報を揃える |

EVPN がなければ VXLAN はフレームを転送できるが「どこに転送すればよいか」を知る手段がない。EVPN がコントロールプレーンとして情報を事前配布することで、はじめて VXLAN が効率的に動作する。

### データプレーン学習 vs 制御プレーン学習

| | データプレーン学習 | 制御プレーン学習(EVPN) |
|--|------------------|----------------------|
| 学習タイミング | 実際のパケットが届いた時 | BGP セッション確立後すぐ |
| VTEP 発見 | マルチキャスト or 静的設定 | Type-3 ルートで自動発見 |
| MAC/IP の管理 | フラッディングで発見 | Type-2 ルートで事前配布 |
| スケール性 | BUM が増大して限界あり | 制御トラフィックのみ増加 |

### MP-BGP とは

BGP はもともと IPv4 ユニキャストルーティングのために設計された。**MP-BGP (Multiprotocol BGP, RFC 4760)** は BGP を拡張し、IPv4 以外の複数のアドレスファミリを1つの BGP セッションで運べるようにした仕組みである。

拡張のキーとなる要素:

| 用語 | 意味 | EVPN での値 |
|------|------|------------|
| AFI (Address Family Identifier) | アドレス体系の種類を示す番号 | 25 (L2VPN) |
| SAFI (Subsequent AFI) | そのアドレス体系内のサービス種別 | 70 (EVPN) |

MP-BGP の UPDATE メッセージには AFI/SAFI が付与され、受信ルータは「これは EVPN の情報だ」と識別して適切な RIB に格納する。BGP ネイバーの設定で `address-family evpn` を有効にするのがこの AFI/SAFI を使うための宣言にあたる。

### BGP -> MP-BGP -> EVPN という技術階層

```
BGP (Border Gateway Protocol)
 └── MP-BGP (RFC 4760)
      │  「IPv4 以外も運べるように拡張した BGP」
      │
      ├── IPv6 unicast
      ├── VPNv4 (MPLS L3VPN)
      ├── IPv4 multicast
      └── EVPN (Ethernet VPN, RFC 7432)
           └── VXLAN を使う場合は RFC 8365 で規定
```

BGP で配布された MAC/IP 情報は最終的に各 VTEP の **MAC テーブル** に格納される。

なお EVPN 自体はリーフスパイン型トポロジに限定されない。VTEP 間に BGP セッションが張れる IP ネットワークであれば、フルメッシュ型や任意のトポロジでも動作する。リーフスパイン型が主流なのは、大規模 DC での冗長性・スケール性・管理容易性に優れているためである。

EVPN が「何の情報を BGP で運ぶか」を種類ごとに分類した仕組みを **ルートタイプ** と呼ぶ。まず実際のトラフィックフローの中でルートタイプがどう使われるかを見てから、全タイプの詳細を整理する。

RFC: **RFC 4760** - Multiprotocol Extensions for BGP-4
RFC: **RFC 7432** - BGP MPLS-Based Ethernet VPN
RFC: **RFC 8365** - A Network Virtualization Overlay Solution Using EVPN

---

## 5. トラフィックフロー

`./deploy.sh --full` 実行後、Host1 から Host2 に ping を打った場合の時系列。フローの中で **Type-3** と **Type-2** という2つのルートタイプが登場する。それぞれの役割は次のセクションで詳しく説明する。

### Phase 1: deploy 直後 - Type-3 配布

```
[Leaf1]                 [Spine1/2]              [Leaf2/3/4]

BGP EVPN 確立
  |--- Type-3 広告 --->|
  「VTEP 3.3.3.3        |--- Type-3 転送 ------->|
    VNI 10010 参加」    |                         Type-3 受信
                        |<-- Type-3 広告 ---------|
                        |    (各 Leaf から)
Type-3 受信 <-----------|--- Type-3 転送 ------
                        |
```

**この時点での状態:**
- 全 Leaf が「VNI 10010 の VTEP 相手一覧」を把握
- ただし MAC テーブルはまだ空

### Phase 2: Host1 の初回通信 - BUM フラッディング

```
[Host1]         [Leaf1=VTEP1]        [Leaf4=VTEP4]       [Host2]
  |                   |                    |                  |
  |-- ARP Request --->|                    |                  |
  |  「.10.2 の MAC   |                    |                  |
  |   を教えて」      |                    |                  |
  | (ブロードキャスト) |                    |                  |
                      |                    |                  |
                 Host1 の MAC を           |                  |
                 ローカルに学習            |                  |
                      |                    |                  |
                      |-- VXLAN カプセル ->|                  |
                      |   dst VTEP: 6.6.6.6|                  |
                      |   VNI: 10010       |-- ARP Request -->|
                      |   (BUM 転送)       |  (デカプセル)     |
                      |                    |                  |
```

- Type-3 で発見済みの VTEP にのみ転送(Leaf2/3 にも同様に転送される)
- outer IP の dst は 6.6.6.6 だが、**物理的には Spine を経由**してルーティングされる(アンダーレイ eBGP が 6.6.6.6 への経路を持つ)。VTEP 間のトンネルは論理的な直結であり、物理的な直結ではない。

### Phase 3: ARP 応答 - Type-2 伝播

```
[Host2]         [Leaf4=VTEP4]        [Spine1/2]          [Leaf1=VTEP1]
  |                   |                    |                  |
  |-- ARP Reply ----->|                    |                  |
  |  「.10.2 の MAC   |                    |                  |
  |   は BBBB です」  |                    |                  |
                      |                    |                  |
                 Host2 の MAC/IP を        |                  |
                 ローカルに学習            |                  |
                      |                    |                  |
                      |-- Type-2 広告 ---->|                  |
                      |   MAC:BBBB         |-- Type-2 転送 -->|
                      |   IP:.10.2         |                  |
                      |   VTEP:6.6.6.6     |             MAC テーブルに
                      |                    |             BBBB @ 6.6.6.6
                      |                    |             を登録
```

### Phase 4: 定常状態 - VXLAN Unicast

```
[Host1]         [Leaf1=VTEP1]        [Spine1/2]          [Leaf4=VTEP4]       [Host2]
  |                   |                    |                    |                  |
  |--- ping --------->|                    |                    |                  |
  |  dst: .10.2       |                    |                    |                  |
  |  dst MAC: BBBB    |                    |                    |                  |
                      |                    |                    |                  |
                 VXLAN カプセル化          |                    |                  |
                 outer src: 3.3.3.3        |                    |                  |
                 outer dst: 6.6.6.6        |                    |                  |
                 VNI: 10010                |                    |                  |
                      |                    |                    |                  |
                      |--- カプセル化済 -->|--- ルーティング -->|                  |
                      |    UDP/4789        |   アンダーレイ eBGP|                  |
                      |                    |                    |                  |
                      |                    |              デカプセル化             |
                      |                    |              outer ヘッダ除去         |
                      |                    |                    |--- ping -------->|
                      |                    |                    |   dst: .10.2     |
```

BUM トラフィックは初回のみ。以降は完全な Unicast で通信する。

### 補足: ARP Suppression

EVPN の Type-2 ルートには MAC アドレスだけでなく **IP アドレスも含まれている**。これを利用して Leaf が代理 ARP 応答を行う機能を **ARP Suppression** という。

```
[ARP Suppression がない場合]

Host1 が「192.168.10.2 の MAC を教えて」と ARP ブロードキャスト
  -> Leaf1 はそのまま全 VTEP にフラッディング(BUM トラフィック発生)

[ARP Suppression がある場合]

Host1 が「192.168.10.2 の MAC を教えて」と ARP ブロードキャスト
  -> Leaf1 はすでに Type-2 で「192.168.10.2 は MAC:BBBB」を知っている
  -> Leaf1 が ARP ブロードキャストを止めて自分で ARP Reply を返す
  -> BUM トラフィックが発生しない
```

ARP Suppression により、2回目以降の ARP も含めて BUM トラフィックをほぼゼロに抑えられる。EVPN 環境での BUM 削減は「VTEP 発見の自動化(Type-3)」と「ARP Suppression(Type-2 の IP 活用)」の2段階で実現される。

---

## 6. EVPN ルートタイプ

フローの中で Type-3(deploy 直後の VTEP 発見)と Type-2(MAC 学習後の伝播)が登場した。EVPN には全部で5つのルートタイプが定義されており、「何の情報を運ぶか」によって使い分けられる。

| Type | 名前 | 運ぶ情報 | 主な用途 |
|------|------|---------|---------|
| **Type-1** | Ethernet Auto-Discovery | ES (Ethernet Segment) 情報 | マルチホーミング |
| **Type-2** | MAC-IP Advertisement | MAC アドレス・IP アドレス | ホストの MAC/IP 学習 |
| **Type-3** | Inclusive Multicast Ethernet Tag | VTEP IP・VNI | VTEP の自動発見 |
| **Type-4** | Ethernet Segment Route | ES の DR 選出情報 | マルチホーミング |
| **Type-5** | IP Prefix Route | IPv4/IPv6 プレフィックス | L3 ルーティング |

**マルチホーミング**とは、1台のホスト(またはスイッチ)を複数の Leaf に同時接続する冗長構成のこと。Type-1 と Type-4 はこの構成で冗長切り替えや DR(Designated Router)選出を制御するために使われる。今回のラボでは未使用。

今回のラボ(L2 VXLAN)で実際に動くのは **Type-2 と Type-3 だけ**。

### Type-3: VTEP の自動発見 (IMET ルート)

BGP セッション確立直後に自動で広告される(Phase 1 に対応)。

```
Leaf1(3.3.3.3) が Spine に対して広告:
  「私(VTEP=3.3.3.3)は VNI 10010 に参加しています」

Spine が全 Leaf に転送 -> 全 Leaf が VTEP 相手一覧を自動学習
```

### Type-2: MAC/IP の学習と伝播

ホストが通信を開始した後に広告される(Phase 3 に対応)。

```
Host2 の MAC が Leaf4 で学習された後:
  Leaf4 が Spine に対して広告:
  「MAC: BBBB, IP: 192.168.10.2 は VTEP 6.6.6.6(私)にいます」

Spine が全 Leaf に転送 -> 全 Leaf の MAC テーブルに登録
```

RFC: **RFC 7432** (Type-1 to Type-4), **RFC 9136** (Type-5)

---

## 7. アンダーレイに eBGP を使った設計理由

### OSPF から eBGP に変えた理由

lab-ansible ではアンダーレイに OSPF を使ったが、lab-evpn では eBGP に変更している。

| 観点 | OSPF | eBGP (今回) |
|------|------|------------|
| 障害の影響範囲 | SPF 再計算が全体に波及 | AS 単位で閉じる |
| フィルタリング | 制御が難しい | route-map で柔軟に制御 |
| スケール | LSDB が肥大化 | 大規模 DC でも耐えられる |
| 現場での採用 | 中小規模まで | 大規模 DC のデファクト |

### Leaf ごとに別 AS にした理由

```
Spine: AS65000 (共通)
Leaf1: AS65001
Leaf2: AS65002
Leaf3: AS65003
Leaf4: AS65004
```

- Leaf の障害が AS 単位で隔離される(SPF 再計算が他の Leaf に波及しない)
- BGP の route-map によってプレフィックスの広告・受信を Leaf 単位で細かく制御できる
- RFC 7938 で推奨されているパターンそのまま

RFC: **RFC 7938** - Use of BGP for Routing in Large-Scale Data Centers

---

## 8. 重要な設定パラメータと理由

### `next-hop-unchanged` (Spine で必須)

```
[Spine に next-hop-unchanged がない場合]

Leaf1 が EVPN Type-2 を広告:
  next-hop = 3.3.3.3 (Leaf1 の Loopback = VTEP IP)

Spine が Leaf4 に転送する時に next-hop を書き換える:
  next-hop = 1.1.1.1 (Spine1 の Loopback)  <- ここが問題

Leaf4 は「VTEP 1.1.1.1 に VXLAN を張ろうとする」
-> Spine は VTEP ではないので VXLAN が通らない!
```

```
[Spine に next-hop-unchanged がある場合]

Spine が転送する時に next-hop を書き換えない:
  next-hop = 3.3.3.3 (Leaf1 の Loopback) のまま

Leaf4 は「VTEP 3.3.3.3 に VXLAN を張る」
-> アンダーレイ eBGP で 3.3.3.3 への経路があるので通る
```

### `send-community extended` (全 EVPN ピアで必須)

Route Target (RT) は BGP の Extended Community 属性に格納される。これを付けないと RT が転送時に除去され、MAC がインポートされない。

### `route-target import/export` (Leaf の vlan セクションで設定)

どの Leaf 同士で EVPN ルートを共有するかを制御する属性。

```
全 Leaf で統一:
  route-target import 65001:10010
  route-target export 65001:10010

-> 全 Leaf が同じ RT を持つので相互にインポートされる
-> RT が一致しない Leaf は無視される(VRF 分離に使える)
```

### RD (Route Distinguisher) と RT (Route Target) の違い

設定ファイルに `rd` と `route-target` の両方が登場するが、それぞれ異なる目的を持つ。

| 属性 | 目的 | 一意性 | 設定例 |
|------|------|--------|--------|
| **RD** | BGP テーブル内でルートを一意に識別する | Leaf ごとに異なる値 | `3.3.3.3:10010` (Loopback:VNI) |
| **RT** | どの Leaf 間でルートをインポート/エクスポートするか制御する | 全 Leaf で共通の値 | `65001:10010` |

```
[なぜ RD が必要か]

複数の Leaf が同じ MAC を BGP に広告する可能性がある。
RD を付けることで「これは VTEP 3.3.3.3 からの広告」と一意に区別できる。
-> BGP テーブル内での衝突を防ぐ識別子

[RT の役割]

RT はインポート/エクスポートのフィルタとして機能する。
全 Leaf で同じ RT を設定 -> 相互にルートをインポートできる
異なる RT を設定     -> 意図的に分離できる(テナント分離等)
```

RD は「区別するためのラベル」、RT は「共有範囲を決めるポリシー」と覚えると整理しやすい。

### `redistribute learned` (Leaf の vlan セクションで必須)

Leaf がローカルで学習した MAC/IP を EVPN Type-2 ルートとして BGP に広告するためのコマンド。

```
router bgp 65001
   vlan 10
      redistribute learned   <- これがないと MAC を学習しても BGP に広告されない
```

```
[redistribute learned がない場合]

Host1 が Leaf1 に接続 -> Leaf1 が Host1 の MAC をローカル学習
  でも「redistribute learned」がなければ Type-2 広告が生成されない
  -> 他の Leaf は Host1 の MAC を知らない -> フラッディングが続く

[redistribute learned がある場合]

Host1 が Leaf1 に接続 -> Leaf1 が Host1 の MAC をローカル学習
  -> Type-2 ルートを生成して Spine に広告
  -> 全 Leaf の MAC テーブルに Host1 の情報が登録される
```

### `ebgp-multihop 3` + `update-source Loopback0` (EVPN セッションで必須)

EVPN のオーバーレイセッションは P2P リンク IP ではなく Loopback 間で確立する。

```
P2P リンク IP でのセッション(アンダーレイ):
  Leaf1(10.1.0.2) <-> Spine1(10.1.0.1)  直結(1ホップ)

Loopback 間でのセッション(オーバーレイ):
  Leaf1(3.3.3.3) <-> Spine1(1.1.1.1)  2ホップ先
  -> ebgp-multihop 3 がないと TTL 切れで TCP 接続できない
  -> update-source Loopback0 がないと送信元 IP が P2P IP になる
```

### `service routing protocols model multi-agent` (全ノードで必須)

Arista EOS で EVPN を動作させるために必要なルーティングモデルの変更。
デフォルトの `ribd` モデルでは EVPN が動作しない。
configs-init の段階からすでに設定済み(変更には再起動が必要なため)。

---

## 9. 参考 RFC 一覧

| RFC | タイトル | 関連技術 |
|-----|---------|---------|
| **RFC 7348** | Virtual eXtensible Local Area Network (VXLAN) | VXLAN の基本仕様・パケットフォーマット |
| **RFC 4760** | Multiprotocol Extensions for BGP-4 | MP-BGP (EVPN を BGP で運ぶ基盤) |
| **RFC 7432** | BGP MPLS-Based Ethernet VPN | BGP EVPN の基本仕様 (Type-1〜4) |
| **RFC 8365** | A Network Virtualization Overlay Solution Using EVPN | VXLAN + EVPN の組み合わせ仕様 |
| **RFC 9136** | IP Prefix Advertisement in EVPN | Type-5 ルート (L3 EVPN) |
| **RFC 7938** | Use of BGP for Routing in Large-Scale Data Centers | DC での eBGP アンダーレイ設計 |
| **RFC 9135** | Integrated Routing and Bridging in Ethernet VPN (IRB) | L3 EVPN (VRF/IRB、次ラボ候補) |
