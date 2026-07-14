# CLAUDE.md — 大学入試数学 過去問データベース

## プロジェクト概要

大学入試数学の過去問を「大学 × 年度 × 大問」単位でレコード化し、**単元タグ**と**解法キータグ**の二軸で絞り込み検索できるデータベースサイト。

- ユーザーは各問題の難易度(★1〜5)を投票できる(同一端末は上書き)
- 各問題に講評コメントを書き込める(MathJax対応、`$...$` で数式)
- **問題文・解説は掲載しない**(著作権許諾フェーズ以降の課題)

## アーキテクチャ

| 項目 | 内容 |
|---|---|
| ホスティング | GitHub Pages |
| フロント | 単一 `index.html`(CSS/JS同梱)、SPA的にJSで3画面を切替 |
| ライブラリ | CDN読込のみ(supabase-js v2 / MathJax v3)。ビルド工程なし |
| バックエンド | Supabase(PostgreSQL + RLS)。URLとanon keyは `index.html` 冒頭の定数プレースホルダに後で差し込む |
| 数式表示 | MathJax(inline math: `$...$`) |
| デザイン | 明るい配色(クリーム系ライトテーマ)・モバイルファースト(iPhone/iPad主体) |

Supabase未接続(プレースホルダのまま)の場合は**デモモード**として動作し、JS内のサンプルデータで全画面を確認できる(変更はページ再読込で消える)。

## データ設計

タグはDBに持たず、コード内定数のID(int)を配列で保持する。
※仕様メモでは `unit_tags int` / `method_tags int` だったが、1問に複数タグを付けるため `int[]` としている。

### テーブル定義SQL(実行はSupabaseのSQL Editorで手動)

```sql
create table problems (
  id          bigint generated always as identity primary key,
  university  text not null,                -- 例: 東京大学
  year        int  not null,                -- 例: 2026
  exam_type   text not null default '',     -- 例: 前期理系(なければ空)
  question_no int  not null,                -- 大問番号
  unit_tags   int[] not null default '{}',  -- UNIT_TAGS のID配列
  method_tags int[] not null default '{}',  -- METHOD_TAGS のID配列
  admin_note  text,                         -- 管理者メモ(任意)
  created_at  timestamptz not null default now()
);

create table votes (
  id          bigint generated always as identity primary key,
  problem_id  bigint not null references problems(id) on delete cascade,
  device_uuid text not null,
  difficulty  int not null check (difficulty between 1 and 5),
  created_at  timestamptz not null default now(),
  unique (problem_id, device_uuid)          -- 同一端末の再投票は upsert で上書き
);

create table comments (
  id             bigint generated always as identity primary key,
  problem_id     bigint not null references problems(id) on delete cascade,
  device_uuid    text not null,
  body           text not null check (char_length(body) <= 500),
  is_hidden      boolean not null default false,
  reported_count int not null default 0,
  created_at     timestamptz not null default now()
);

create index idx_problems_university on problems (university);
create index idx_problems_year on problems (year);
create index idx_problems_unit_tags on problems using gin (unit_tags);
create index idx_problems_method_tags on problems using gin (method_tags);
create index idx_votes_problem on votes (problem_id);
create index idx_comments_problem on comments (problem_id);
```

### RLSポリシーSQL

方針: 匿名(anon)は problems の select のみ、votes は select/insert/update、comments は select/insert と reported_count のインクリメント(RPC経由)のみ。

```sql
alter table problems enable row level security;
alter table votes    enable row level security;
alter table comments enable row level security;

-- problems: 読み取りのみ
create policy "problems_anon_select" on problems
  for select to anon using (true);

-- votes: 読み取り + 投票(upsert = insert/update)
create policy "votes_anon_select" on votes
  for select to anon using (true);
create policy "votes_anon_insert" on votes
  for insert to anon with check (true);
create policy "votes_anon_update" on votes
  for update to anon using (true) with check (true);

-- comments: 読み取り + 投稿(隠しフラグ・通報数は初期値のみ許可)
create policy "comments_anon_select" on comments
  for select to anon using (true);
create policy "comments_anon_insert" on comments
  for insert to anon with check (is_hidden = false and reported_count = 0);

-- 通報: reported_count のインクリメントだけを security definer 関数で許可
create or replace function report_comment(target_id bigint)
returns void
language sql
security definer
set search_path = public
as $$
  update comments set reported_count = reported_count + 1 where id = target_id;
$$;

grant execute on function report_comment(bigint) to anon;
```

#### 既知の制約(要検討)

- Supabase Auth を使っていないため、「votes の update は自分の device_uuid 行のみ」をサーバ側で強制できない(device_uuid は自己申告)。実害が出たら Auth(匿名サインイン)へ移行して `auth.uid()` ベースのポリシーに置き換える。
- 管理画面(問題のCRUD、コメントの is_hidden トグル)も anon key で動くため、上記ポリシーのままでは**本番DBに対して書き込みが失敗する**。初期運用でどうしても必要なら下記の暫定ポリシーを追加できるが、**誰でも書き込める状態になる**ことを理解した上で使うこと。恒久対応は Supabase Auth + 管理者ロール、または Edge Function 化。

```sql
-- ★暫定(リスク承知の上で必要な場合のみ実行)
create policy "problems_anon_write_TEMP" on problems
  for all to anon using (true) with check (true);
create policy "comments_anon_hide_TEMP" on comments
  for update to anon using (true) with check (true);
```

## タグ定義

**タグの正本(source of truth)は `index.html` 内のJS定数 `UNIT_TAGS` / `METHOD_TAGS`。** DBにはID(int)のみ保存する。タグの改名はコード修正のみで対応できる。**IDの振り直し・削除は既存データを壊すので禁止**(追加は末尾IDで行う)。

### UNIT_TAGS(id: 1〜25)

1 数と式・論証 / 2 二次関数 / 3 図形と計量 / 4 場合の数 / 5 確率 / 6 確率漸化式 / 7 整数 / 8 図形の性質 / 9 式と証明・高次方程式 / 10 図形と方程式 / 11 三角関数 / 12 指数・対数 / 13 微分法(数II) / 14 積分法(数II) / 15 数列 / 16 統計的な推測 / 17 ベクトル(平面) / 18 ベクトル(空間) / 19 複素数平面 / 20 二次曲線 / 21 極限 / 22 微分法(数III) / 23 積分法(数III)・求積 / 24 曲線の長さ・回転体 / 25 融合・総合

### METHOD_TAGS(id: 1〜36、group属性つき)

- **方針・戦略**: 1 実験して規則性を発見 / 2 小さい場合・端の場合から考える / 3 対称性の利用 / 4 一般化・特殊化 / 5 逆向きに考える
- **論証**: 6 数学的帰納法 / 7 背理法 / 8 対偶の利用 / 9 鳩の巣原理 / 10 必要条件で絞って十分性確認
- **整数**: 11 剰余で分類(mod) / 12 素因数分解・約数 / 13 不等式で範囲を絞る / 14 互除法・不定方程式
- **関数・方程式**: 15 置換 / 16 文字定数の分離 / 17 解の配置 / 18 存在条件への言い換え(逆像法) / 19 1文字固定(予選決勝法) / 20 対称式
- **図形**: 21 座標設定 / 22 ベクトルで処理 / 23 複素数平面で処理 / 24 初等幾何で処理 / 25 三角関数でパラメータ表示 / 26 空間図形を平面で切る
- **解析**: 27 はさみうちの原理 / 28 平均値の定理 / 29 微分して増減を調べる / 30 積分と不等式 / 31 区分求積法 / 32 漸化式を立てる / 33 誘導の構造を見抜く
- **確率・場合の数**: 34 余事象・排反に分ける / 35 対等性・確率の対称性 / 36 場合分けの設計

## 画面仕様(3画面、SPA的にJS切替)

### 1. 一覧+絞り込み(メイン画面)

- フィルタ: 大学(複数選択チップ、データから動的生成)/ 年度範囲(from–to)/ 単元タグ(複数、OR)/ 解法タグ(複数、OR、グループ見出しつき)/ 平均難易度帯
- 結果カード: 大学・年度・大問番号、タグチップ、平均難易度(★表示+投票数)、コメント数
- カードタップで詳細画面へ。該当0件時は空状態表示

### 2. 問題詳細

- 基本情報とタグ一覧
- 難易度投票: ★1〜5タップで投票。`device_uuid`(localStorage、初回 `crypto.randomUUID()` 生成)で upsert。自分の投票済み状態を表示
- コメント: 投稿フォーム(500字制限・トリムのみ、プレビューなし)、一覧は新着順、MathJax対応
- 各コメントに通報ボタン(確認ダイアログ → `report_comment` RPC)。通報済みIDはlocalStorageに記録し連打防止
- `is_hidden = true` のコメントは表示しない(フィルタはクライアント側)

### 3. 管理画面(パスワード保護)

- 入口はフッターの目立たないリンク。パスワードはJS内定数 `ADMIN_PASSWORD`(プレースホルダ)との簡易照合(**セキュリティ機構ではなくUIゲート**。本命はRLS側)
- 問題の新規登録・編集・削除(タグはチェックボックスで選択)
- コメント管理: 全コメント一覧(通報数順/新着順ソート)、`is_hidden` トグル

## コーディング規約

- **単一 `index.html`** にCSS/JSを同梱。ビルドツール・フレームワーク不使用、ライブラリはCDNのみ
- 明るい配色(クリーム系ライトテーマ)・モバイルファースト(基準幅 ~390px、`max-width` でタブレット対応)
- localStorage キーは **`examdb_` プレフィックス**で統一
  - `examdb_device_uuid` — 端末識別UUID
  - `examdb_reported_comments` — 通報済みコメントIDの配列(JSON)
- コメント本文は投稿時に**トリム+500字制限のみ**。表示時は必ずHTMLエスケープ(XSS対策必須)。`$...$` はエスケープ後もMathJaxが処理する
- Supabase未接続でも全画面が動くよう、サンプルデータへのフォールバックを維持すること(接続判定は anon key がプレースホルダかどうか)
- タグ定数の変更ルール: 改名OK・追加は末尾ID・削除/ID変更は禁止

## 今後のロードマップ

1. **フェーズ1(現在)**: メタデータDBとして運用。問題文・解説は載せない
2. 問題文・解説の掲載 — 大学/予備校等との**著作権許諾が取れてから**
3. AdSense等の収益化 — コンテンツ(レコード数・コメント)が十分蓄積してから
4. 管理画面の本格認証(Supabase Auth / Edge Function)への移行
5. 理科(物理・化学)への拡張構想 — テーブル・タグ体系を科目ごとに分離して横展開
