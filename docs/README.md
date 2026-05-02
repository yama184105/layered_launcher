# Layered Launcher — Landing Page

公開用 GitHub Pages のソース。

## 公開手順 (一度だけ)

1. このブランチを `master` にマージ (まだ未マージなら)
2. GitHub の **Settings → Pages**
3. **Source**: `Deploy from a branch`
4. **Branch**: `master` / **Folder**: `/docs`
5. **Save**
6. 1〜2 分後 `https://yama184105.github.io/layered_launcher/` で公開

## ファイル

```
docs/
├── index.html              トップページ (β テスター募集)
├── privacy.html            プライバシーポリシー (Play Store 必須)
├── styles.css              共通スタイル
├── .nojekyll               Jekyll を無効化 (アンダースコア始まりのファイルを処理させない)
└── assets/
    └── screenshots/        スクリーンショット (Galaxy で撮影して差し込む)
```

## 差し替え必須箇所 (公開前にやる)

### 1. 応募フォームの URL

`index.html` 内の `https://forms.gle/REPLACE_WITH_YOUR_FORM_ID` を、Google Forms で作成した
実際の応募フォーム URL に書き換える。

#### Google Forms の質問項目 (推奨)

- Gmail アドレス (必須・回答者が直接入力)
- 普段使っているランチャー (例: Pixel Launcher / Niagara / Olauncher / 不明)
- なぜ興味を持ったか (短文)
- 端末モデル (例: Galaxy S22)
- Twitter/X ハンドル (任意・進捗連絡用)

### 2. スクリーンショット

`assets/screenshots/` に Galaxy で撮影した PNG を置き、`index.html` の
`<div class="screenshot-placeholder">` 部分を `<img src="...">` に書き換える。

最低 3 枚:
- 0F (ホーム画面)
- 1F or 任意の階層 (アプリ一覧)
- 設定画面のアコーディオン

推奨 5 枚:
- 上記 + フロア遷移アニメ途中 + 緊急モード起動中

### 3. 開発者からの言葉 (philosophy セクション)

`#philosophy` セクションの blockquote は仮置き。実際の言葉に書き換えると刺さりやすい。

### 4. プライバシーポリシー詳細

`privacy.html` の「最終更新日」と各項目を、実装に合わせて微調整。
特に「権限」セクションは AndroidManifest.xml と一致させる。

## ローカル確認

```bash
# Python 3 系 (確認用簡易サーバ)
cd docs
python3 -m http.server 8000
# → http://localhost:8000/
```

## SEO / OGP (後で)

- `og:image` 用の画像を `assets/og.png` (1200x630) で用意して `index.html` のメタタグに追加
- `favicon.ico` を追加
