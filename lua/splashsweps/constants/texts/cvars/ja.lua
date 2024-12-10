AddCSLuaFile()
return {CVars = {
    AllowSprint = "走れるようにする。 (1: 有効, 0: 無効)",
    AvoidWalls = "インクが壁に吸い付かないようにする。 (1: 有効, 0: 無効)",
    TransformOnCrouch = "しゃがんだ時に変形する。 (1: 有効, 0: 無効)",
    CanDrown = "水没した時に死ぬかどうか。 (1: 有効, 0: 無効)",
    CanHealInk = "インクの中で体力が回復する。 (1: 有効, 0: 無効)",
    CanHealStand = "インクの外で体力が回復する。 (1: 有効, 0: 無効)",
    CanReloadInk = "インクの中でインクが回復する。 (1: 有効, 0: 無効)",
    CanReloadStand = "インクの外でインクが回復する。 (1: 有効, 0: 無効)",
    Clear = "マップ上のすべてのインクを消去する。",
    DoomStyle = "ビューモデルを画面中央に置く (1: 有効, 0: 無効)",
    DrawCrosshair = "照準を描画する。 (1: 有効, 0: 無効)",
    DrawInkOverlay = "一人称視点でインクのオーバーレイを描画する。 (1: 有効, 0: 無効)",
    Enabled = "Splash SWEPsを有効化する。 (1: 有効, 0: 無効)",
    ExplodeEveryone = "Splash SWEPsの武器を持っていない敵も撃破した時に爆発する。 (1: 有効, 0: 無効)",
    FF = "同士討ちを有効にする。 (1: 有効, 0: 無効)",
    Gain = {
        DamageScale = "武器が与えるダメージにかかる倍率。 例えば200を設定すると与えるダメージが2倍になる。",
        HealSpeedInk = "インク内における体力回復速度の倍率。 例えば200を設定すると体力回復にかかる時間が半分になる。",
        HealSpeedStand = "インク外における体力回復速度の倍率。 例えば200を設定すると体力回復にかかる時間が半分になる。",
        MaxHealth = "プレイヤーの最大ヘルス。",
        InkAmount = "インクタンクの容量。",
        ReloadSpeedInk = "インク内におけるインク回復速度の倍率。 例えば200を設定するとインク回復にかかる時間が半分になる。",
        ReloadSpeedStand = "インク外におけるインク回復速度の倍率。 例えば200を設定するとインク回復にかかる時間が半分になる。",
    },
    HideInk = "マップに塗られたインクを非表示にする。 (1: 有効, 0: 無効)",
    HurtOwner = "各種爆風で自爆するかどうか。 (1: 有効, 0: 無効)",
    InkColor = "インクの色を設定する。使用可能な値は以下の通り。:\n",
    LeftHand = "左手で武器を構える。 (1: 有効, 0: 無効)",
    MoveViewmodel = "壁を避けて狙う時、ビューモデルを動かす。 (1: 有効, 0: 無効)",
    NewStyleCrosshair = "照準の動き方を別パターンにする。 (1: 有効, 0: 無効)",
    NPCInkColor = {
        Citizen = "市民のインクの色。",
        Combine = "コンバインのインクの色。",
        Military = "\"ミリタリー\" NPCのインクの色。",
        Zombie = "ゾンビのインクの色。",
        Antlion = "アントライオンのインクの色。",
        Alien = "エイリアンのインクの色。",
        Barnacle = "バーナクルのインクの色。",
        Others = "その他のNPCのインクの色。",
    },
    Playermodel = "三人称モデル。使用可能な値は以下の通り。:\n",
    ResetCamera = "カメラリセットコマンド。",
    RTResolution = [[インクの描画システムで用いるRenderTargetの設定。
この変更を反映するにはGMODの再起動を必要とする。
また、高解像度になるほど多くのVRAM容量が要求される。
ビデオメモリの容量が十分にあることを確認してから変更することを推奨する。
0: SplashSWEPsのロード中にクラッシュした場合の値である。
    解像度は2048x2048、VRAM使用量は32MBである。
1: RTの解像度は4096x4096である。
    このオプションは128MBのVRAMを必要とする。
2: RTの解像度は2x4096x4096である。
    オプション1の2倍の面積に等しい解像度を持つ。
    このオプションは256MBのVRAMを必要とする。
3: 8192x8192、512MB。
4: 2x8192x8192、1GB。
5: 16384x16384、2GB。]],
    TakeFallDamage = "武器を持っている時、落下ダメージを受けるかどうか。 (1: 受ける, 0: 受けない)",
    ToggleADS = "アイアンサイト切り替え(1)/ホールド(0)",
    TranslucentNearbyLocalPlayer = "プレイヤーがカメラに近い時に透明化するかどうか。 (1: する, 0: しない)",
    weapon_splashsweps_shooter = {
    },
}}