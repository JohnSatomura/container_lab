# L2 EVPN と L3 EVPN の違い

lab-evpn (L2 EVPN) と lab-l3evpn (L3 EVPN) の構成・動作・設定の違いをまとめる。

---

## 1. 一言での違い

| | L2 EVPN (lab05) | L3 EVPN (lab06) |
|-|-----------------|-----------------|
| **目的** | 異なる Leaf に接続されたホストを**同一 L2 セグメント**として扱う | 異なる Leaf に接続されたホスト間を**サブネット越えで L3 ルーティング**する |
| **転送方式** | L2 フォワーディング (MAC ベース) | L3 ルーティング (IP ベース) + VRF テナント分離 |
| **ゲートウェイ** | ホスト側に設定 (Leaf は GW を持たない) | Leaf が Anycast GW を持つ (分散ゲートウェイ) |

---

## 2. トポロジ比較

### L2 EVPN (lab05)

```
Spine1 / Spine2 (AS65000)
  |    (eBGP アンダーレイ + EVPN オーバーレイ)
Leaf1 / Leaf2 / Leaf3 / Leaf4
  |                          |
Host1 (192.168.10.1/24)  Host2 (192.168.10.2/24)
            <- 同じサブネット ->
```

- Host1 と Host2 は **同じ** /24 セグメント (192.168.10.0/24)
- VXLAN で L2 延伸しているため、ホストから見ると同一スイッチに繋がっているように見える
- Leaf は L2 スイッチとして動作し、ルーティングしない

### L3 EVPN (lab06)

```
Spine1 / Spine2 (AS65000)
  |    (eBGP アンダーレイ + EVPN オーバーレイ)
Leaf1 (AS65001)               Leaf2 (AS65002)
GW 192.168.10.254             GW 192.168.20.254
GW 192.168.30.254
  |            |                      |
Host1        Host3                 Host2
.10.10/24    .30.10/24             .20.10/24
(TENANT_A)  (TENANT_B)            (TENANT_A)
        <- 異なるサブネット ->
```

- Host1 (192.168.10.0/24) と Host2 (192.168.20.0/24) は **異なる** /24 セグメント
- Leaf が Anycast GW として機能し、VRF 内でルーティングする
- TENANT_A / TENANT_B は VRF で完全分離

---

## 3. 使用する EVPN ルートタイプ

| ルートタイプ | 用途 | L2 EVPN | L3 EVPN |
|------------|------|---------|---------|
| **Type-2** (MAC-IP) | MAC・IP アドレスの学習・伝播 | 使用 | 使用 |
| **Type-3** (IMET) | VTEP の自動発見 | 使用 | 使用 |
| **Type-5** (IP Prefix) | サブネット単位の IP プレフィックス広告 | **未使用** | **使用** |

### Type-5 が必要な理由

L2 EVPN では「どの MAC がどの VTEP にいるか」を Type-2 で知ればよい。

L3 EVPN では「どのサブネット (192.168.20.0/24) がどの VTEP (4.4.4.4) にあるか」という **ルーティング情報** を伝播させる必要がある。これを担うのが Type-5 (IP Prefix) ルート。

```
[L2 EVPN の EVPN テーブル]
  RD: 3.3.3.3:10010  imet  3.3.3.3    <- Type-3: VTEP 発見
  RD: 6.6.6.6:10010  mac-ip BBBB      <- Type-2: MAC 学習

[L3 EVPN の EVPN テーブル (追加分)]
  RD: 3.3.3.3:100  ip-prefix 192.168.10.0/24  <- Type-5: サブネット広告
  RD: 4.4.4.4:100  ip-prefix 192.168.20.0/24  <- Type-5: サブネット広告
```

---

## 4. VNI の種類

### L2 EVPN: L2VNI のみ

```
VLAN 10  <->  VNI 10010   (L2 セグメントの識別子)
```

L2VNI は「どの L2 ドメイン (VLAN) のパケットか」を識別するために使う。

### L3 EVPN: L2VNI + L3VNI

```
VLAN 10  <->  VNI 10010   (L2VNI: L2 セグメントの識別子)
VLAN 20  <->  VNI 10020   (L2VNI)
VRF TENANT_A  <->  VNI 50001   (L3VNI: VRF の識別子)
VRF TENANT_B  <->  VNI 50002   (L3VNI)
```

**L3VNI** は VRF 専用の VNI。Leaf 間で L3 転送するときのカプセル化に使う。

```
L2VNI を使うケース: 同じ VRF 内の同じ VLAN 間通信 (L2 延伸)
L3VNI を使うケース: 同じ VRF 内の異なる VLAN 間通信 (Symmetric IRB)
```

---

## 5. パケット転送フローの違い

### L2 EVPN: Host1 -> Host2 (同一 L2 セグメント)

```
Host1 (192.168.10.1)
  |  宛先 MAC: Host2 の MAC
  v
Leaf1 (VTEP: 3.3.3.3)
  |  VXLAN カプセル化
  |  outer src: 3.3.3.3, outer dst: 6.6.6.6
  |  VNI: 10010 (L2VNI)   <- VLAN 単位の識別子
  v
Leaf4 (VTEP: 6.6.6.6)
  |  VXLAN デカプセル化
  |  L2 フォワーディング (MAC テーブル参照)
  v
Host2 (192.168.10.2)
```

- Leaf は **L2 フォワーディング** のみ。IPを見ない。
- ホストから見ると VLAN 内の直接通信に見える (TTL は減らない)

### L3 EVPN: Host1 -> Host2 (異なるサブネット / Symmetric IRB)

```
Host1 (192.168.10.10)
  |  宛先 IP: 192.168.20.10
  |  宛先 MAC: Anycast GW (00:1c:73:00:00:01)  <- GW 宛
  v
Leaf1 (Anycast GW + VTEP: 3.3.3.3)
  |  TENANT_A VRF でルーティング
  |  宛先 192.168.20.0/24 -> Type-5 ルート -> VTEP: 4.4.4.4
  |  VXLAN カプセル化
  |  outer src: 3.3.3.3, outer dst: 4.4.4.4
  |  VNI: 50001 (L3VNI)   <- VRF 単位の識別子
  v
Leaf2 (VTEP: 4.4.4.4)
  |  L3VNI (50001) -> TENANT_A VRF を特定
  |  TENANT_A VRF でルーティング
  |  192.168.20.10 -> Vlan20 SVI 経由で Host2 へ
  v
Host2 (192.168.20.10)
```

- Leaf が **L3 ルーティング** を行う (Ingress Leaf と Egress Leaf の両方)。
- 両方向で L3VNI を使う = **Symmetric IRB** (対称 IRB)
- ホストから見ると TTL が 2 減る (Leaf1 でルーティング + Leaf2 でルーティング)

---

## 6. VRF によるテナント分離

L2 EVPN には VRF の概念がない。全ホストが同一の転送ドメインに属する。

L3 EVPN では VRF を使ってテナントを完全分離する。

```
TENANT_A (VRF: TENANT_A, L3VNI: 50001, RT: 100:100)
  Host1 (192.168.10.10) <-> Host2 (192.168.20.10) : ping 成功

TENANT_B (VRF: TENANT_B, L3VNI: 50002, RT: 200:200)
  Host3 (192.168.30.10)

TENANT_A <-> TENANT_B : ping 失敗 (VRF 間ルート交換なし)
```

RT (Route Target) が異なれば EVPN ルートはインポートされないため、異なる VRF のサブネットには到達できない。

---

## 7. Anycast Gateway (分散ゲートウェイ)

L2 EVPN ではホストが自分でデフォルト GW を持つ。Leaf は GW の役割を担わない。

L3 EVPN では各 Leaf が同じ IP・同じ MAC のゲートウェイ (Anycast GW) を持つ。

```
[L2 EVPN]
Host1: 192.168.10.1/24  GW: (外部ルータ等)
Host2: 192.168.10.2/24  GW: (外部ルータ等)
  Leaf は L2 スイッチとして透過的に動作

[L3 EVPN の Anycast GW]
Leaf1: ip virtual-router mac-address 00:1c:73:00:00:01
       interface Vlan10 -> ip address virtual 192.168.10.254/24
Leaf2: ip virtual-router mac-address 00:1c:73:00:00:01  <- 同じ MAC
       interface Vlan20 -> ip address virtual 192.168.20.254/24

Host1 の GW: 192.168.10.254 (Leaf1 が応答)
Host2 の GW: 192.168.20.254 (Leaf2 が応答)
```

全 Leaf で MAC を共通にする理由は、ホストが Leaf 間を移動 (VM マイグレーション等) しても ARP の再解決が不要になるため。

---

## 8. 設定の差分

### Spine 側

Spine は L2/L3 EVPN 共通設定。`next-hop-unchanged` が必須なのは同じ。

### Leaf 側の差分

| 設定項目 | L2 EVPN (lab05) | L3 EVPN (lab06) |
|---------|-----------------|-----------------|
| `vrf instance` | なし | あり (`TENANT_A`, `TENANT_B`) |
| `ip routing vrf` | なし | あり (VRF ごとに有効化) |
| L3VNI transit VLAN | なし | あり (`vlan 100`, `vlan 110`) |
| `ip virtual-router mac-address` | なし | あり (全 Leaf 共通 MAC) |
| SVI の IP | なし | `ip address virtual` (Anycast GW) |
| `vxlan vrf ... vni ...` | なし | あり (L3VNI マッピング) |
| BGP `vlan` セクション | `redistribute learned` | `redistribute learned` |
| BGP `vrf` セクション | なし | `redistribute connected` (Type-5 生成) |

### BGP `redistribute` の違い

```
[L2 EVPN]
router bgp 65001
   vlan 10
      redistribute learned   <- ローカル学習 MAC を Type-2 として広告

[L3 EVPN]
router bgp 65001
   vlan 10
      redistribute learned   <- 同上 (L2 部分は共通)
   vrf TENANT_A
      redistribute connected <- VRF 内の connected ルートを Type-5 として広告
```

`redistribute learned` は「MAC テーブルに学習したエントリを EVPN に入れる」。
`redistribute connected` は「VRF 内の直接接続ルート (サブネット) を EVPN に入れる」。

### cEOS 設定時の注意

cEOS では `ip routing vrf` を `vrf instance` より**後**に記述する必要がある。

```
# 誤り: vrf instance が存在しない状態で ip routing vrf を適用 -> 無視される
ip routing vrf TENANT_A   <- VRF がまだ存在しないので適用されない
vrf instance TENANT_A

# 正しい
vrf instance TENANT_A
ip routing vrf TENANT_A   <- VRF 作成後に適用
```

---

## 9. ユースケース

| ユースケース | L2 EVPN | L3 EVPN |
|------------|---------|---------|
| VM ライブマイグレーション (IP 変えずに別ラックへ移動) | 向いている | 不要 (L3 転送で解決) |
| マルチテナント DC (テナント間の完全分離) | 困難 | 向いている (VRF 分離) |
| 異なるサブネット間のルーティング | 別途外部ルータが必要 | Leaf の Anycast GW で完結 |
| 大規模 DC の East-West トラフィック最適化 | 不十分 | L3VNI + Type-5 で最適化 |

---

## 10. まとめ

```
L2 EVPN
  「L2 を伸ばす」
  Type-2/3 で MAC を配布 -> VLAN を VTEP 間で延伸
  ホストは同一サブネット内にいる感覚

        |
        | L3 EVPN で追加される要素
        v

L3 EVPN
  「L3 で繋ぐ」
  Type-5 で IP プレフィックスを配布 -> VRF 内のサブネット間をルーティング
  Anycast GW が分散ルーティングを担う
  L3VNI が VRF 単位のトンネル識別子として機能
  VRF によるテナント完全分離が可能
```

L3 EVPN は L2 EVPN の仕組みをそのまま継承しつつ、VRF・L3VNI・Type-5・Anycast GW という4つの要素を追加することで実現される。L2 EVPN を理解していれば、この4点の差分を押さえるだけで L3 EVPN の全体像を把握できる。
