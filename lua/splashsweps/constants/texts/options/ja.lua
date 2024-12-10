AddCSLuaFile()
return {Options = {
    AllowSprint = "ダッシュを許可する",
    AvoidWalls = "壁を避けて狙う",
    AvoidWalls_help = "インクが壁に吸われないようにする。",
    TransformOnCrouch = "変形する",
    TransformOnCrouch_help = "しゃがみ時に変形するか、屈んだヒトになるか。",
    CanDrown = "水没時に死ぬ",
    CanHealInk = "インク内でHP回復",
    CanHealInk_help = false,
    CanHealStand = "インク外でHP回復",
    CanHealStand_help = false,
    CanReloadInk = "インク内でインク回復",
    CanReloadInk_help = false,
    CanReloadStand = "インク外でインク回復",
    CanReloadStand_help = false,
    DoomStyle = "DOOMスタイル",
    DoomStyle_help = "一人称視点で武器が中央に配置される。",
    DrawCrosshair = "照準の描画",
    DrawInkOverlay = "インクオーバーレイの描画",
    DrawInkOverlay_help = "一人称視点でインクに潜った時、画面に水のエフェクトがかかる。",
    Enabled = "Splash SWEPsの有効化",
    ExplodeEveryone = "撃破時に必ず爆発する",
    ExplodeEveryone_help = [[チェックを入れると、倒した相手が必ず爆発する。
チェックを外すと、このアドオンの武器を持っている相手のみ撃破時に爆発するようになる。]],
    FF = "同士討ちの有効化",
    Gain = {
        __printname = "各種パラメータ",
        DamageScale = "与ダメージ倍率[%]",
        HealSpeedInk = "体力回復速度[%] (インク内)",
        HealSpeedStand = "体力回復速度[%] (インク外)",
        MaxHealth = "最大ヘルス",
        InkAmount = "インクタンク容量",
        ReloadSpeedInk = "インク回復速度[%] (インク内)",
        ReloadSpeedStand = "インク回復速度[%] (インク外)",
    },
    HideInk = "マップ上のインクを非表示にする",
    HideInk_help = "チェックを入れると、マップ上に塗られたインクが非表示になる。",
    HurtOwner = "自爆を有効化",
    InkColor = "インクの色",
    LeftHand = "左利き",
    LeftHand_help = "一人称視点で武器が左側に表示される。",
    MoveViewmodel = "壁を避けて狙うとき、ビューモデルを動かす",
    MoveViewmodel_help = "「壁を避けて狙う」が有効のとき、一人称視点で腕が動く。",
    NewStyleCrosshair = "照準のスタイルを別パターンにする",
    NPCInkColor = {
        __printname = "NPCのインクの色",
        Citizen = "市民",
        Combine = "コンバイン",
        Military = "ミリタリー",
        Zombie = "ゾンビ",
        Antlion = "アントライオン",
        Alien = "エイリアン",
        Barnacle = "バーナクル",
        Others = "その他",
    },
    TakeFallDamage = "落下ダメージを有効化",
    ToggleADS = "アイアンサイト切り替え",
    ToggleADS_help = "アイアンサイトを長押しで覗くか、切り替えて覗くか。",
    TranslucentNearbyLocalPlayer = "プレイヤーがカメラに近い時に透明化する",
    TranslucentNearbyLocalPlayer_help = false,
    weapon_splashsweps_shooter = {
    },
}}