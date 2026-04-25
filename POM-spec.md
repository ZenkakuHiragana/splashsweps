# Parallax Occlusion Mapping (POM) 仕様書

インクメッシュのピクセルシェーダーにおけるレイマーチングと座標変換の全体像を記述する。
デバッグと修正の判断基準として使う。

---

## やりたいこと

- ある面の表面形状がインクUV空間のハイトマップによって盛り上がったり、掘り下げられているように見せる。
- 面を真横から見た時であっても、盛り上がりによる稜線の変化が分かるように見せる。
- 表面形状の変化した部分は半透明もしくは透明であることがあるため、塗りの下地となるテクスチャも形状変化に追従して破綻なく見せる。
- 塗りの界面で下地を屈折させて見せる + 下地の掘り下げ量を加味する。
- そのために、インクUV空間には2つのハイトマップがある。
  - 塗り界面のハイトマップ
  - 下地の掘り下げられた深さを示すハイトマップ

---

## 1. 座標系と入力データ契約

### 1.1 ワールド空間 (World Space)

- 単位: Hammer Units
- 基準: マップ座標系
- 頂点の `Position`, `Normal` はこの空間

### 1.2 インクUV空間 (Ink UV Space) — フルスケール

- 単位: 正規化された UV `[0, 1]` 範囲
- `worldToUV` 行列でワールド座標をインクUVに変換する
- `worldToUV` の行1が出力 U 成分、行2が出力 V 成分
- レンダーターゲットのレイアウト:
  - 左半分 (`x < 0.5`): 加算色 + 高さ (`TO_SIGNED` で `[-1, +1]`)
  - 右半分 (`x >= 0.5`): 乗算色 + 深度 (`[0, 1]`)

### 1.3 インクUV空間 — ハーフスケール

- シェーダー内部で実際に使う空間
- `inkUV_half = inkUV_full × 0.5`
- 頂点シェーダーで `baseBumpUV.xy * 0.5` として生成される
- `surfaceClipRange` も `* 0.5` 済み
- インク接空間の XY 行も `* 0.5` 済み

### 1.4 バンプUV空間 (Bump UV Space)

- ワールドのバンプマップテクスチャの UV 座標
- 各頂点の `BumpmapUV` に格納される
- インクUV空間とは独立したマッピング

### 1.5 インク接空間 (Ink Tangent Space)

- ワールド空間のオフセットベクトルをインクUV空間ハーフスケールに変換する 3×3 行列
- 定義:

```
tangentSpaceInk[0] = inkBinormal × 0.5
tangentSpaceInk[1] = inkTangent × 0.5
tangentSpaceInk[2] = worldNormal / HEIGHT_TO_HAMMER_UNITS
```

- `inkTangent` = `worldToUV` の行1
- `inkBinormal` = `worldToUV` の行2
- 頂点シェーダーでは handedness を揃えるために格納先を意図的にスワップしている

### 1.6 ワールド接空間 (World Tangent Space)

- バンプマップ法線をワールド法線に変換する 3×3 行列
- 定義:

```
tangentSpaceWorld[0] = worldTangent (S)
tangentSpaceWorld[1] = worldBinormal (T)
tangentSpaceWorld[2] = worldNormal (N)
```

### 1.7 スクリーン/クリップ空間

- `projPos = mul(float4(pos, 1.0), cModelViewProj)`
- `projPosZ / projPosW` = 非線形深度バッファ値

### 1.8 頂点バッファ → ピクセルシェーダーの入力契約

| 出力 | 内容 | 備考 |
| --- | --- | --- |
| `TEXCOORD0 surfaceClipRange` | `(minV, minU, maxV, maxU) × 0.5` | インクUVの有効範囲 |
| `TEXCOORD1 lightmapUV1And2` | `(s+dS, t+dT, s+2dS, t+2dT)` | ライトマップUV |
| `TEXCOORD2 lightmapUV3_projXY` | `(s+3dS, t+3dT, J[0][0], J[0][1])` | ライトマップUV + Jacobian 行0 |
| `TEXCOORD3 inkUV_worldBumpUV` | `(uvV×0.5, uvU×0.5, bumpU, bumpV)` | インクUV + バンプUV |
| `TEXCOORD4 worldPos_projPosZ` | `(liftedPos.xyz, projPos.z)` | リフト済みワールド位置 |
| `TEXCOORD5 worldBinormalTangentX` | `(binormal.xyz, tangentS.x)` | ワールド binormal |
| `TEXCOORD6 worldNormalTangentY` | `(normal.xyz, tangentS.y)` | ワールド normal |
| `TEXCOORD7 inkTangentXYZWorldZ` | `(inkBinormal×0.5, tangentS.z)` | インク接空間行0 |
| `TEXCOORD8 inkBinormalMeshLift` | `(inkTangent×0.5, liftAmount)` | インク接空間行1 + lift |
| `TEXCOORD9 projPosW_meshRole` | `(projPos.w, role/4, J[1][0], J[1][1])` | 射影W + Mesh Role + Jacobian 行1 |

---

## 2. 中核関数の契約

この章では、界面交点を求めるための計算だけを定義する。
ここでは `clip`、色決定、深度特例、Mesh Role ごとの表示抑制を扱わない。

### 2.1 `BuildTraceRay`

**目的**

視点とプロキシ点から、インクUV空間でのレイを定義する。

**入力**

- `proxyUV : float3`
  - `xy`: インクUV空間ハーフスケール
  - `z`: リフト量に対応する高さ
- `worldPos : float3`
  - リフト後のワールド位置
- `tangentSpaceInk : float3x3`
  - ワールド空間からインクUV空間ハーフスケールへの線形変換
- `eyeWorld : float3`

**出力**

- `eyeUV : float3`
- `rayDir : float3`

**事前条件**

- `proxyUV.xy` はハーフスケール
- `tangentSpaceInk` の XY 行はハーフスケール系である
- `worldPos` と `eyeWorld` はワールド空間

**事後条件**

```
eyeUV = proxyUV + tangentSpaceInk * (eyeWorld - worldPos)
rayDir = proxyUV - eyeUV
```

**失敗条件**

- なし

**禁止事項**

- `clip` しない

### 2.2 `IntersectTraceBox`

**目的**

レイが探索領域 AABB にいつ進入し、いつ退出するかを求める。

**入力**

- `eyeUV : float3`
- `rayDir : float3`
- `surfaceClipRange : float4`
- `heightMin : float`
- `heightMax : float`

**出力**

- `status`
  - `TRACE_BOX_HIT`
  - `TRACE_BOX_MISS`
- `fractionStart : float`
- `fractionEnd : float`

**事前条件**

- `surfaceClipRange` はインクUV空間ハーフスケール
- `heightMin < heightMax`

**事後条件**

- `status = TRACE_BOX_HIT` のとき `fractionStart < fractionEnd`
- `fractionStart = max(fractionEnter, 0)`
- `fractionEnd = fractionExit`

**失敗条件**

- レイが探索領域に入らない場合は `TRACE_BOX_MISS`

**禁止事項**

- `clip` しない
- Mesh Role を見ない

### 2.3 `EvaluateInterfaceField`

**目的**

与えられたインクUV空間上の点が、界面の内側か外側かを符号で返す。

**入力**

- `samplePos : float3`

**出力**

- `field : float`

**定義**

```
field = FetchHeight(samplePos.xy) - samplePos.z
```

**解釈**

- `field > 0` : 点は界面の内側
- `field = 0` : 点は界面上
- `field < 0` : 点は界面の外側

**禁止事項**

- `clip` しない
- 色を返さない
- Mesh Role を見ない

### 2.4 `MarchInterface`

**目的**

探索区間 `[fractionStart, fractionEnd]` の中で界面交点を探す。

**入力**

- `eyeUV : float3`
- `rayDir : float3`
- `fractionStart : float`
- `fractionEnd : float`

**出力**

- `status`
  - `TRACE_HIT_START`
  - `TRACE_HIT_CROSSING`
  - `TRACE_NO_HIT`
- `hitUV : float3`
- `hitFraction : float`
- `traceSteps : int`

**事前条件**

- `fractionStart < fractionEnd`
- 探索区間は探索領域内である

**事後条件**

- `TRACE_HIT_START`: 開始点がほぼ界面上
- `TRACE_HIT_CROSSING`: 区間内で符号変化を検出し、必要なら二分探索で精密化
- `TRACE_NO_HIT`: 区間内で界面交点を見つけられなかった

**禁止事項**

- `clip` しない
- 代用品ヒットを返さない
- Mesh Role を見ない

### 2.5 `TraceInterface`

**目的**

レイ構築、AABB交差、マーチングをまとめて行い、界面交点を返す。

**入力**

- `proxyUV`
- `worldPos`
- `tangentSpaceInk`
- `surfaceClipRange`
- `eyeWorld`

**出力**

- `traceStatus`
  - `TRACE_BOX_MISS`
  - `TRACE_NO_HIT`
  - `TRACE_HIT_START`
  - `TRACE_HIT_CROSSING`
- `hitUV : float3`
- `hitFraction : float`
- `traceSteps : int`

**禁止事項**

- `clip` しない
- 色を決めない
- 深度を書かない
- Mesh Role を見ない

### 2.6 現行実装との対応

現行の `TracePaintInterface` は、概念上は上の 5 関数を1つにまとめている。
ただし現在の実装は関数内で `clip` を行っているため、契約上はまだ純粋関数ではない。

現在の `traceKind` 対応:

- `traceKind = 1` → `TRACE_HIT_START`
- `traceKind = 2` → `TRACE_HIT_CROSSING`
- `traceKind = -1` → `TRACE_NO_HIT` または `TRACE_BOX_MISS`
- `traceKind = 0` → 現行実装に残っているフォールバック用の暫定値

---

## 3. 表示契約

この章では、レイマーチング結果をどの Mesh Role がどう表示に使うかを定義する。
Tri Type / Mesh Role は表示契約の話であり、中核関数の契約には入れない。

### 3.1 共通契約

**入力**

- `traceStatus`
- `hitUV`
- `hitFraction`
- `meshRole`

**共通規則**

- `traceStatus` がヒット系でない場合、表示側が破棄を決める
- 表示側は `traceStatus` を見て debug color を出してよい
- 中核関数側は表示判断をしない
- 第一目標の表示採用条件は、少なくとも次の積集合で決まる
  - `traceStatus` がヒット系である
  - ink ID が空でない
  - `depth + hitUV.z >= 0` を満たす
- 上の採用条件を満たさないピクセルは、最終カラーも alpha も出してはならない
- 第一目標では、ライティング結果そのものより先に「最終的に表示されたかどうか」の visibility mask を検証してよい

### 3.2 `MESH_ROLE_BASE`

**意味**

下地面と同じ位置・向きの基本面。仕様書の `TRI_BASE` に対応する。

**表示契約**

- ヒットした界面を表示対象とする
- メッシュ背面の露出は許可しない
- 第一目標では「地形の上面が見えること」だけを担当する

**第一目標での合格条件**

- 上面の外形が高さマップに対応している
- 欠けや飛びがない
- 交点がない場所だけが消える
- 表示採用条件を満たす領域が連続して見える
- 表示採用条件を満たさない領域に塗りが漏れない

### 3.3 `MESH_ROLE_CEIL`

**意味**

`SIDE` 系だけでは欠けうる上側の見えを補完する面。仕様書の `TRI_CEIL` に対応する。
界面内部視点だけに限定せず、界面外であっても `CEIL` が見えることで連続外形を補う視点では表示候補になりうる。

**表示契約**

- `BASE` と同じ交点計算を使う
- レイマーチングの仕様は `BASE` と共有する
- 異なるのは「どの視点条件で採用するか」だけ
- `SIDE` 系だけで十分なときは `CEIL` は不要でよいが、`SIDE` 系だけだと欠ける視点では `CEIL` が補完面として採用されうる
- `cameraHeight < HEIGHT_TO_HAMMER_UNITS` かどうかは、`CEIL` の必要性と同値ではない
- `CEIL` の採用可否を単独の `cameraHeight` 閾値だけで決めてはならない

**第一目標での合格条件**

- 界面内部から見たときに天井面が欠けない
- `BASE` と連続した外形になる
- 界面外の斜視点で `SIDE` 系だけでは欠ける区間を `CEIL` が補完できる
- `CEIL` を加えたとき、必要な補完区間では visibility が増え、不要領域に塗りが漏れない
- 表示採用条件を満たす領域が連続して見える
- 表示採用条件を満たさない領域に塗りが漏れない

### 3.4 `MESH_ROLE_SIDE_IN`

**意味**

界面の内側側面。奥側の稜線を構成する面。仕様書の `TRI_SIDE_IN` に対応する。

**表示契約**

- 交点が得られたときのみ表示
- メッシュより奥への描画は許可しない
- 第一目標では、側面外形が連続していることだけを見る
- 第一目標では、連続して見えるべき輪郭以外に塗りを出さない
- 視線が側面に浅い角度で入っても、交点が連続して得られる区間では途中で採用が途切れてはならない
- `SIDE_IN` の visibility は `BASE` の top outline だけで代用してはならず、側面自身の連続領域として検証する

### 3.5 `MESH_ROLE_SIDE_OUT`

**意味**

界面の外側側面。手前の稜線と、向こう側の稜線の見えを担う面。仕様書の `TRI_SIDE_OUT` に対応する。

**表示契約**

- 交点が得られたときのみ表示
- 最終段階では奥側への表示を許可する場合がある
- ただし第一目標では深度特例を切り離してよい
- 第一目標では、連続して見えるべき輪郭以外に塗りを出さない

### 3.6 `MESH_ROLE_DEPTH`

**意味**

掘り下げ断面の表示面。仕様書の `TRI_DEPTH` に対応する。

**表示契約**

- 第一目標では後回しにしてよい
- 先に `BASE / CEIL / SIDE_IN / SIDE_OUT` の連続外形を確定させる

### 3.7 現行実装の Mesh Role エンコード

現行の頂点シェーダーでは `TEXCOORD9.y = role / MESH_ROLE_MAX` を渡している。

| 値 | role |
| --- | --- |
| `0.0` | `TRI_CEIL` |
| `0.25` | `TRI_DEPTH` |
| `0.5` | `TRI_BASE` |
| `0.75` | `TRI_SIDE_IN` |
| `1.0` | `TRI_SIDE_OUT` |

---

## 4. 第一目標専用の最小契約

第一目標では、外形が正しく連続しているかだけを確認する。
屈折、下地追従、法線、ライティング、深度特例は切り離してよい。

### 4.1 中核関数側

- `TraceInterface` は `clip` しない
- `TraceInterface` は Mesh Role を見ない
- `TraceInterface` は `hit / no-hit / box-miss` を区別して返す
- `hitUV` と `hitFraction` を返す

### 4.2 表示側

- `meshRole` ごとの色分けはしてよい
- `traceStatus` ごとの色分けはしてよい
- ただし屈折、下地追従、法線、ライティング、深度特例は切る
- 第一目標の render test では、最終カラーの代わりに最終 visibility mask を観測してよい
- visibility mask は「表示採用条件を満たしたピクセルだけが見える」ことを表す
- 第一目標の visual contract は、単一 role の単純平面ではなく、本番相当の role/lift 構成を持つ fixture で検証する
- 少なくとも `BASE / CEIL / SIDE_IN / SIDE_OUT / DEPTH` を含む組み合わせ fixture を持ち、`SIDE_IN / SIDE_OUT / DEPTH` は `LIFT_NONE / LIFT_UP / LIFT_DOWN` の混在で縦面を表現する

### 4.3 合格条件

- `BASE` の上面外形が欠けない
- `CEIL` が内部視点で欠けない
- `CEIL` は外部斜視点でも、`SIDE` だけでは欠ける区間を補完できる
- `SIDE_IN / SIDE_OUT` の輪郭が連続する
- `TRACE_NO_HIT` と `TRACE_BOX_MISS` を色で区別できる
- 「消えた理由」が `clip` ではなく `status` で追える
- `TRACE_NO_HIT` と `TRACE_BOX_MISS` では最終表示に塗りが残らない
- ink ID が空の領域には最終表示に塗りが残らない
- 表示採用条件を満たす連続領域に不要な穴が開かない
- `SIDE_IN` は浅い視線角でも連続して見えるべき区間で欠けない
- `SIDE_OUT` は浅い視線角でも連続して見えるべき区間で欠けず、禁止領域に塗りが漏れない
- `DEPTH` は第一目標で主輪郭を担わず、元のマップジオメトリの手前で不要な輪郭や漏れを作らない
- 第一目標の必須視点には、少なくとも `cameraHeight > HEIGHT_TO_HAMMER_UNITS`、`cameraHeight < HEIGHT_TO_HAMMER_UNITS`、浅い斜視点を含める

### 4.4 テスト層契約

第一目標の自動テストは、少なくとも次の 4 層に分ける。
各層の合格は別々に扱い、上位層の失敗を下位層の通過で代用してはならない。

- **Core trace contracts**
  - `BuildTraceRay` / `IntersectTraceBox` / `EvaluateInterfaceField` / `MarchInterface` / `TraceInterface`
  - ここでは中核関数の数学的契約だけを扱う
  - 表示採用、ink ID、depth 特例、Mesh Role 採用は扱わない
- **Transport contracts**
  - 本物の頂点シェーダーが `surfaceClipRange`、`inkUV`、接空間行、`liftAmount`、Mesh Role、Jacobian を spec 通りにピクセルシェーダーへ運ぶこと
  - 実際の `inkmesh_vs30.hlsl` を通した観測で検証する
- **Display adoption/rejection contracts**
  - 表示の採用可否と、棄却理由の分類を扱う
  - 少なくとも `TRACE_BOX_MISS`、`TRACE_NO_HIT`、empty ink、negative thickness、visible hit を区別できること
  - 単なる visibility mask だけでなく、棄却理由を追跡できる観測面を持つこと
- **Production visual contracts**
  - 本物の VS + PS + 3D capture を通した最終可視性と輪郭連続性を扱う
  - ここでは canonical fixture と required view classes に対する連続領域、禁止領域への漏れ、主要 role の見えを検証する
  - canonical fixture は少なくとも 4 種以上とし、単一 role 平面ではなく `surfacebuilder.lua` の role/lift 構成を模した組み合わせ fixture を使う
  - required view classes には、少なくとも `cameraHeight > HEIGHT_TO_HAMMER_UNITS`、`cameraHeight < HEIGHT_TO_HAMMER_UNITS`、浅い斜視点を含める
  - `CEIL` の contract は、`SIDE` だけでは欠ける fixture に対して `CEIL` を加えたとき必要区間で visibility が増え、不要区間では増えないこととして表現してよい

### 4.5 テストケース設計上の禁止事項

- `t.note` だけで合否が決まらないケースを、契約テストに含めない
- デバッグ色の一致だけで production visual contract を満たしたとみなさない
- 本物の VS を通さない観測で transport contract を満たしたとみなさない
- `visible / hidden` の 2 値だけで、消えた理由の契約を満たしたとみなさない
- 単一 role の単純平面を、第一目標の production visual contract の十分条件にしてはならない

---

## 5. 第二段階以降の契約

第一目標の外形が安定したあとに扱う要素。

### 5.1 バンプUV変換

#### 5.1.1 定義

```
inkProxyUV = inkUV_worldBumpUV.xy
bumpProxyUV = inkUV_worldBumpUV.zw
inkHitOffset = hitUV.xy - inkProxyUV
hitBumpOffset = J * inkHitOffset
```

#### 5.1.2 Jacobian の定義

- `J × ΔinkUV_full = ΔbumpUV`
- `J` は Lua `ComputeBumpFromInk` で三角形ごとに計算される 2×2 行列

#### 5.1.3 既知の問題

- 現在の実装では `inkHitOffset` がハーフスケール、`J` はフルスケール定義
- したがって `J × ΔinkUV_half = 0.5 × ΔbumpUV`

### 5.2 パララックスオフセット

```
thickness = max(depth + hitUV.z, 0.0)
parallaxVec = tangentViewDir.xy / max(tangentViewDir.z, 1e-3)
uvDepthParallax = -parallaxVec * thickness / (tangentScaleSqr * texTransformScale)
```

### 5.3 フレームバッファ追従

`g_NeedsFrameBuffer > 0` の場合、バンプUVオフセットをスクリーン空間へ逆変換して下地を追従させる。

### 5.4 深度書き込み

- `TRI_SIDE_OUT` は奥側表示を許可する場合がある
- それ以外はメッシュ背面の露出を防ぐ
- これは表示契約側の特例であり、中核関数には入れない

### 5.5 視線方向の計算

```
hitWorldPos = lerp(g_EyePos, worldPos, hitFraction)
viewVec = g_EyePos - hitWorldPos
viewDir = normalize(viewVec)
```

数式上は正しいが、`hitFraction` が極端な値になると数値的に不安定になりうる。

---

## 6. 現行実装の問題一覧

### 6.1 レイマーチング中核と表示契約が分離されていない

- `TracePaintInterface` が `clip` を含んでいる
- `TRACE_BOX_MISS` と `TRACE_NO_HIT` を区別しにくい
- 表示側の都合が中核関数に混ざっている

### 6.2 Jacobian のスケール不一致

- `J` はフルスケール定義
- `inkHitOffset` はハーフスケール

### 6.3 Mesh Role ごとの表示契約が中核計算の議論と混線しやすい

- `CEIL` が欠ける問題は、原則として表示採用規則または可視性判定の問題として切り分けるべき
- `TraceInterface` 自体は `CEIL` と `BASE` を区別しない方が検証しやすい

### 6.4 フォールバックヒットは暫定実装である

- `traceKind = 0` は契約上の正式なヒット種別ではなく、現行実装の暫定値

---

## 7. デバッグ方法

### 7.1 組み込みデバッグモード (`$c0_w` で切替)

| 値 | 名前 | 表示内容 | 何を確認するか |
| --- | --- | --- | --- |
| `0` | 通常 | 最終カラー | — |
| `1` | TraceKind | ヒット種別の色分け | `TRACE_HIT_START / TRACE_HIT_CROSSING / miss` の分布 |
| `2` | TexelFraction | テクセル内の小数部分 | UVがテクセル境界をまたいでいないか |
| `3` | SnapDelta | `inkUV` と `pixelUV` の差 | スナップ前後のズレ |
| `4` | HeightDepth | `R=height, G=hitHeight, B=depth` | 高さと深度が妥当か |
| `5` | InkIDs | `R=ID1/255, G=ID2/255, B=idBlend` | インクIDの分布 |
| `6` | TraceSteps | ステップ数/MAX | 精度不足の場所 |

### 7.2 テストビルド専用モード (`INKMESH_TEST_BUILD` のみ)

| 値 | 名前 | 表示内容 | 何を確認するか |
| --- | --- | --- | --- |
| `8` | Alpha | `alpha / depth` | alpha と深度の分離 |
| `9` | Depth | `depth / alpha` | 深度特例の差 |
| `10` | MaterialFetch | 材料パラメータ | マテリアル参照の取り出し |
| `11` | RoleTransport | `projPosW_meshRole.y` | Mesh Role が VS から PS に運ばれるか |
| `12` | AdoptionDecision | 採用理由色 | `TRACE_BOX_MISS` / `TRACE_NO_HIT` / empty ink / negative thickness / visible hit |
| `13` | JacobianOffset | `bumpProxyUV` / `inkHitOffset` / `hitBumpOffset` / `bumpUV` | Jacobian のスケールとオフセット |
| `14` | TraceTransport | `proxyUV` / `eyeUV` / `rayDir` / box fractions | レイ構築と AABB 交差の観測 |
| `15` | SurfaceTransport | `surfaceClipRange` / `inkUV` / lift | VS からの範囲・UV・リフト伝達 |
| `16` | BasisTransport | `inkTangentXYZWorldZ` / `inkBinormalMeshLift` / `worldNormalTangentY` | 接空間 3 行の伝達 |
| `17` | TailTransport | `lightmapUV3_projXY.zw` / `projPosW_meshRole.zw` | Jacobian 行0/1 と role 末尾 |

### 7.3 推奨デバッグ手順

1. `TRACE_BOX_MISS` と `TRACE_NO_HIT` を色で分離して確認できる状態を作る
2. `BASE / CEIL / SIDE_IN / SIDE_OUT` を役割色で可視化する
3. まず外形が連続するかだけを見る
4. その後で Jacobian、下地追従、深度特例を戻す

---

## 8. 用語集

| 用語 | 意味 |
| --- | --- |
| プロキシ点 (proxy) | 頂点シェーダーでリフトしたメッシュ表面の点 |
| ハーフスケール | インクUVを 0.5 倍した空間 |
| ヤコビアン (J) | インクUV空間からバンプUV空間への 2×2 変換行列 |
| リフト量 (liftAmount) | メッシュを法線方向に持ち上げる量 |
| thickness | インクの厚み。`max(depth + hitHeight, 0)` |
| TRACE_BOX_MISS | AABB に入れなかった |
| TRACE_NO_HIT | AABB には入ったが界面交点を見つけられなかった |
| TRACE_HIT_START | 開始点がほぼ界面上 |
| TRACE_HIT_CROSSING | 区間内で符号変化から交点を検出した |
