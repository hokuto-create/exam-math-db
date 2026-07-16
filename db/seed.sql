-- =====================================================================
-- 過去問データ シードSQL
-- =====================================================================
-- 使い方:
--   1. Supabase ダッシュボード → SQL Editor にこのファイルの内容を貼り付けて実行
--   2. このファイルが問題データの正本。データ追加はここに追記して再実行する
--      (自然キーの unique 制約 + on conflict により、再実行しても重複しない)
--
-- 注意:
--   - タグIDの正本は index.html の UNIT_TAGS / METHOD_TAGS(下に早見表あり)
--   - exam_type が無い場合は空文字 '' を入れる(NULLにしない)
--
-- ---------------------------------------------------------------------
-- 単元タグ早見表(UNIT_TAGS)
--  1 数と式・論証      2 二次関数          3 図形と計量        4 場合の数
--  5 確率              6 確率漸化式        7 整数              8 図形の性質
--  9 式と証明・高次方程式  10 図形と方程式  11 三角関数         12 指数・対数
-- 13 微分法(数II)      14 積分法(数II)     15 数列             16 統計的な推測
-- 17 ベクトル(平面)    18 ベクトル(空間)   19 複素数平面       20 二次曲線
-- 21 極限              22 微分法(数III)    23 積分法(数III)・求積
-- 24 曲線の長さ・回転体  25 融合・総合
--
-- 解法タグ早見表(METHOD_TAGS)
-- [方針・戦略]     1 実験して規則性を発見  2 小さい場合・端の場合から考える
--                  3 対称性の利用          4 一般化・特殊化    5 逆向きに考える
-- [論証]           6 数学的帰納法          7 背理法            8 対偶の利用
--                  9 鳩の巣原理           10 必要条件で絞って十分性確認
-- [整数]          11 剰余で分類(mod)      12 素因数分解・約数
--                 13 不等式で範囲を絞る   14 互除法・不定方程式
-- [関数・方程式]  15 置換                 16 文字定数の分離   17 解の配置
--                 18 存在条件への言い換え(逆像法)  19 1文字固定(予選決勝法)
--                 20 対称式
-- [図形]          21 座標設定             22 ベクトルで処理   23 複素数平面で処理
--                 24 初等幾何で処理       25 三角関数でパラメータ表示
--                 26 空間図形を平面で切る
-- [解析]          27 はさみうちの原理     28 平均値の定理     29 微分して増減を調べる
--                 30 積分と不等式         31 区分求積法       32 漸化式を立てる
--                 33 誘導の構造を見抜く
-- [確率・場合の数] 34 余事象・排反に分ける  35 対等性・確率の対称性
--                 36 場合分けの設計
-- ---------------------------------------------------------------------

-- 問題文カラムを追加(既にあればスキップ)
-- ※問題文の著作権は大学等にあります。掲載許諾の状況を確認の上で入力してください
alter table problems add column if not exists problem_text text;

-- 公式問題PDFのURLカラムを追加(既にあればスキップ)
-- ※運用ルール: source_url を登録したら https://web.archive.org/save/<そのURL> を
--   一度開いて Wayback Machine に魚拓を残すこと(公式サイトからの削除に備える。
--   詳細画面の「アーカイブで開く」リンクはこの魚拓を参照する)
alter table problems add column if not exists source_url text;

-- 配点カラムを追加(既にあればスキップ)
-- ※試験冊子に配点が明記されている大学(京大など)のみ入れる。
--   問題文シートの大問見出し行の右端に「(◯点)」と表示される
alter table problems add column if not exists points int;

-- 自然キー(大学×年度×区分×大問)にユニーク制約を追加(既にあればスキップ)
do $$
begin
  alter table problems
    add constraint problems_natural_key unique (university, year, exam_type, question_no);
exception
  when duplicate_table then null;
  when duplicate_object then null;
end $$;

-- =====================================================================
-- 解答・解説テーブル(既にあればスキップ)
-- 運営者オリジナルの構造化解答。1問につき1件(problem_id で upsert)。
-- 11項目構成のうち「難易度」= difficulty(投票平均とは別の運営評価)、
-- 「目標解答時間」= target_time_min、「類題」はサイトの自動類題セクションが担う。
-- 定義の正本は CLAUDE.md の「データ設計」
-- =====================================================================
create table if not exists solutions (
  id              bigint generated always as identity primary key,
  problem_id      bigint not null unique references problems(id) on delete cascade,
  difficulty      int check (difficulty between 1 and 5), -- 運営評価の難易度
  target_time_min int,   -- 目標解答時間(分)
  prerequisites   text,  -- 必要な知識
  approach        text,  -- 方針
  answer          text,  -- 答え(答えのみ。証明問題はその旨)
  full_solution   text,  -- 完全解答
  insight         text,  -- 発想の理由(なぜこの置換・補助線か/どの条件で解法を決めるか)
  alternatives    text,  -- 別解
  common_mistakes text,  -- よくある誤答
  grading_notes   text,  -- 採点上必要な記述
  takeaways       text,  -- この問題から学ぶこと
  created_at      timestamptz not null default now()
);

alter table solutions enable row level security;
do $$
begin
  create policy "solutions_anon_select" on solutions
    for select to anon using (true);
exception
  when duplicate_object then null;
end $$;
-- ※管理画面(anon key)から解答を書き込む場合のみ、下記の暫定ポリシーを追加する
--   (誰でも書き込める状態になる点は problems と同じリスク。恒久対応は Auth 移行):
-- create policy "solutions_anon_write_TEMP" on solutions
--   for all to anon using (true) with check (true);

-- =====================================================================
-- 問題データ
-- 形式: (大学, 年度, 試験区分, 大問番号, 単元タグID配列, 解法タグID配列, 管理メモ)
-- =====================================================================
-- 問題文の転記ルール(東京大学):
--   「東京大学第2次学力試験入学試験問題等の2次利用について」(令和6年7月1日改定)に従い,
--   事前承認なしで転載可。ただし (1) 公表から1か月以内に本部入試課のフォームで利用報告
--   (2) 出典明示+改変明示(problem_text 末尾の出典行) を必ず守ること。
insert into problems
  (university, year, exam_type, question_no, unit_tags, method_tags, source_url, problem_text, admin_note)
values
  -- ---- 東京大学 2026 前期理系(数学・理科)----
  ('東京大学', 2026, '前期理系', 1, '{22,23}', '{29,30,33}', 'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'(1) 関数 $f(\theta)=\sin\theta-\theta+\dfrac{\theta^3}{6}$ の区間 $-1\leqq\theta\leqq1$ における最大値 $M$ および最小値 $m$ を求めよ。

(2) (1)で定めた $M$ に対し,次の不等式を示せ。
$$\frac{7}{8}\pi\leqq\int_0^{2\pi}\sin{(\cos x-x)}\,dx\leqq\frac{7}{8}\pi+4M$$

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第1問(原本より数式の組版を変更して転載)',
   'sinθ-θ+θ^3/6 の最大最小から ∫sin(cosx-x)dx を評価'),
  ('東京大学', 2026, '前期理系', 2, '{5,4}',   '{34,36}',    'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'$n$ を正の整数とする。座標平面上の $3n$ 個の点がなす集合
$$\{(x,\ y)\mid x,\ y\ \text{は}\ 1\leqq x\leqq3,\ 1\leqq y\leqq n\ \text{を満たす整数}\}$$
から相異なる $3$ 点を選ぶ。ただし,どの $3$ 点も等確率で選ばれるものとする。選んだ $3$ 点が三角形の $3$ 頂点となる確率を $p_n$ とする。

(1) $p_5$ を求めよ。

(2) $m$ を $2$ 以上の整数とする。$p_{2m}$ を求めよ。

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第2問(原本より数式の組版を変更して転載)',
   '3×n の格子点から選んだ3点が三角形をなす確率 p_n'),
  ('東京大学', 2026, '前期理系', 3, '{18,10}', '{22,18}',    'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'座標空間内の原点を中心とする半径 $5$ の球面を $S$ とする。$S$ 上の相異なる $3$ 点 $\mathrm{P},\ \mathrm{Q},\ \mathrm{R}$ が次の条件を満たすように動く。

条件: $\mathrm{P},\ \mathrm{Q}$ は $xy$ 平面上にあり,三角形 $\mathrm{PQR}$ の重心は $\mathrm{G}\,(2,\ 0,\ 1)$ である。

以下の問いに答えよ。

(1) 線分 $\mathrm{PQ}$ の中点 $\mathrm{M}$ の軌跡を $xy$ 平面上に図示せよ。

(2) 線分 $\mathrm{PQ}$ が通過する範囲を $xy$ 平面上に図示せよ。

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第3問(原本より数式の組版を変更して転載)',
   '球面上の3点と重心固定条件。PQ中点の軌跡と線分PQの通過範囲の図示'),
  ('東京大学', 2026, '前期理系', 4, '{13,10}', '{18,29}',    'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'$k$ を実数とし,座標平面上の曲線 $C$ を $y=x^3-kx$ で定める。$C$ 上の $2$ 点 $\mathrm{P},\ \mathrm{Q}$ に対する以下の条件 $(*)$ を考える。

条件 $(*)$: 原点 $\mathrm{O}$,点 $\mathrm{P}$,点 $\mathrm{Q}$ は相異なり,$C$ の $\mathrm{O},\ \mathrm{P},\ \mathrm{Q}$ における接線のうち,どの $2$ 本も交わり,そのなす角はすべて $\dfrac{\pi}{3}$ となる。

ただし,$2$ 直線のなす角は $0$ 以上 $\dfrac{\pi}{2}$ 以下の範囲で考えるものとする。

(1) 条件 $(*)$ を満たす $\mathrm{P},\ \mathrm{Q}$ が存在するような $k$ の範囲を求めよ。

(2) $k$ が(1)で定まる範囲にあるとする。$\mathrm{P},\ \mathrm{Q}$ が条件 $(*)$ を満たすように動くとき,$C$ の $\mathrm{O},\ \mathrm{P},\ \mathrm{Q}$ における接線によって囲まれる三角形の面積 $S$ の最大値を $M$,最小値を $m$ とおく。ただし,$3$ 本の接線が $1$ 点で交わるときは $S=0$ とする。$M=4m$ となる $k$ の値を求めよ。

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第4問(原本より数式の組版を変更して転載)',
   'y=x^3-kx の3接線(O,P,Q)がどの2本もなす角 π/3。kの範囲と三角形の面積'),
  ('東京大学', 2026, '前期理系', 5, '{19}',    '{23,18}',    'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'複素数平面上の原点を中心とする半径 $1$ の円を $C$ とする。複素数 $\alpha$ と $C$ 上の点 $\mathrm{P}(z)$ に対し,$w=(z-\alpha)^3$ とおく。$\mathrm{P}$ が $C$ 上を動くときの点 $\mathrm{Q}(w)$ の軌跡を $D$ とする。

(1) $\alpha=-3$ とし,$w$ の偏角を $\theta$ とおく。$\mathrm{P}$ が $C$ 上を動くとき,$\sin\theta$ がとりうる値の範囲を求めよ。

(2) $\alpha$ が次の条件を満たすように動く。

条件: $D$ は実軸の正の部分および負の部分の両方と共有点を持つ。

複素数平面上の点 $\mathrm{R}(\alpha)$ が動きうる範囲の面積を求めよ。

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第5問(原本より数式の組版を変更して転載)',
   'w=(z-α)^3 による単位円の像。偏角の範囲と条件を満たす α の範囲の面積'),
  ('東京大学', 2026, '前期理系', 6, '{7}',     '{11,12}',    'https://www.u-tokyo.ac.jp/content/400239118.pdf',
'$n$ を正の整数とする。$n$ の正の約数のうち,$3$ で割って $1$ 余るものの個数を $f(n)$,$3$ で割って $2$ 余るものの個数を $g(n)$ とする。

(1) $f(2800),\ g(2800)$ を求めよ。

(2) $f(n)\geqq g(n)$ を示せ。

(3) $g(n)=15$ であるとき,$f(n)$ がとりうる値を求めよ。

出典:東京大学 2026年度 第2次学力試験問題 数学(理科)第6問(原本より数式の組版を変更して転載)',
   '約数を mod 3 で分類した個数 f(n), g(n)。f(n)≧g(n) の証明など')
on conflict (university, year, exam_type, question_no)
do update set
  unit_tags    = excluded.unit_tags,
  method_tags  = excluded.method_tags,
  source_url   = excluded.source_url,
  problem_text = excluded.problem_text,
  admin_note   = excluded.admin_note;

-- 問題文の転記ルール(京都大学):
--   「試験問題等の利用について」(https://www.kyoto-u.ac.jp/ja/admissions/undergrad/past-eq/copyright-policy)
--   に従い,条項遵守を条件に複製・自動公衆送信が事前承認なしで許可されている。ただし
--   (1) Web掲載分は送信内容のプリントアウトを添えて「京都大学入試問題等利用報告書」を提出
--   (2) 出典明示+改変明示(problem_text 末尾の出典行) を必ず守ること。
insert into problems
  (university, year, exam_type, question_no, points, unit_tags, method_tags, source_url, problem_text, admin_note)
values
  -- ---- 京都大学 2026 前期理系(数学・理系)----
  ('京都大学', 2026, '前期理系', 1, 30, '{21,22}', '{16,29}',   'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　$a$ は $1$ より大きい実数とし,$k$ は実数とする.$0<x<1$ において定義された関数を
$$f(x)=\frac{1}{x^2\left(\log\dfrac{a}{x}\right)^2}$$
とおく.$y=f(x)$ と $y=k$ のグラフの共有点がちょうど $2$ 個存在するような実数の組 $(a,\ k)$ の集合を,座標平面上に図示せよ.ただし $\log x$ は自然対数とする.また,$\displaystyle\lim_{x\to+0}x\log x=0$ が成り立つことを証明なしに用いてよい.

出典:京都大学 2026年度 入学試験問題 数学(理系)第1問(原本より数式の組版を変更して転載)',
   'f(x)=1/(x²(log(a/x))²) と y=k の共有点がちょうど2個となる (a,k) の集合の図示'),
  ('京都大学', 2026, '前期理系', 2, 30, '{18}',    '{22,26}',   'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　$r$ は正の実数とする.$1$ 辺の長さが $1$ の正四面体 $\mathrm{OABC}$ において,辺 $\mathrm{OA}$ 上に点 $\mathrm{P}$ をとる.点 $\mathrm{P}$ が辺 $\mathrm{OA}$ 上のどこにあっても,点 $\mathrm{P}$ を中心とする半径 $r$ の球面が,辺 $\mathrm{BC}$ と共有点をもたないような $r$ の範囲を求めよ.ただし,点 $\mathrm{O},\ \mathrm{A}$ は辺 $\mathrm{OA}$ に含まれ,点 $\mathrm{B},\ \mathrm{C}$ は辺 $\mathrm{BC}$ に含まれるとする.

出典:京都大学 2026年度 入学試験問題 数学(理系)第2問(原本より数式の組版を変更して転載)',
   '正四面体OABCの辺OA上の任意の点Pを中心とする半径rの球面が辺BCと交わらないrの範囲'),
  ('京都大学', 2026, '前期理系', 3, 35, '{7}',     '{6,11}',    'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　$n$ は正の整数とする.整数係数の多項式
$$(x+1)^{2^{n+1}}-(x^2+1)^{2^n}$$
のすべての係数が $2^m$ で割り切れるような正の整数 $m$ のうち,最大のものは $n+1$ であることを示せ.

〔補足説明〕ただし,
$(x+1)^{2^{n+1}}$ は $x+1$ の $2^{n+1}$ 乗を表す.
$(x^2+1)^{2^n}$ は $x^2+1$ の $2^n$ 乗を表す.
$2^m$ は $2$ の $m$ 乗を表す.

出典:京都大学 2026年度 入学試験問題 数学(理系)第3問および補足説明紙(原本より数式の組版を変更して転載)',
   '(x+1)^{2^{n+1}}−(x²+1)^{2^n} の全係数を割り切る 2^m の最大の m が n+1 であることの証明'),
  ('京都大学', 2026, '前期理系', 4, 35, '{3,11}',  '{3,25,29}', 'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　平面において,次の条件 $(*)$ を満たす正三角形の $1$ 辺の長さの最小値を求めよ.
$(*)$ $1$ 辺の長さが $1$ の正方形であって,$4$ つの頂点がすべてその正三角形の内部または辺上にあるようなものが存在する.

出典:京都大学 2026年度 入学試験問題 数学(理系)第4問(原本より数式の組版を変更して転載)',
   '1辺1の正方形を内部または辺上に含む正三角形の1辺の長さの最小値'),
  ('京都大学', 2026, '前期理系', 5, 35, '{23,24}', '{3}',       'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　$a$ は $0<a<\pi$ を満たす実数とする.$2$ つの関数 $y=\sin(x+a)$ と $y=\sin(x-a)$ のグラフの,$-\dfrac{\pi}{2}\leqq x\leqq\dfrac{\pi}{2}$ の部分が囲む領域を $D_a$ とする.$x$ 軸のまわりに $D_a$ を $1$ 回転してできる立体の体積を求めよ.

出典:京都大学 2026年度 入学試験問題 数学(理系)第5問(原本より数式の組版を変更して転載)',
   'y=sin(x+a) と y=sin(x−a) が囲む領域 D_a の x軸回転体の体積'),
  ('京都大学', 2026, '前期理系', 6, 35, '{5,4}',   '{35}',      'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'　$n$ は $3$ 以上の整数とする.$1$ から $n$ までの番号が書かれた $n$ 枚の札が袋に入っている.ただし,同じ番号が書かれた札はないとする.この袋から $3$ 枚の札を同時に取り出し,一番大きな番号を $X$ とする.$X$ の期待値を求めよ.

出典:京都大学 2026年度 入学試験問題 数学(理系)第6問(原本より数式の組版を変更して転載)',
   'n枚から3枚同時に取り出したときの最大番号 X の期待値')
on conflict (university, year, exam_type, question_no)
do update set
  points       = excluded.points,
  unit_tags    = excluded.unit_tags,
  method_tags  = excluded.method_tags,
  source_url   = excluded.source_url,
  problem_text = excluded.problem_text,
  admin_note   = excluded.admin_note;

-- =====================================================================
-- 解答データ(運営者オリジナル。index.html の SAMPLE_DATA.solutions と同期)
-- 全12問: 東大2026 第1〜6問 / 京大2026 第1〜6問
-- 文中に ' を含むため文字列は $txt$ ... $txt$ のドル引用で囲む
-- =====================================================================

-- ---- 東京大学 2026 前期理系 第1問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 3, 30,
$txt$三角関数の加法定理/置換積分/$\cos^2x,\ \cos^4x$ の定積分(半角公式)/導関数の符号と増減/関数の偶奇性$txt$,
$txt$(1) $f'(\theta)=\cos\theta-1+\dfrac{\theta^2}{2}$ の符号は,もう一度微分した $(f')'(\theta)=\theta-\sin\theta$ で調べる。$f$ は単調増加とわかるので,区間の両端の値がそのまま $M,\ m$ になる。

(2) 次の3段階で評価する。

① 加法定理で $\sin(\cos x-x)$ を展開する。$\cos(\cos x)\sin x$ の項は置換 $t=\cos x$ で消え,$\sin(\cos x)\cos x$ だけが残る。

② $\theta=\cos x$ は $[-1,\ 1]$ に収まるので,$\sin\theta=\theta-\dfrac{\theta^3}{6}+f(\theta)$ を代入する。主要部の積分が $\dfrac{7}{8}\pi$ になる。

③ 誤差項 $f(\cos x)\cos x$ を「非負かつ $M|\cos x|$ 以下」と評価する($\int_0^{2\pi}|\cos x|\,dx=4$ より $4M$ 以下)。$txt$,
$txt$(1) $M=\sin1-\dfrac{5}{6}$,$m=-\sin1+\dfrac{5}{6}\ (=-M)$
(2) 証明問題(方針・完全解答を参照)$txt$,
$txt$(1) $f'(\theta)=\cos\theta-1+\dfrac{\theta^2}{2}$ とおく。さらに
$$f''(\theta)=-\sin\theta+\theta$$
$\theta\geqq0$ では $(\theta-\sin\theta)'=1-\cos\theta\geqq0$ かつ $\theta=0$ で値 $0$ だから $f''(\theta)\geqq0$。$f''$ は奇関数だから $\theta\leqq0$ では $f''(\theta)\leqq0$。よって $f'$ は $\theta=0$ で最小となり,$f'(0)=0$ だから $-1\leqq\theta\leqq1$ で
$$f'(\theta)\geqq0(等号は\ \theta=0\ のみ)$$
ゆえに $f$ はこの区間で単調増加であり,
$$M=f(1)=\sin1-\frac{5}{6},\qquad m=f(-1)=-\sin1+\frac{5}{6}=-M$$

(2) 求める積分を $I$ とする。加法定理より
$$\sin(\cos x-x)=\sin(\cos x)\cos x-\cos(\cos x)\sin x$$
第2項は $t=\cos x$($dt=-\sin x\,dx$)の置換により
$$\int_0^{2\pi}\cos(\cos x)\sin x\,dx=\int_1^1\cos t\,dt=0$$
よって
$$I=\int_0^{2\pi}\sin(\cos x)\cos x\,dx$$
(1)の $f$ を用いると $\sin\theta=\theta-\dfrac{\theta^3}{6}+f(\theta)$ であり,$\cos x\in[-1,\ 1]$ だから $\theta=\cos x$ を代入して
$$\sin(\cos x)\cos x=\cos^2x-\frac{\cos^4x}{6}+f(\cos x)\cos x$$
$\displaystyle\int_0^{2\pi}\cos^2x\,dx=\pi$,$\displaystyle\int_0^{2\pi}\cos^4x\,dx=\frac{3}{4}\pi$ より
$$\int_0^{2\pi}\left(\cos^2x-\frac{\cos^4x}{6}\right)dx=\pi-\frac{1}{6}\cdot\frac{3}{4}\pi=\frac{7}{8}\pi$$
残る誤差項を評価する。$f$ は奇関数で,(1)より $-1\leqq\theta\leqq1$ で単調増加かつ $f(0)=0$ だから,この区間で $f(\theta)$ と $\theta$ は常に同符号。よって
$$f(\cos x)\cos x\geqq0$$
また $-1\leqq\theta\leqq1$ で $-M=m\leqq f(\theta)\leqq M$ だから $|f(\cos x)|\leqq M$ であり,$f(\cos x)\cos x\leqq M|\cos x|$。$\displaystyle\int_0^{2\pi}|\cos x|\,dx=4$ より
$$0\leqq\int_0^{2\pi}f(\cos x)\cos x\,dx\leqq4M$$
以上より
$$\frac{7}{8}\pi\leqq I\leqq\frac{7}{8}\pi+4M$$
が示された。■$txt$,
$txt$中身の $\cos x-x$ は $[-1,\ 1]$ に収まらないので,(1)の $f$ を $\sin(\cos x-x)$ に直接使うことはできない。ここで手が止まったら「加法定理でほどく」を試す。展開して出る $\cos(\cos x)\sin x$ は $g(\cos x)\sin x$ 型で,置換 $t=\cos x$ により消えるので,実質の被積分関数は $\sin(\cos x)\cos x$ だけになる。

(1)の $f(\theta)=\sin\theta-\theta+\dfrac{\theta^3}{6}$ は $\sin\theta$ の3次近似の誤差そのもの。「(1)で最大値・最小値 → (2)で不等式評価」という誘導は,「近似の主要部が $\dfrac{7}{8}\pi$,誤差が $4M$ 以内」という構図を示唆している。さらに目標の下限が $\dfrac{7}{8}\pi$ ちょうど($-4M$ が現れない)ことから,誤差項が非負,すなわち $f(\cos x)\cos x\geqq0$(同符号)に気づきたい。$txt$,
$txt$・(1)は $\cos\theta\geqq1-\dfrac{\theta^2}{2}$($\theta\ne0$ で等号なし)を先に示し,そこから $f'>0$ を導いてもよい(同値な議論)。
・(2)の $\displaystyle\int_0^{2\pi}\cos(\cos x)\sin x\,dx=0$ は,置換 $x\mapsto2\pi-x$ で被積分関数が符号反転することからも示せる。
・「(周期関数)$\times\sin x$ で中身が $\cos x$ の合成」は原始関数が書ける,と覚えておくと展開の方針が早く立つ。$txt$,
$txt$・$\sin(\cos x-x)$ に直接 $\theta-\dfrac{\theta^3}{6}$ の近似を適用する($\cos x-x$ は $[-1,\ 1]$ を大きくはみ出すので(1)は使えない)。
・下限側で $f(\cos x)\cos x\geqq0$ の根拠(奇関数+単調増加+$f(0)=0$)を述べず,$\dfrac{7}{8}\pi-4M$ 止まりの評価しか得られない。
・$\displaystyle\int_0^{2\pi}|\cos x|\,dx=4$ を $0$ や $2$ と誤る($\cos x$ 自体の積分と混同)。
・$\cos^4x$ の定積分 $\dfrac{3}{4}\pi$ の計算ミス(半角公式を2回使う)。$txt$,
$txt$・(1) $f'$ の符号を論じる際,$f''(\theta)=\theta-\sin\theta$ の符号の根拠($\theta\geqq0$ で $\theta\geqq\sin\theta$)と,奇関数性による $\theta<0$ 側の処理を明記する。
・(2) $\displaystyle\int_0^{2\pi}\cos(\cos x)\sin x\,dx=0$ は置換の式変形つきで示す(「明らか」で流さない)。
・$m=-M$($f$ が奇関数)を使う箇所は根拠を一言添える。
・$f(\cos x)\cos x\geqq0$ の同符号の議論は下限 $\dfrac{7}{8}\pi$ の成否を分ける本質部分なので必ず記述する。$txt$,
$txt$・(1)で与えられた関数は $\sin\theta$ の3次テイラー近似の誤差。「誘導で与えられた関数の正体」を見抜くと(2)での使い所が定まる。
・周期関数の定積分では,置換($t=\cos x$,$x\mapsto2\pi-x$ など)で消える項を先に探す。
・不等式の証明は「主要部の計算+誤差項の符号と大きさの評価」に分解する。目標の式の形(下限に誤差が現れない等)から,必要な評価の強さを逆算できる。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 1
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 東京大学 2026 前期理系 第2問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 2, 25,
$txt$組合せの計算/余事象/3点が同一直線上にある条件(等差中項)/偶奇による場合分け$txt$,
$txt$余事象「3点が同一直線上」を数える。この格子は $x$ 座標が $1,2,3$ の3種類しかないので,同一直線上の3点は次の2型に完全に分類できる。

① 縦線型(3点が同じ列): $3\times{}_n\mathrm{C}_3$ 組。

② 各列1点型: $(1,y_1),(2,y_2),(3,y_3)$ が同一直線上 ⟺ $y_1+y_3=2y_2$(等差)⟺ $y_1$ と $y_3$ が同じ偶奇。$y_2$ は自動的に決まるので,同偶奇の組 $(y_1,y_3)$ の個数を数える(横一列 $y_1=y_3$ もここに含まれる)。

(2)は $n=2m$ で奇数・偶数がちょうど $m$ 個ずつになり,②が $2m^2$ と一斉に数えられる。$txt$,
$txt$(1) $p_5=\dfrac{412}{455}$
(2) $p_{2m}=\dfrac{m(16m-7)}{(6m-1)(3m-1)}$$txt$,
$txt$$3n$ 個の点から3点を選ぶ方法は ${}_{3n}\mathrm{C}_3$ 通りで,どれも等確率。三角形にならないのは3点が同一直線上のときである。

同じ列($x$ 座標が等しい)の2点を通る直線は縦線だから,同一直線上の3点は
(i) 3点が同じ列にある
(ii) 3点の $x$ 座標が $1,2,3$ で1つずつ
のどちらか一方に限られる($x$ 座標がちょうど2種類の3点は同一直線上に並ばない)。

(i) 各列 $n$ 点から3点: $3\times{}_n\mathrm{C}_3$ 組。

(ii) $(1,y_1),(2,y_2),(3,y_3)$ が同一直線上 ⟺ $y_2-y_1=y_3-y_2$ ⟺ $y_1+y_3=2y_2$。
$y_1,y_3$($1\leqq y_1,y_3\leqq n$)を同じ偶奇に選べば $y_2=\dfrac{y_1+y_3}{2}$ は $1\leqq y_2\leqq n$ を満たす整数として一意に定まる。$y_1\ne y_3$ のとき $(y_1,y_3)$ と $(y_3,y_1)$ は異なる3点を与えるから,この型の組数は同偶奇の順序対 $(y_1,y_3)$ の個数に等しい(横一列 $y_1=y_2=y_3$ の場合も含む)。

(1) $n=5$: 全体 ${}_{15}\mathrm{C}_3=455$。
(i) $3\times{}_5\mathrm{C}_3=30$。(ii) 奇数3個・偶数2個より $3^2+2^2=13$。
同一直線上は $30+13=43$ 組だから
$$p_5=1-\frac{43}{455}=\frac{412}{455}$$

(2) $n=2m$: 全体 ${}_{6m}\mathrm{C}_3=\dfrac{6m(6m-1)(6m-2)}{6}=2m(6m-1)(3m-1)$。
(i) $3\times{}_{2m}\mathrm{C}_3=m(2m-1)(2m-2)=2m(2m-1)(m-1)$。
(ii) 奇数 $m$ 個・偶数 $m$ 個より $m^2+m^2=2m^2$。
同一直線上の総数は
$$2m(2m-1)(m-1)+2m^2=2m(2m^2-2m+1)$$
よって
$$p_{2m}=1-\frac{2m^2-2m+1}{(6m-1)(3m-1)}=\frac{18m^2-9m+1-(2m^2-2m+1)}{(6m-1)(3m-1)}=\frac{m(16m-7)}{(6m-1)(3m-1)}$$$txt$,
$txt$「三角形になる」より「同一直線上に並ぶ」の方が圧倒的に数えやすい — まず余事象と決める。

次に効くのが「$x$ 座標が3種類しかない」という格子の特殊性。同一直線は縦線か「各列1点ずつ」しかない,と直線の型を先に分類してしまえば,残る条件は等差中項 $y_1+y_3=2y_2$ だけになる。「中点(中項)が格子に乗る ⟺ 両端が同偶奇」は格子点問題の頻出の言い換え。

(1)の $p_5$ は(2)の一般化の予行演習。$n$ が奇数だと奇数・偶数の個数が非対称($3^2+2^2$)になるのに対し,$n=2m$ では $m^2+m^2$ と揃う — 出題が $p_{2m}$ に限定されているのはこのためで,誘導の意図がここから読める。$txt$,
$txt$・(ii)は「$y_3-y_1$ が偶数」と読み替え,差 $2d$($d=0,\pm1,\dots$)ごとに組数を数えて和をとってもよい(結果は同じ)。
・$p_{2m}$ は $m=2$($n=4$)で検算できる: 全体 ${}_{12}\mathrm{C}_3=220$,同一直線 $12+8=20$,$p_4=\dfrac{200}{220}=\dfrac{10}{11}$。公式 $\dfrac{2(32-7)}{11\cdot5}=\dfrac{50}{55}=\dfrac{10}{11}$ ✓$txt$,
$txt$・横一列($y_1=y_2=y_3$)の数え落とし,または(ii)と別に数えて重複させる(本解は(ii)に含めて処理)。
・$(y_1,y_3)$ を組(無順序)で数えてしまう: $y_1\ne y_3$ なら $(y_1,y_3)$ と $(y_3,y_1)$ は異なる3点。
・$n=5$ の奇数・偶数の個数(3個と2個)の取り違え。
・「$x$ 座標が2種類の3点は同一直線上にない」ことの確認を飛ばし,分類の完全性が崩れる。$txt$,
$txt$・「どの3点も等確率」を根拠に確率=組数比とすること,分母 ${}_{3n}\mathrm{C}_3$ の明示。
・同一直線の型分類(縦線型/各列1点型)と,それで尽くされる理由の一言。
・$y_1+y_3=2y_2$ から $y_2$ が自動的に $1\leqq y_2\leqq n$ の整数になることの明示。
・(2)の因数分解した最終形(約分の過程)。$txt$,
$txt$・「〜にならない確率」は余事象から。幾何条件(同一直線)は座標の代数条件(等差・偶奇)に翻訳する。
・格子点の共線・中点条件は偶奇で数える — 「中点が格子点 ⟺ 両端が同偶奇」。
・小さい場合((1)や $n=4$)で一般式を検算する習慣が事故を防ぐ。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 2
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 東京大学 2026 前期理系 第3問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 4, 40,
$txt$球面と平面の交わり/重心の位置ベクトル/軌跡(逆の確認を含む)/弦と中心の垂直関係/存在条件への言い換え(三角関数の合成)$txt$,
$txt$① $\mathrm{P},\mathrm{Q}$ は球面と $xy$ 平面の交わりの円 $x^2+y^2=25$ 上。重心の条件から $\mathrm{R}=(6,0,3)-2\mathrm{M}$($\mathrm{M}$ は $\mathrm{PQ}$ の中点)と,$\mathrm{R}$ を $\mathrm{M}$ で表して消去する。

② $\mathrm{R}$ が球面上 ⟺ $|\mathrm{OR}|^2=25$ を $\mathrm{M}=(x,y)$ で書くと円 $(x-3)^2+y^2=4$。$\mathrm{M}=(5,0)$ では $\mathrm{P}=\mathrm{Q}$ になるので除く(逆の確認も行う)。

③ (2) 弦 $\mathrm{PQ}$ は「$\mathrm{M}$ を通り $\mathrm{OM}$ に垂直」。点 $(X,Y)$ を固定し,その点を通る弦を与える $\mathrm{M}$(パラメータ $\varphi$)が存在する条件に言い換える(逆像法)。$\varphi$ の方程式を三角関数の合成で処理すると双曲線の不等式が出る。$txt$,
$txt$(1) $xy$ 平面上の円 $(x-3)^2+y^2=4$。ただし点 $(5,\ 0)$ を除く。
(2) $\dfrac{(x-3)^2}{4}-\dfrac{y^2}{5}\leqq1$ かつ $x^2+y^2\leqq25$ の表す部分($xy$ 平面上)。ただし点 $(5,\ 0)$ を除く(境界はそれ以外含む)。$txt$,
$txt$$\mathrm{P},\mathrm{Q}$ は球面 $S$ と $xy$ 平面の交わり,すなわち円 $x^2+y^2=25,\ z=0$ 上にある。

(1) 重心の条件 $\dfrac{1}{3}(\mathrm{P}+\mathrm{Q}+\mathrm{R})=(2,0,1)$ より $\mathrm{R}=(6,0,3)-(\mathrm{P}+\mathrm{Q})$。$\mathrm{PQ}$ の中点を $\mathrm{M}(x,y,0)$ とすると $\mathrm{P}+\mathrm{Q}=2\mathrm{M}$ だから
$$\mathrm{R}=(6-2x,\ -2y,\ 3)$$
$\mathrm{R}$ が $S$ 上にある条件は
$$(6-2x)^2+4y^2+9=25\ \Longleftrightarrow\ (x-3)^2+y^2=4$$
逆に,この円上の点 $\mathrm{M}\ne(5,0)$ は $x^2+y^2<25$(円 $(x-3)^2+y^2=4$ 上で $x^2+y^2=25$ となるのは $(5,0)$ のみ)を満たすので,$\mathrm{M}$ を中点とする弦 $\mathrm{PQ}$($\mathrm{OM}\perp\mathrm{PQ}$,$\mathrm{P}\ne\mathrm{Q}$)が取れ,上式の $\mathrm{R}$ は $S$ 上にある。また $\mathrm{R}$ の $z$ 座標は $3\ne0$ なので $\mathrm{R}$ は $\mathrm{P},\mathrm{Q}$ と常に異なる。$\mathrm{M}=(5,0)$ では $\mathrm{P}=\mathrm{Q}=(5,0)$ となり不適。
よって求める軌跡は 円 $(x-3)^2+y^2=4$ から点 $(5,0)$ を除いたもの。

(2) $\mathrm{M}=(3+2\cos\varphi,\ 2\sin\varphi)$($\varphi\ne0$,すなわち $\mathrm{M}\ne(5,0)$)とおく。弦 $\mathrm{PQ}$ は「$\mathrm{M}$ を通り $\overrightarrow{\mathrm{OM}}$ に垂直な直線」の円 $x^2+y^2\leqq25$ 内の部分だから,点 $(X,Y)$ が線分 $\mathrm{PQ}$ 上にある条件は
$$X^2+Y^2\leqq25\ かつ\ X(3+2\cos\varphi)+2Y\sin\varphi=(3+2\cos\varphi)^2+(2\sin\varphi)^2$$
右の等式を整理すると
$$2(X-6)\cos\varphi+2Y\sin\varphi=13-3X\quad\cdots(\ast)$$
$(\ast)$ を満たす $\varphi$ が存在する条件は,左辺の合成(振幅 $2\sqrt{(X-6)^2+Y^2}$)より
$$|13-3X|\leqq2\sqrt{(X-6)^2+Y^2}$$
両辺は0以上だから2乗して同値変形でき
$$(13-3X)^2\leqq4\{(X-6)^2+Y^2\}\ \Longleftrightarrow\ 5X^2-30X+25-4Y^2\leqq0\ \Longleftrightarrow\ \frac{(X-3)^2}{4}-\frac{Y^2}{5}\leqq1$$
除外した $\varphi=0$ が $(\ast)$ の解になるのは $2(X-6)=13-3X$,すなわち $X=5$ のときだけで,$X^2+Y^2\leqq25$ より $(X,Y)=(5,0)$。この点では $\varphi=0$ が唯一の解だから $(5,0)$ のみ通過範囲から除かれ,他の点は影響を受けない。
よって求める範囲は
$$\frac{(x-3)^2}{4}-\frac{y^2}{5}\leqq1\ かつ\ x^2+y^2\leqq25(点\ (5,0)\ を除く)$$
双曲線 $\dfrac{(x-3)^2}{4}-\dfrac{y^2}{5}=1$ は頂点 $(1,0),(5,0)$,漸近線 $y=\pm\dfrac{\sqrt5}{2}(x-3)$ で,円 $x^2+y^2=25$ とは $\left(-\dfrac{5}{3},\ \pm\dfrac{10\sqrt2}{3}\right)$(および点 $(5,0)$)で交わる。図は「半径5の円の内部のうち,双曲線の2つの枝に挟まれた部分」(境界含む,点 $(5,0)$ のみ除く)。$txt$,
$txt$空間の問題に見えるが,$\mathrm{P},\mathrm{Q}$ が $xy$ 平面に固定されているので,「重心の条件で $\mathrm{R}$ を消去」すれば実質は平面の問題になる。動点が3つあるときは,従属する点を1つの代表点(ここでは中点 $\mathrm{M}$)にまとめて自由度を下げるのが定石。

(1)で $\mathrm{M}$ の軌跡が円とわかった瞬間,(2)は「円周上を中点が動く弦の通過範囲」という古典的な設定に落ちる。通過範囲は「点 $(X,Y)$ を固定して,そこを通る弦(を与える $\varphi$)が存在するか」と逆向きに読む(逆像法)。パラメータが角 $\varphi$ なら,存在条件は三角関数の合成で「振幅 ≧ 右辺」と一発で書ける — 包絡線を求めるより論証が軽い。

境界に双曲線が現れるのは,弦の族の包絡線が円錐曲線になるため。答えの図の妥当性チェック(頂点 $(1,0),(5,0)$ が $\mathrm{M}$ の円の端に対応)にも使える。$txt$,
$txt$・(2)は $\mathrm{M}=(x_0,y_0)$ とおき,弦の方程式 $x_0X+y_0Y=x_0^2+y_0^2$ と円 $(x_0-3)^2+y_0^2=4$ を連立し,$(x_0,y_0)$ の実数解の存在条件として処理してもよい(合成の代わりに判別式)。
・弦の方程式を $\varphi$ で微分して連立すれば包絡線 $\dfrac{(X-3)^2}{4}-\dfrac{Y^2}{5}=1$ が直接出る。図の根拠としては強力だが,「通過範囲=包絡線の内側」の論証を別に書く必要があり,答案としては存在条件の方が安全。$txt$,
$txt$・(1)で逆の確認(円上の点なら実際に $\mathrm{P},\mathrm{Q},\mathrm{R}$ が取れる)や,退化する点 $(5,0)$ の除外を落とす。
・(2)で「直線の通過範囲」を求めてしまい,円の外側まで塗る($\mathrm{PQ}$ は線分=弦)。
・合成の存在条件で両辺の符号(0以上)に触れず2乗する。
・除外点 $\varphi=0$ の影響が $(5,0)$ だけに限られることの確認を飛ばす。
・双曲線と円の交点($x=-5/3$)の計算ミス。$txt$,
$txt$・(1)は軌跡なので必要(条件から円が出る)と十分(円上なら実現できる)の両方を書く。$\mathrm{R}\ne\mathrm{P},\mathrm{Q}$($z$ 座標 $3\ne0$)への言及。
・(2)「$(X,Y)$ を通る弦が存在する ⟺ $\varphi$ の方程式が解をもつ」という言い換えの向きを明示。
・図には双曲線の頂点・漸近線・円との交点 $\left(-\frac{5}{3},\pm\frac{10\sqrt2}{3}\right)$・除外点 $(5,0)$ を明記。$txt$,
$txt$・重心・中点などの従属点で動点を消去し,自由度を減らしてから軌跡を求める。
・線分・直線の通過範囲は「存在条件への言い換え(逆像法)」が第一候補。角パラメータなら三角関数の合成が存在条件そのもの。
・軌跡・通過範囲の「除外点」はもとの図形の退化($\mathrm{P}=\mathrm{Q}$)から生じる — パラメータの端で何が退化するかを常に確認する。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 3
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 東京大学 2026 前期理系 第4問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 4, 40,
$txt$三次関数の接線/2直線のなす角と傾き($\tan$ の加法定理)/傾斜角/正三角形の面積/比の処理$txt$,
$txt$① 接点 $x=t$ での接線の傾きは $3t^2-k$。とくに $\mathrm{O}$ での傾きは $-k$ で,これは接線の傾きの最小値($t\ne0$ なら傾きは $-k$ より大)。

② どの2本も $\dfrac{\pi}{3}$ で交わる ⟺ 3本の傾斜角が $\theta_0,\ \theta_0\pm\dfrac{\pi}{3}$($\theta_0$ は $\mathrm{O}$ の接線の傾斜角)。$\mathrm{P},\mathrm{Q}$ の接線の傾きは $-k$ より大きいので,$\tan\!\left(\theta_0\pm\dfrac{\pi}{3}\right)>-k$ が存在条件。加法定理で整理すると $\tan\theta_0=-k<-\dfrac{1}{\sqrt3}$。

③ (2) なす角がすべて $60^\circ$ なので3接線の三角形は正三角形。面積は $\mathrm{O}$ の接線上の2交点間距離だけで決まり $S=\dfrac{\sqrt3}{9}(1+k^2)(p-q)^2$。$p=\pm\sqrt A,\ q=\pm\sqrt B$ の符号で $S$ は $(\sqrt B\pm\sqrt A)^2$ の2通り。$M=4m$ ⟺ $B=9A$ を $k$ で解く。$txt$,
$txt$(1) $k>\dfrac{\sqrt3}{3}$
(2) $k=\dfrac{5\sqrt3}{12}$$txt$,
$txt$$y'=3x^2-k$ より,接点の $x$ 座標が $t$ の接線の傾きは $3t^2-k$,接線の方程式は $y=(3t^2-k)x-2t^3$。

(1) $\mathrm{O}$($t=0$)での傾きは $-k$。$\mathrm{P}(t=p\ne0),\ \mathrm{Q}(t=q\ne0)$ での傾き $3p^2-k,\ 3q^2-k$ はいずれも $-k$ より大きい。
$\mathrm{O}$ の接線の傾斜角を $\theta_0$($\tan\theta_0=-k$)とする。3本がどの2本も $\dfrac{\pi}{3}$ で交わるのは,3本の傾斜角が($\pi$ の差を除いて)$\theta_0,\ \theta_0+\dfrac{\pi}{3},\ \theta_0-\dfrac{\pi}{3}$ と等間隔に並ぶときに限る。よって
$$\{3p^2-k,\ 3q^2-k\}=\left\{\tan\!\left(\theta_0+\frac{\pi}{3}\right),\ \tan\!\left(\theta_0-\frac{\pi}{3}\right)\right\}$$
となる $p,q\ne0$ が存在すればよく,その条件は2つの $\tan$ がともに定義されて $-k$ より大きいこと。$t=\tan\theta_0=-k$ とおくと加法定理より
$$\tan\!\left(\theta_0+\frac{\pi}{3}\right)-t=\frac{t+\sqrt3}{1-\sqrt3\,t}-t=\frac{\sqrt3(1+t^2)}{1-\sqrt3\,t},\qquad \tan\!\left(\theta_0-\frac{\pi}{3}\right)-t=-\frac{\sqrt3(1+t^2)}{1+\sqrt3\,t}$$
両方が正 ⟺ $1-\sqrt3\,t>0$ かつ $1+\sqrt3\,t<0$ ⟺ $t<-\dfrac{1}{\sqrt3}$ ⟺ $k>\dfrac{1}{\sqrt3}=\dfrac{\sqrt3}{3}$。
このとき分母は0でない($\tan$ は定義される)。また2つの傾きは異なるので $p^2\ne q^2$,どの2本も平行でなく必ず交わる。
答: $k>\dfrac{\sqrt3}{3}$

(2) $A=p^2=\dfrac{1}{3}\left\{\tan\!\left(\theta_0+\dfrac{\pi}{3}\right)+k\right\},\ B=q^2=\dfrac{1}{3}\left\{\tan\!\left(\theta_0-\dfrac{\pi}{3}\right)+k\right\}$ とおくと,(1)の計算に $t=-k$ を代入して
$$A=\frac{\sqrt3(1+k^2)}{3(1+\sqrt3 k)},\qquad B=\frac{\sqrt3(1+k^2)}{3(\sqrt3 k-1)}$$
$k>\dfrac{\sqrt3}{3}$ では $0<A<B$。$p=\pm\sqrt A,\ q=\pm\sqrt B$。
$\mathrm{O}$ の接線 $y=-kx$ と接点 $t$ の接線の交点の $x$ 座標は $\dfrac{2t}{3}$ だから,$\mathrm{O}$ の接線上の2交点間の距離は $\left|\dfrac{2p}{3}-\dfrac{2q}{3}\right|\sqrt{1+k^2}$。3本の内角はすべて $\dfrac{\pi}{3}$ なので三角形は正三角形であり
$$S=\frac{\sqrt3}{4}\cdot\frac{4}{9}(p-q)^2(1+k^2)=\frac{\sqrt3}{9}(1+k^2)(p-q)^2$$
$(p,q)\to(-p,-q)$ は原点対称で面積不変だから,$S$ の値は符号の組合せにより
$$S_1=\frac{\sqrt3}{9}(1+k^2)(\sqrt B-\sqrt A)^2,\qquad S_2=\frac{\sqrt3}{9}(1+k^2)(\sqrt B+\sqrt A)^2$$
の2通り($p\ne q$ かつ $p\ne-q$ なので $S=0$ は起こらない)。よって $m=S_1,\ M=S_2$ で
$$M=4m\ \Longleftrightarrow\ (\sqrt B+\sqrt A)^2=4(\sqrt B-\sqrt A)^2\ \Longleftrightarrow\ \sqrt B+\sqrt A=2(\sqrt B-\sqrt A)\ \Longleftrightarrow\ B=9A$$
$$\frac{B}{A}=\frac{1+\sqrt3 k}{\sqrt3 k-1}=9\ \Longleftrightarrow\ 1+\sqrt3 k=9\sqrt3 k-9\ \Longleftrightarrow\ \sqrt3 k=\frac{5}{4}\ \Longleftrightarrow\ k=\frac{5\sqrt3}{12}$$
これは $k>\dfrac{\sqrt3}{3}=\dfrac{4\sqrt3}{12}$ を満たす。
答: $k=\dfrac{5\sqrt3}{12}$$txt$,
$txt$「なす角がすべて $\dfrac{\pi}{3}$」は,3本の方向(傾斜角)が $60^\circ$ ずつの等間隔に並ぶことと同値 — まず角の条件を傾き($\tan$)の条件に翻訳する。

(1)の本質は「接線の傾き $3t^2-k$ は $-k$ より小さくなれない」という値域の制限。$\mathrm{O}$ の接線が"一番緩い"方向なので,そこから $\pm60^\circ$ 回した方向の接線が実在できるかが問われている。$\tan(\theta_0\pm60^\circ)-\tan\theta_0$ の符号だけ調べればよい,と気づくと計算は加法定理1回で済む。

(2)は「3方向が固定なら三角形は常に正三角形」に気づくのが分かれ目。面積が1辺(=$\mathrm{O}$ の接線上の線分)だけで決まるので,頂点座標を全部求める必要がない。$M=4m$ のような比の条件は,面積比→辺の比→ $\sqrt A,\sqrt B$ の比,と次数を下げてから処理する。$txt$,
$txt$・(1)は「傾き $m$ の接線が存在 ⟺ $m\geqq-k$($m=-k$ は $\mathrm{O}$ のみ)」と値域で整理し,単位円上で $\theta_0,\theta_0\pm60^\circ$ の $\tan$ の大小を図で判断してもよい。
・(2)は3交点の座標(接点 $a,b$ の接線の交点の $x$ 座標が $\dfrac{2(a^2+ab+b^2)}{3(a+b)}$)を求めて座標の面積公式で計算しても出る(正三角形に気づけば不要)。
・傾きを使わず,3接線の傾斜角を $\theta_0,\theta_0\pm\dfrac{\pi}{3}$ とおいて全体を $\theta_0$ で表す方針もある。$txt$,
$txt$・「2直線のなす角は $0$ 以上 $\dfrac{\pi}{2}$ 以下」の規約を忘れ,傾斜角の差 $\dfrac{2\pi}{3}$ の組(なす角としては $\dfrac{\pi}{3}$)を別扱いして場合を増やす/落とす。
・接線が鉛直になる($\tan$ が定義されない)可能性の検討漏れ(本問は(1)の不等式処理で自動的に除かれる)。
・(2)で符号の組合せを $(\sqrt A,\sqrt B)$ しか考えず,$M$ と $m$ の区別がつかない。
・3線が1点で交わる($S=0$)場合の検討を書かない(交点の $x$ 座標 $\frac{2p}{3}\ne\frac{2q}{3}$ から起こらない)。$txt$,
$txt$・「どの2本も $\frac{\pi}{3}$ ⟺ 傾斜角が等間隔 $\theta_0,\theta_0\pm\frac{\pi}{3}$」の同値性の説明。
・(1)は存在条件の必要十分をきちんと構成する($p^2>0$ ⟺ 傾き $>-k$)。
・どの2本も「交わる」(平行でない)ことの確認。
・(2)三角形が正三角形である根拠(3つの内角がすべて $\frac{\pi}{3}$)を一言。
・最後に $k$ が(1)の範囲に入ることの確認。$txt$,
$txt$・直線のなす角の条件は傾斜角に翻訳する。「すべての組が同角」なら方向は等間隔。
・接線の傾きの値域($3t^2-k\geqq-k$)のような"見えない制約"が存在条件の正体になることが多い。
・図形量(面積)は最少の変数で表してから条件式へ。角が固定された三角形は1辺で決まる。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 4
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 東京大学 2026 前期理系 第5問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 4, 40,
$txt$複素数の極形式・偏角($n$ 乗で偏角 $n$ 倍)/3倍角の公式/円と半直線の位置関係(距離)/領域の対称性と面積$txt$,
$txt$(1) $u=z+3$ は中心 $3$,半径 $1$ の円上。偏角 $\psi$ は接線から $|\psi|\leqq\psi_0$($\sin\psi_0=\frac13$)で,$\theta=3\psi$。$3\psi_0<\frac{\pi}{2}$ を確認してから3倍角で $\sin3\psi_0$ を計算。

(2) $w=(z-\alpha)^3$ が正の実数 ⟺ $\arg(z-\alpha)\in\{0,\pm\frac{2\pi}{3}\}$,負の実数 ⟺ $\{\pi,\pm\frac{\pi}{3}\}$。つまり原点から $60^\circ$ おきの6本の半直線を交互に「正組」「負組」とし,$\beta=-\alpha$ を中心とする半径1の円(= $z-\alpha$ の軌跡)が両組と交わる条件にする。円が半直線と交わる ⟺ 中心から半直線への距離 $\leqq1$。$60^\circ$ 回転対称なので1つの扇形で四角形の面積を求めて6倍。$txt$,
$txt$(1) $-\dfrac{23}{27}\leqq\sin\theta\leqq\dfrac{23}{27}$
(2) $4\sqrt3$$txt$,
$txt$(1) $\alpha=-3$ のとき $w=(z+3)^3$。$u=z+3$ は中心 $3$,半径 $1$ の円上を動く。$u$ の偏角を $\psi$ とすると,原点からこの円に引いた接線を考えて
$$-\psi_0\leqq\psi\leqq\psi_0,\qquad \sin\psi_0=\frac{1}{3}\ \left(0<\psi_0<\frac{\pi}{2}\right)$$
であり,$\psi$ はこの範囲のすべての値をとる。$\theta=3\psi$ だから $\sin\theta=\sin3\psi$。
$\sin\psi_0=\dfrac13<\dfrac12$ より $\psi_0<\dfrac{\pi}{6}$,よって $3\psi\in[-3\psi_0,3\psi_0]\subset\left(-\dfrac{\pi}{2},\dfrac{\pi}{2}\right)$。この範囲で $\sin$ は単調増加だから,$\sin3\psi$ は $\psi=\pm\psi_0$ で最大・最小をとる。3倍角の公式より
$$\sin3\psi_0=3\sin\psi_0-4\sin^3\psi_0=1-\frac{4}{27}=\frac{23}{27}$$
答: $-\dfrac{23}{27}\leqq\sin\theta\leqq\dfrac{23}{27}$(この範囲のすべての値をとる)

(2) $z\ne\alpha$ のとき $\arg w=3\arg(z-\alpha)$ だから
$$w が正の実数\ \Longleftrightarrow\ \arg(z-\alpha)\in\left\{0,\ \frac{2\pi}{3},\ -\frac{2\pi}{3}\right\},\qquad w が負の実数\ \Longleftrightarrow\ \arg(z-\alpha)\in\left\{\pi,\ \frac{\pi}{3},\ -\frac{\pi}{3}\right\}$$
($w=0$ は正でも負でもない。)原点から偏角 $\dfrac{k\pi}{3}$($k=0,1,\dots,5$)に出る6本の半直線(原点は含めない)を $L_k$ とすると,$k$ 偶数の3本が「正組」,奇数の3本が「負組」。
$z$ が $C$ 上を動くとき $z-\alpha$ は $\beta=-\alpha$ を中心とする半径 $1$ の円 $K$ 上を動くから,条件は
$$K が L_0,L_2,L_4 のいずれかと交わり,かつ L_1,L_3,L_5 のいずれかとも交わる$$
円 $K$ が半直線 $L$ と共有点をもつ条件は,$\beta$ から $L$ への距離が $1$ 以下であること(端点の原点のみで接する例外は $|\beta|=1$ かつ接する場合に限られ,面積には影響しない)。
$\beta$ の偏角を $\omega$,絶対値を $\rho$ とする。全体は $60^\circ$ 回転で不変だから $0\leqq\omega\leqq\dfrac{\pi}{3}$ の扇形で考えると,この範囲の $\beta$ に最も近い正組は $L_0$,負組は $L_1$ で(他の半直線への距離はこれ以上),距離はそれぞれ $\rho\sin\omega,\ \rho\sin\!\left(\dfrac{\pi}{3}-\omega\right)$。条件は
$$\rho\sin\omega\leqq1\ かつ\ \rho\sin\!\left(\frac{\pi}{3}-\omega\right)\leqq1$$
境界はそれぞれ「$L_0$ から距離1の直線」「$L_1$ から距離1の直線」で,その交点は偏角 $\dfrac{\pi}{6}$,$\rho=2$ の点。よって扇形内の領域は,O,$\mathrm{A}\left(\rho=\dfrac{2}{\sqrt3},\ \omega=0\right)$,$\mathrm{B}\left(\rho=2,\ \omega=\dfrac{\pi}{6}\right)$,$\mathrm{C}\left(\rho=\dfrac{2}{\sqrt3},\ \omega=\dfrac{\pi}{3}\right)$ を頂点とする四角形で,その面積は
$$\triangle\mathrm{OAB}+\triangle\mathrm{OBC}=\frac{1}{2}\cdot\frac{2}{\sqrt3}\cdot2\sin\frac{\pi}{6}\times2=\frac{2}{\sqrt3}$$
全体はこれが6つ分だから $\beta$ の範囲の面積は $6\times\dfrac{2}{\sqrt3}=4\sqrt3$。
$\alpha=-\beta$(原点対称)なので $\mathrm{R}(\alpha)$ の範囲の面積も等しく
答: $4\sqrt3$$txt$,
$txt$3乗写像は「絶対値を3乗,偏角を3倍」— よって「$w$ が実軸上」は「$z-\alpha$ の偏角が $\dfrac{\pi}{3}$ の倍数」という角度だけの条件になる。図形化すると「原点から $60^\circ$ おきの6本の半直線」で,3倍して偏角 $0$ になる組(正)と $\pi$ になる組(負)が交互に並ぶ。ここまで言い換えられれば,(2)は複素数の問題ではなく平面図形の問題。

主役は $\alpha$ でなく円の中心 $\beta=-\alpha$。「円がある集合と交わる ⟺ 中心がその集合から距離1以内」と,動く円の条件を中心の位置の条件に引き戻す(逆像法の発想)。

(1)は(2)の布石: 「円上の点の偏角の範囲は原点からの接線で決まる」ことを確認させている。$3\psi_0<\dfrac{\pi}{2}$ のチェック($\sin\psi_0=\frac13<\frac12$)が単調性の根拠で,これを飛ばすと答えだけ合う危うい答案になる。$txt$,
$txt$・(2)の扇形1枚の面積は,極座標の積分 $\displaystyle\int_{\pi/6}^{\pi/3}\frac{1}{2}\cdot\frac{d\omega}{\sin^2\omega}\times2=\left[-\frac{\cot\omega}{2}\right]\times2$ でも計算できる(結果 $\frac{2}{\sqrt3}$ は同じ)。四角形分割なら積分不要。
・全体を「頂点が交互に $\rho=\frac{2}{\sqrt3}$ と $\rho=2$ の12角形」とみて,面積 $=12\times\frac12\cdot\frac{2}{\sqrt3}\cdot2\sin30^\circ=4\sqrt3$ とまとめる見方もある。
・(1)は $u=3+\cos t+i\sin t$ とおいて $\sin\theta$ を $t$ で表し微分する方法もあるが,計算が重い。$txt$,
$txt$・「正の実数」の条件を $\arg(z-\alpha)=0$ だけとし,$\pm\dfrac{2\pi}{3}$(3倍すると $\pm2\pi$)を落とす — 領域が過小になる最頻出ミス。
・$w=0$($z=\alpha$)を正または負に含めてしまう。
・「円と半直線」の交わり条件を「円と直線」(距離 $\leqq1$)で済ませ,半直線の端(原点)側の処理を曖昧にする。
・(1)で $3\psi_0<\dfrac{\pi}{2}$ を確認せずに $\sin$ の単調性を使う。
・$\alpha$ と $\beta=-\alpha$ の混同(最後に対称性で戻すのを忘れる)。$txt$,
$txt$・$w$ が正(負)の実数 ⟺ $\arg(z-\alpha)$ の条件,の同値変形($\bmod\ 2\pi$ の処理)を明示。
・「円が半直線と共有点をもつ ⟺ 中心から半直線への距離 $\leqq1$」の根拠(端点だけで接する例外への言及があればより丁寧)。
・$60^\circ$ 回転対称で1つの扇形に帰着する際,その扇形で最近接の半直線が $L_0,L_1$ である理由を一言。
・(1)は $\psi$ の範囲(接線・$\sin\psi_0=\frac13$)と単調性の確認,および値がすべて実現されること。$txt$,
$txt$・$z\mapsto z^n$ で実軸に乗る条件は「偏角が $\frac{\pi}{n}$ の倍数」— 半直線 $2n$ 本の構図として図形化する。
・「動く図形(円)が集合と交わる」条件は中心の条件(距離 $\leqq$ 半径)へ言い換えるのが定石。
・回転対称な領域は1周期分 $\times$ 個数。四角形などへの分割で積分を回避できることが多い。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 5
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 東京大学 2026 前期理系 第6問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 3, 35,
$txt$約数と素因数分解(約数の個数の積の公式)/合同式($\bmod\ 3$)/分配法則による展開(積の形の数え上げ)$txt$,
$txt$① $\bmod\ 3$ では $2\times2\equiv1,\ 2\times1\equiv2$: 約数 $d$ の余りは「$3$ で割って $2$ 余る素因数の指数の総和の偶奇」だけで決まる。

② $n=3^c m$($3\nmid m$)として $f(n)=f(m),\ g(n)=g(m)$。$m$ の素因数を余り $1$ の組($p_i$)と余り $2$ の組($q_j$)に分け,$f-g$ を「符号 $(-1)^{指数和}$ 付きの数え上げ」とみると素数ごとの積に分解でき,$f-g\geqq0$ が出る。

③ (3)は $f+g=$ 総数,$f-g=P\Delta$($\Delta\in\{0,1\}$)の連立。$g=15$ から $P(B'-1)=30$ 型の整数問題に落として数え上げ,実現例も添える。$txt$,
$txt$(1) $f(2800)=16,\ g(2800)=14$
(2) 証明問題(完全解答を参照)
(3) $f(n)=15,\ 16,\ 18,\ 20,\ 30$$txt$,
$txt$準備: $3$ の倍数の約数は $f,g$ のどちらにも数えないので,$n=3^c m$($3\nmid m$)と書くと $f(n)=f(m),\ g(n)=g(m)$。$3\nmid d$ の $d$ を $3$ で割った余りは,$2\cdot2\equiv1,\ 2\cdot1\equiv2\pmod3$ を繰り返すことで,「$d$ のもつ『$3$ で割って $2$ 余る素因数』の個数(重複込み)が偶数なら $1$,奇数なら $2$」とわかる。

(1) $2800=2^4\cdot5^2\cdot7$。$2\equiv2,\ 5\equiv2,\ 7\equiv1\pmod3$。約数 $2^a5^b7^c$($0\leqq a\leqq4,\ 0\leqq b\leqq2,\ 0\leqq c\leqq1$)が $1$ 余る ⟺ $a+b$ が偶数。
$(a,b)$ で $a+b$ 偶数は(偶,偶)$3\times2=6$ 通り,(奇,奇)$2\times1=2$ 通りの計 $8$ 通り。$c$ は $2$ 通りずつ。
$$f(2800)=8\times2=16,\qquad g(2800)=30-16=14(総約数は 5\cdot3\cdot2=30)$$

(2) $m=p_1^{a_1}\cdots p_s^{a_s}\,q_1^{b_1}\cdots q_t^{b_t}$($p_i\equiv1,\ q_j\equiv2\pmod3$)とする。$m$ の約数は各素数の指数 $\alpha_i\ (0\leqq\alpha_i\leqq a_i),\ \beta_j\ (0\leqq\beta_j\leqq b_j)$ を独立に選んで得られ,余りは $B=\beta_1+\cdots+\beta_t$ の偶奇で決まる($B$ 偶数 ⟺ 余り $1$)。$p_i$ 側の選び方は共通に $P=(a_1+1)\cdots(a_s+1)$ 通りずつあるから
$$f(m)-g(m)=P\sum_{\beta_1=0}^{b_1}\cdots\sum_{\beta_t=0}^{b_t}(-1)^{\beta_1+\cdots+\beta_t}=P\prod_{j=1}^{t}\left(\sum_{\beta=0}^{b_j}(-1)^{\beta}\right)$$
(最後の等号は分配法則による展開)。各因子は
$$\sum_{\beta=0}^{b_j}(-1)^\beta=\begin{cases}1&(b_j\ 偶数)\\ 0&(b_j\ 奇数)\end{cases}$$
だから $f(m)-g(m)=P\Delta$($\Delta=0$ または $1$)$\geqq0$。$t=0$(余り $2$ の素因数がない)ときも $f=P,\ g=0$ で成立。∎

(3) (2)の記号で $f+g=P\cdot B'$($B'=(b_1+1)\cdots(b_t+1)$),$f-g=P\Delta$。
・ある $b_j$ が奇数($\Delta=0$)のとき: $f=g=15$。実現例: $m=2\cdot p^{14}$($p\equiv1\pmod3$,例えば $p=7$)なら $f=g=15$。
・すべての $b_j$ が偶数($\Delta=1$)のとき: $B'$ は奇数の積で奇数,$g=\dfrac{P(B'-1)}{2}=15$ より $P(B'-1)=30$。$B'-1$ は偶数だから
$$B'-1\in\{2,6,10,30\},\qquad (P,B')=(15,3),(5,7),(3,11),(1,31)$$
いずれも $B'$ は奇数で,$q^2,\ q^6,\ q^{10},\ q^{30}$($q\equiv2\pmod3$)などで実現できる(例: $(P,B')=(15,3)$ は $m=7^{14}\cdot2^2$)。このとき
$$f=g+P=15+P=30,\ 20,\ 18,\ 16$$
以上より $f(n)$ のとりうる値は $15,\ 16,\ 18,\ 20,\ 30$。$txt$,
$txt$$\bmod\ 3$ では $2\equiv-1$ — つまり「余り $2$ の素因数を1個掛けるたびに符号が反転する」と読むのが全体の見取り図。(1)はこの仕組みを数値で体験させる実験台で,「指数の偶奇がすべて」と気づけば(2)(3)の設計図が見える。

(2)の核心は $f-g=\sum_{d\mid m}(\pm1)$ という「符号付き数え上げ」への言い換え。約数の個数公式 $(a_1+1)\cdots$ が積に分解するのと全く同じ理屈で,符号付きの和も素数ごとの積に分解する(分配法則)。「余り $2$ の素数で指数が奇数のものが1つでもあれば差は $0$,全部偶数なら差は $P$」という完全な公式が得られ,(3)はその応用問題になる — 誘導の流れが一直線。

(3)では「$f-g=0$ の場合」を落とさないこと。$\Delta=0$ と $\Delta=1$ で場合の構造がまったく違う。$txt$,
$txt$・(2)は $t$(余り $2$ の素数の種類数)に関する帰納法でも証明できる: $q^{b}$ を掛けると $f'=f\cdot\lceil\frac{b+1}{2}\rceil+g\cdot\lfloor\frac{b+1}{2}\rfloor$,$g'$ はその逆,と漸化式を立てて差 $f'-g'=(f-g)\times(1\ または\ 0)$ を追う。
・(2)の組合せ的別証: すべての $b_j$ が偶数のとき,約数を「最初の $q_j$ の指数を $\pm1$ ずらす」対応でペアにすると余り $1$ と余り $2$ が打ち消し合い,対応のつかない約数(全指数偶数)がちょうど $P$ 個残る。$txt$,
$txt$・$3^c$ の扱い: 「$3$ の倍数の約数」は $f,g$ に入らないだけで,$n$ が $3$ を素因数にもっても $f,g$ は変わらない — ここを混同する。
・(1)で $7\equiv1$ を余り $2$ 側に入れるなどの取り違え。
・(3)で $\Delta=0$(ある $b_j$ が奇数)の場合を忘れ,答えから $15$ が抜ける。
・$B'=1$($t=0$)だと $g=0\ne15$ で不適,の確認漏れ。
・「とりうる値」なのに実現例(構成)を示さず,必要条件だけで終える。$txt$,
$txt$・「約数の余りが指数和の偶奇で決まる」根拠($2\cdot2\equiv1\pmod3$)の明示。
・(2)の $\sum(-1)^B$ を積に分解する等号は「分配法則で展開」の一言(または帰納法で丁寧に)。
・(3)は「これらの値に限る」(必要)と「実際にとれる」(構成例)の両方を記述。
・$P,B'$ の意味(素因数分解の形との対応)を定義してから使う。$txt$,
$txt$・約数の数え上げは素因数ごとの独立性(積の構造)に分解する。条件付きの個数は符号 $(-1)^{\cdots}$ を付けると積に分解できる — 強力な一般手法。
・$\bmod\ p$ で $-1$ と合同な数を探して「符号」とみなすのは整数問題の常套手段。
・「とりうる値を求めよ」は必要条件で絞る+構成例で実現,の2部構成で書く。$txt$
from problems p
where p.university = '東京大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 6
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第1問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 3, 30,
$txt$対数関数の微分/増減表とグラフ/$\lim_{x\to+0}x\log x=0$/方程式の解の個数とパラメータ/同値変形(逆数・平方根)$txt$,
$txt$① $f(x)=\dfrac{1}{\{x\log(a/x)\}^2}$ と見て,$h(x)=x\log\dfrac{a}{x}=x(\log a-\log x)$ を導入する($0<x<1$ で $h>0$)。$f(x)=k$ ⟺ $h(x)=\dfrac{1}{\sqrt k}$($k>0$)。

② $h'(x)=\log\dfrac{a}{ex}$ より $h$ は $x=\dfrac{a}{e}$ で極大。$a\geqq e$ なら $(0,1)$ で単調増加で解は高々1個。

③ $1<a<e$ のとき $h$ の山の高さ $\dfrac{a}{e}$ と右端の極限値 $\log a$($x=1$ は定義域外)の大小($\dfrac{a}{e}>\log a$)を確認し,水平線 $h=c$ との交点が2個 ⟺ $\log a<c<\dfrac{a}{e}$。$c=\dfrac{1}{\sqrt k}$ を $k$ に戻す。$txt$,
$txt$$1<a<e$ かつ $\dfrac{e^2}{a^2}<k<\dfrac{1}{(\log a)^2}$ の表す領域(境界は含まない)。2曲線 $k=\dfrac{e^2}{a^2}$,$k=\dfrac{1}{(\log a)^2}$ はともに減少で,$a\to1+0$ でそれぞれ $e^2$,$+\infty$,点 $(e,\ 1)$ で交わる。求める領域はこの2曲線に挟まれた部分。$txt$,
$txt$$f(x)>0$ だから $k\leqq0$ のとき共有点は $0$ 個。以下 $k>0$ とする。
$0<x<1,\ a>1$ では $\dfrac{a}{x}>1$ より $\log\dfrac{a}{x}>0$。そこで
$$h(x)=x\log\frac{a}{x}=x(\log a-\log x)\ (>0)$$
とおくと $f(x)=\dfrac{1}{h(x)^2}$ であり
$$f(x)=k\ \Longleftrightarrow\ h(x)=\frac{1}{\sqrt k}\ (=c\ とおく,\ c>0)$$
よって共有点の個数は $h(x)=c$($0<x<1$)の解の個数に等しい。

$$h'(x)=\log a-\log x-1=\log\frac{a}{ex},\qquad h'(x)>0\ \Longleftrightarrow\ x<\frac{a}{e}$$

(i) $a\geqq e$ のとき: $\dfrac{a}{e}\geqq1$ なので $(0,1)$ で $h$ は単調増加。解は高々 $1$ 個で,「ちょうど $2$ 個」は起こらない。

(ii) $1<a<e$ のとき: $h$ は $\left(0,\dfrac{a}{e}\right]$ で増加,$\left[\dfrac{a}{e},1\right)$ で減少。
$x\to+0$ では $x\log x\to0$ より $h\to0$。極大値は $h\!\left(\dfrac{a}{e}\right)=\dfrac{a}{e}\log e=\dfrac{a}{e}$。$x\to1-0$ では $h\to\log a$($x=1$ は定義域に含まれない)。
ここで $1<a<e$ において $\dfrac{a}{e}>\log a$ を確認する: $\varphi(a)=\dfrac{a}{e}-\log a$ は $\varphi'(a)=\dfrac{1}{e}-\dfrac{1}{a}<0$($a<e$)で減少し $\varphi(e)=0$,よって $\varphi(a)>0$。
増減とあわせて $h(x)=c$ の解の個数は
$$0<c\leqq\log a:\ 1個,\qquad \log a<c<\frac{a}{e}:\ 2個,\qquad c=\frac{a}{e}:\ 1個,\qquad c>\frac{a}{e}:\ 0個$$
よって「ちょうど $2$ 個」⟺ $\log a<\dfrac{1}{\sqrt k}<\dfrac{a}{e}$。各辺正だから逆数をとって2乗すると
$$\frac{e^2}{a^2}<k<\frac{1}{(\log a)^2}$$

以上より求める集合は
$$1<a<e\ かつ\ \frac{e^2}{a^2}<k<\frac{1}{(\log a)^2}$$
図示: $a>1$ で2曲線 $k=\dfrac{e^2}{a^2}$,$k=\dfrac{1}{(\log a)^2}$ はいずれも減少。$a\to1+0$ でそれぞれ $e^2$,$+\infty$ に向かい,$a=e$ でともに $k=1$(点 $(e,1)$ で交わる)。求める領域はこの2曲線の間の部分で,境界(2曲線および点 $(e,1)$)は含まない。$txt$,
$txt$$f$ は「(単純な関数)の $-2$ 乗」— 逆数と平方を外して $h(x)=x\log\dfrac{a}{x}$ の水平線との交点に言い換えるのが第一歩。複雑な関数のグラフを直接描こうとせず,同値変形で一番簡単な関数に落としてから増減を調べる。

「ちょうど $2$ 個」の型では,山の高さ($\frac{a}{e}$)と両端の極限値($0$ と $\log a$)の大小関係がすべてを決める。とくに $x=1$ が定義域外(開区間)なので $\log a$ は「近づくが到達しない値」— ここが境界 $k=\dfrac{1}{(\log a)^2}$ を含まない理由になっている。

パラメータが $(a,k)$ の2つあるが,「$a$ を固定して $k$ の範囲を出す」(1文字固定)と決めれば,残る作業は $\dfrac{a}{e}$ と $\log a$ の大小比較という微分の小問題だけ。$txt$,
$txt$・$h$ を経由せず $f'(x)$ を直接計算しても増減は出るが,$f'=-\dfrac{2h'}{h^3}$ なので結局 $h$ の増減に帰着し,計算だけ重くなる。
・$\dfrac{a}{e}>\log a$($1<a<e$)は「直線 $y=\dfrac{x}{e}$ と曲線 $y=\log x$ が $x=e$ で接する」ことからも見える(接線の議論)。
・$c=\dfrac{1}{\sqrt k}$ の代わりに $\sqrt k=\dfrac{1}{h}$ と見て,$\dfrac{1}{h(x)}$ の増減を調べても同じ結論に至る。$txt$,
$txt$・$x=1$ が定義域に入らないことを見落とし,境界 $k=\dfrac{1}{(\log a)^2}$ を領域に含めてしまう(最重要の失点ポイント)。
・$k\leqq0$ の処理(共有点 $0$ 個)を書かない。
・$a\geqq e$ の場合(単調で $2$ 個は不可能)の検討漏れ。
・$\dfrac{a}{e}$ と $\log a$ の大小を証明なしに使う。
・逆数・2乗の同値変形で各辺が正であることに触れない。$txt$,
$txt$・$f(x)=k\Longleftrightarrow h(x)=\dfrac{1}{\sqrt k}$ の同値変形($h>0,k>0$)の明示。
・$x\to+0$ で $h\to0$ に $\lim_{x\to+0}x\log x=0$ を使う旨(問題文で許可されている)。
・$\dfrac{a}{e}>\log a$ の証明。
・解の個数の場合分け(増減表またはグラフ)と,$c=\dfrac{a}{e}$ で $1$ 個などの端の扱い。
・図には交点 $(e,1)$,$a\to1+0$ の挙動($e^2$ と $+\infty$),境界を含まないことを明記。$txt$,
$txt$・「共有点の個数」は式を最も簡単な関数に同値変形してから(合成の外側 $\frac{1}{t^2}$ は単調変換として外す)。
・開区間の端の値は「極限として近づくが到達しない」— 個数が変わる境界がちょうどそこに現れる。
・2パラメータの領域図示は「1文字を固定して他方の範囲」(予選決勝法の発想)+境界曲線の概形・交点の明示。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 1
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第2問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 3, 25,
$txt$空間ベクトルの内積(正四面体では $\vec a\cdot\vec b=\frac12$ など)/2変数の2次式の最小・最大/球面(球の表面)と線分の位置関係$txt$,
$txt$① 球面は「面」— 線分 $\mathrm{BC}$ と共有点をもたない ⟺ $\mathrm{BC}$ 全体が球の内部,または全体が外部。「小さい $r$」と「大きい $r$」の2つの範囲が答えになりうる,とまず見抜く。

② $\mathrm{P}=t\vec a$,$\mathrm{BC}$ 上の点 $\mathrm{X}=(1-s)\vec b+s\vec c$ とおいて $|\mathrm{PX}|^2$ を計算すると
$$|\mathrm{PX}|^2=\left(t-\frac12\right)^2+\left(s-\frac12\right)^2+\frac12$$
と分離された形になる(対辺の対称性の現れ)。

③ $s$ を動かした最小(中点 $\mathrm{M}$,$s=\frac12$)と最大(端点 $\mathrm{B},\mathrm{C}$)を $t$ の式にし,「すべての $\mathrm{P}$ で内部」⟺ $r>\max=1$,「すべての $\mathrm{P}$ で外部」⟺ $r<\min=\dfrac{\sqrt2}{2}$。混在が起こらないことは連続性で一言。$txt$,
$txt$$0<r<\dfrac{\sqrt2}{2}$ または $r>1$$txt$,
$txt$球面は面なので,線分 $\mathrm{BC}$ と共有点をもたない ⟺ $\mathrm{BC}$ 上の点がすべて球の内部にある,またはすべて外部にある。$\mathrm{P}$ から線分 $\mathrm{BC}$ 上の点までの距離の最小値を $d_{\min}(\mathrm{P})$,最大値を $d_{\max}(\mathrm{P})$ とすると
$$\mathrm{P} を中心とする半径\ r\ の球面が\ \mathrm{BC}\ と交わらない\ \Longleftrightarrow\ r<d_{\min}(\mathrm{P})\ または\ r>d_{\max}(\mathrm{P})$$

$\vec a=\overrightarrow{\mathrm{OA}}$ 等とおくと $|\vec a|=|\vec b|=|\vec c|=1$,どの2つの内積も $\cos60^\circ=\dfrac12$。$\mathrm{P}=t\vec a$($0\leqq t\leqq1$),$\mathrm{X}=(1-s)\vec b+s\vec c$($0\leqq s\leqq1$)とすると
$$|\overrightarrow{\mathrm{PX}}|^2=|t\vec a-(1-s)\vec b-s\vec c|^2$$
$|(1-s)\vec b+s\vec c|^2=(1-s)^2+s^2+s(1-s)=1-s+s^2$,$\vec a\cdot\{(1-s)\vec b+s\vec c\}=\dfrac12$ より
$$|\overrightarrow{\mathrm{PX}}|^2=t^2-t+1-s+s^2=\left(t-\frac12\right)^2+\left(s-\frac12\right)^2+\frac12$$

$s$ について: 最小は $s=\dfrac12$($\mathrm{X}=\mathrm{BC}$ の中点 $\mathrm{M}$)で $d_{\min}(\mathrm{P})^2=\left(t-\dfrac12\right)^2+\dfrac12$,最大は $s=0,1$(端点)で $d_{\max}(\mathrm{P})^2=\left(t-\dfrac12\right)^2+\dfrac34$。

もし,ある $\mathrm{P}_1$ で $r<d_{\min}(\mathrm{P}_1)$,別の $\mathrm{P}_2$ で $r>d_{\max}(\mathrm{P}_2)\ (\geqq d_{\min}(\mathrm{P}_2))$ が同時に起こると,$d_{\min}(\mathrm{P})$ は $t$ の連続関数だから途中の $\mathrm{P}$ で $d_{\min}(\mathrm{P})=r$ となり,そのとき最近点が球面上に乗って共有点が生じる。よって「すべての $\mathrm{P}$」で条件が成り立つのは
$$r<\min_{0\leqq t\leqq1}d_{\min}(\mathrm{P})\qquad または\qquad r>\max_{0\leqq t\leqq1}d_{\max}(\mathrm{P})$$
の2通りに限る。
$$\min d_{\min}=\sqrt{\frac12}=\frac{\sqrt2}{2}\ (t=\tfrac12),\qquad \max d_{\max}=\sqrt{\frac14+\frac34}=1\ (t=0,1)$$
逆にこのとき条件を満たすことは明らか。等号($r=\dfrac{\sqrt2}{2}$: $\mathrm{P}$ が $\mathrm{OA}$ の中点のとき $\mathrm{M}$ が球面上,$r=1$: $\mathrm{P}=\mathrm{O}$ のとき $\mathrm{B}$ が球面上)は不適。

答: $0<r<\dfrac{\sqrt2}{2}$ または $r>1$$txt$,
$txt$「球面」は面であって中身の詰まった球ではない — 線分を完全に呑み込んでしまう大きい $r$ も条件を満たす。この読解が本問の核心で,ここに気づかないと答えの半分($r>1$)が丸ごと消える。「共有点をもたない」ときたら,内側に逃げるか外側に逃げるかの2通りを必ず疑う。

計算面では,$|\mathrm{PX}|^2=\left(t-\frac12\right)^2+\left(s-\frac12\right)^2+\frac12$ という変数分離形になるのが美しいポイント。正四面体の対辺 $\mathrm{OA},\mathrm{BC}$ は「ねじれの位置にあり,共通垂線が両方の中点を結ぶ」— この対称性ゆえに $t,s$ の最小が独立に($t=s=\frac12$ で)達成される。定数 $\frac12$ の平方根 $\dfrac{\sqrt2}{2}$ は正四面体の対辺間距離そのもの。

「すべての $\mathrm{P}$ で(小さい側)または(大きい側)」という条件は,$\mathrm{P}$ ごとに択一なので,$\min$ と $\max$ をとるだけでは済まない — 小さい側と大きい側が $\mathrm{P}$ によって混在しないことを連続性で排除する一言が論証の要。$txt$,
$txt$・座標設定($\mathrm{O}=(0,0,0),\ \mathrm{A}=(1,0,0),\ \mathrm{B}=(\frac12,\frac{\sqrt3}{2},0),\ \mathrm{C}=(\frac12,\frac{\sqrt3}{6},\frac{\sqrt6}{3})$)でも同じ計算ができる(内積の方が対称性を活かしやすい)。
・$d_{\min}$ は「点と直線 $\mathrm{BC}$ の距離」として垂線の足を求めて計算してもよい(足が線分内 $s=\frac12$ にあることの確認付き)。
・$\min d_{\min}=\dfrac{\sqrt2}{2}$ は「正四面体の対辺間距離(1辺 $1$ のとき $\frac{\sqrt2}{2}$)」として知られる値 — 導出込みで書けば引用してよい。$txt$,
$txt$・球面を球体と誤読し,$0<r<\dfrac{\sqrt2}{2}$ だけを答える(最頻出)。
・端の値を含めてしまう: $r=\dfrac{\sqrt2}{2}$ は $\mathrm{P}$ が $\mathrm{OA}$ の中点のとき,$r=1$ は $\mathrm{P}=\mathrm{O},\mathrm{A}$ のときに共有点が生じる。
・「すべての $\mathrm{P}$」を「ある $\mathrm{P}$」と取り違える/小さい側・大きい側の混在が起こらない理由(連続性)を書かない。
・$d_{\max}$ を中点で評価する,垂線の足が線分の外に出る可能性を検討しない,などの距離の取り扱いミス。$txt$,
$txt$・「球面と線分が共有点をもたない ⟺ 線分全体が内部または全体が外部」の言い換えの明示。
・$|\mathrm{PX}|^2$ の計算(内積の値 $\frac12$ を使う箇所)と,$s$ に関する最小・最大の根拠。
・すべての $\mathrm{P}$ に対する処理: $\min,\max$ をとる論理と,両側の混在が不可能なことへの言及。
・端点 $r=\frac{\sqrt2}{2},\ 1$ が除かれる理由。$txt$,
$txt$・「球面(面)との共有点なし」は内側・外側の2通り — 図形の表面と中身の区別を問う出題は京大が好む。
・距離の2乗が $(t-\alpha)^2+(s-\beta)^2+c$ に分離できたら,各変数の最小・最大は独立に決まる。
・正四面体の対辺間距離 $\dfrac{\sqrt2}{2}$(1辺 $1$)は導出ごと手の内に。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 2
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第3問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 4, 35,
$txt$二項定理/組合せの恒等式 $j\,{}_n\mathrm{C}_j=n\,{}_{n-1}\mathrm{C}_{j-1}$/整数の $2$ で割り切れる回数($2$ 進付値)の扱い/多項式の係数比較$txt$,
$txt$① $(x+1)^{2^{n+1}}=\{(x+1)^2\}^{2^n}=\{(x^2+1)+2x\}^{2^n}$ と「2乗の $2^n$ 乗」に読み替え,$(x^2+1)$ と $2x$ の二項定理で展開する。引く相手 $(x^2+1)^{2^n}$ がちょうど $j=0$ の項として相殺し,差は $j\geqq1$ の項の和になる。

② 各項の係数 ${}_{2^n}\mathrm{C}_j\cdot2^j$ が $2^{n+1}$ で割り切れることを,恒等式 $j\,{}_{2^n}\mathrm{C}_j=2^n\,{}_{2^n-1}\mathrm{C}_{j-1}$ から従う「${}_{2^n}\mathrm{C}_j$ は $2^{\,n-v}$ で割り切れる($2^v$ は $j$ を割り切る最大の $2$ べき)」で示す。鍵は $j-v\geqq1$。

③ 最大性: $x^1$ の係数は $j=1$ の項からしか出ず,ちょうど $2^{n+1}$。よって $2^{n+2}$ ではすべての係数を割り切れない。$txt$,
$txt$証明問題(完全解答を参照)。示すべき最大値は $m=n+1$。$txt$,
$txt$$F(x)=(x+1)^{2^{n+1}}-(x^2+1)^{2^n}$ とおく。$(x+1)^2=(x^2+1)+2x$ だから,二項定理より
$$F(x)=\{(x^2+1)+2x\}^{2^n}-(x^2+1)^{2^n}=\sum_{j=1}^{2^n}{}_{2^n}\mathrm{C}_j\,(2x)^j(x^2+1)^{2^n-j}$$
($j=0$ の項が $(x^2+1)^{2^n}$ と相殺する。)

[1] すべての係数が $2^{n+1}$ で割り切れること
$j\geqq1$ に対し $j=2^v u$($u$ は奇数,$0\leqq v\leqq n$)とする。組合せの恒等式
$$j\,{}_{2^n}\mathrm{C}_j=2^n\,{}_{2^n-1}\mathrm{C}_{j-1}$$
の右辺は $2^n$ で割り切れる整数で,左辺の $j$ は $2$ でちょうど $v$ 回割り切れるから,${}_{2^n}\mathrm{C}_j$ は $2^{\,n-v}$ で割り切れる。よって $j$ 番目の項の係数 ${}_{2^n}\mathrm{C}_j\cdot2^j$ は $2^{\,n-v+j}$ で割り切れる。ここで
$$j-v\geqq1\quad(\because\ j\geqq2^v\geqq v+1)$$
だから $n-v+j\geqq n+1$。ゆえに $F(x)$ のすべての係数は $2^{n+1}$ で割り切れる。
($2^v\geqq v+1$ は $v=0,1$ で等号成立,以降は左辺が倍々で増えるので明らか。)

[2] $2^{n+2}$ で割り切れない係数があること
$j$ 番目の項 ${}_{2^n}\mathrm{C}_j(2x)^j(x^2+1)^{2^n-j}$ は $x^j\times(x\ の偶数次式)$ なので,現れる最低次は $x^j$。よって $F(x)$ の $x^1$ の係数に寄与するのは $j=1$ の項だけであり,その値は
$${}_{2^n}\mathrm{C}_1\cdot2\cdot\{(x^2+1)^{2^n-1}\ の定数項\}=2^n\cdot2\cdot1=2^{n+1}$$
すなわち $x^1$ の係数はちょうど $2^{n+1}$ で,$2^{n+2}$ では割り切れない。

[1][2]より,すべての係数を割り切る $2^m$ の最大の $m$ は $n+1$ である。∎$txt$,
$txt$指数 $2^{n+1}=2\cdot2^n$ を見て「2乗してから $2^n$ 乗」と入れ子に読み替えるのが最大の関門。$(x+1)^2=(x^2+1)+2x$ は「引く相手 $(x^2+1)^{2^n}$ との差が $2x$ という"小さい項"」になるように作った変形で,二項定理を使うと差 $F$ が「$2x$ を1個以上含む項の和」として丸ごと取り出せる。

割り切りの評価では ${}_{2^n}\mathrm{C}_j$ の $2$ べきが必要になるが,高校範囲では $j\,{}_{n}\mathrm{C}_j=n\,{}_{n-1}\mathrm{C}_{j-1}$ (吸収公式)がその代用品 — 「${}_{2^n}\mathrm{C}_j$ は $2^{n-v}$ の倍数」が一行で出る。あとは $2^j$ の寄与と合わせて $j-v\geqq1$,つまり「$2^j$ は $j$ の $2$ べきより速く増える」だけの話。

最大性の証明は「一番調べやすい係数」を探す発想: 最低次 $x^1$ の係数は $j=1$ の項からしか来ないので,値がちょうど $2^{n+1}$ と即決できる。全係数を調べる必要はない。$txt$,
$txt$・$n$ についての数学的帰納法: $F_{n+1}=\{(x+1)^{2^{n+1}}\}^2-\{(x^2+1)^{2^n}\}^2=F_n\{F_n+2(x^2+1)^{2^n}\}$ と因数分解し,$F_n=2^{n+1}G_n$($G_n$ に奇数係数がある)とおくと $F_{n+1}=2^{n+2}G_n\{2^nG_n+(x^2+1)^{2^n}\}$。$x^1$ の係数の奇偶を追えば帰納法でも完結する(タグ「数学的帰納法」の想定ルート)。
・クンマーの定理(${}_{2^n}\mathrm{C}_j$ の $2$ べき $=n-v$)を知っていれば見通しは速いが,答案では証明を添える必要がある(上の吸収公式で置き換えるのが実戦的)。$txt$,
$txt$・「すべての係数が $2^{n+1}$ で割り切れる」だけ示して,最大性($2^{n+2}$ では割り切れない係数の存在)を忘れる — 問題は「最大の $m$」。
・係数の $2$ べきを $2^j$ の分しか数えず,${}_{2^n}\mathrm{C}_j$ 側の寄与($2^{n-v}$)を落として評価が届かない。
・$j-v\geqq1$($2^v\leqq j$ から)を証明なしに使う。
・$x^1$ の係数に $j\geqq2$ の項が混ざらない理由(各項の最低次が $x^j$)を書かない。$txt$,
$txt$・二項定理の展開式と $j=0$ の項の相殺を明示。
・吸収公式 $j\,{}_{2^n}\mathrm{C}_j=2^n\,{}_{2^n-1}\mathrm{C}_{j-1}$ は導出(定義式の変形)を一行添えると安全。
・「${}_{2^n-1}\mathrm{C}_{j-1}$ が整数」であることを使う旨。
・[1](すべて割り切れる)と[2](最大性)を独立の段落として明確に分ける。$txt$,
$txt$・$a^{2^{n+1}}$ 型は「2乗の $2^n$ 乗」と入れ子で見る。引く相手との差が小さくなる変形($(x+1)^2=(x^2+1)+2x$)を自分で作る。
・二項係数の素因数の個数は吸収公式 $k\,{}_n\mathrm{C}_k=n\,{}_{n-1}\mathrm{C}_{k-1}$ で引き出す — ルジャンドル・クンマーの高校版。
・「最大の $m$」=上からの評価(全部割り切れる)+下からの評価(割り切れない係数を1つ特定)のセット。特定するなら最低次・最高次など"寄与が1項しかない係数"を狙う。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 3
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第4問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 4, 40,
$txt$点と直線の距離/正三角形の内部の点と3辺の距離(Viviani の定理: 和が高さに等しい)/三角関数の合成・和積/最小値問題の「評価+構成」の枠組み$txt$,
$txt$① 最小値問題は「どんな置き方でも $s\geqq(下限)$」の評価と「その値を実現する配置」の構成の2部構成で設計する。

② 評価: 正方形の中心 $\mathrm{X}$ をとる。正三角形の内部の点から3辺への距離の和は高さ $\dfrac{\sqrt3}{2}s$ で一定(Viviani)。一方,正方形が各辺の内側にあることから,各辺への距離は「$\mathrm{X}$ からその辺の法線方向への正方形の張り出し $h(\psi)=\dfrac{|\cos\psi|+|\sin\psi|}{2}$」以上。

③ 3辺の法線は $120^\circ$ 間隔,$h$ は周期 $90^\circ$ — 3つの角は $\bmod\ 90^\circ$ で $30^\circ$ 間隔に並ぶ。和を $\sin$ の合成でまとめると最小値 $\dfrac{2+\sqrt3}{2}$(正方形の辺が三角形の辺と平行のとき)。$\dfrac{\sqrt3}{2}s\geqq\dfrac{2+\sqrt3}{2}$ から $s\geqq\dfrac{3+2\sqrt3}{3}$。

④ 構成: 正方形を底辺に載せると,高さ $1$ での三角形の幅がちょうど $1$ になり等号達成。$txt$,
$txt$$\dfrac{3+2\sqrt3}{3}\ \left(=1+\dfrac{2\sqrt3}{3}=1+\dfrac{2}{\sqrt3}\right)$$txt$,
$txt$正三角形 $T$ の1辺を $s$ とする。正方形の4頂点が $T$ の内部または辺上にあれば,$T$ は凸だから正方形全体が $T$ に含まれる。

[1] どんな配置でも $s\geqq\dfrac{3+2\sqrt3}{3}$ であること
正方形の中心を $\mathrm{X}$,$T$ の3辺(を含む直線)を $\ell_1,\ell_2,\ell_3$,$\mathrm{X}$ から $\ell_i$ への距離を $d_i$ とする。$\mathrm{X}$ は $T$ の内部(辺上含む)にあるから,$T$ を $\mathrm{X}$ と各辺を結ぶ3つの三角形に分割して面積を比べることで(Viviani の定理)
$$d_1+d_2+d_3=(T\ の高さ)=\frac{\sqrt3}{2}s$$
一方,正方形は各 $\ell_i$ の内側にあるから,$d_i$ は「$\mathrm{X}$ から $\ell_i$ の外向き法線方向に測った正方形の張り出し」以上である。正方形の頂点は中心から $\left(\pm\dfrac12,\pm\dfrac12\right)$(正方形基準の座標)にあるので,法線が正方形の辺と角 $\psi$ をなすとき張り出しは
$$h(\psi)=\frac{|\cos\psi|+|\sin\psi|}{2}$$
3辺の法線方向は互いに $120^\circ$ 異なる。$h$ は周期 $90^\circ$ だから,3方向の角は $\bmod\ 90^\circ$ で $\beta,\ \beta+30^\circ,\ \beta+60^\circ$($0^\circ\leqq\beta\leqq30^\circ$ にとれる)。$0^\circ\leqq\psi<90^\circ$ では $h(\psi)=\dfrac{\cos\psi+\sin\psi}{2}=\dfrac{\sqrt2}{2}\sin(\psi+45^\circ)\cdot\dfrac{1}{1}$ … すなわち $h(\psi)=\dfrac{\sqrt2}{2}\sin(\psi+45^\circ)$ だから
$$d_1+d_2+d_3\geqq\frac{\sqrt2}{2}\{\sin(\beta+45^\circ)+\sin(\beta+75^\circ)+\sin(\beta+105^\circ)\}$$
和積(加法定理)より $\sin(\beta+45^\circ)+\sin(\beta+105^\circ)=2\sin(\beta+75^\circ)\cos30^\circ=\sqrt3\sin(\beta+75^\circ)$ なので
$$d_1+d_2+d_3\geqq\frac{\sqrt2}{2}(1+\sqrt3)\sin(\beta+75^\circ)$$
$0^\circ\leqq\beta\leqq30^\circ$ より $75^\circ\leqq\beta+75^\circ\leqq105^\circ$ で $\sin(\beta+75^\circ)\geqq\sin75^\circ=\dfrac{\sqrt6+\sqrt2}{4}$。よって
$$\frac{\sqrt3}{2}s=d_1+d_2+d_3\geqq\frac{\sqrt2}{2}(1+\sqrt3)\cdot\frac{\sqrt6+\sqrt2}{4}=\frac{(1+\sqrt3)^2}{4}=\frac{2+\sqrt3}{2}$$
$$\therefore\ s\geqq\frac{2+\sqrt3}{\sqrt3}=\frac{3+2\sqrt3}{3}$$

[2] $s=\dfrac{3+2\sqrt3}{3}$ で条件 $(\ast)$ を満たせること
この $s$ の正三角形の底辺の中央に,正方形の1辺を底辺に重ねて置く。高さ $1$ の水平線における三角形の幅は
$$s-2\cdot\frac{1}{\tan60^\circ}=s-\frac{2}{\sqrt3}=1$$
だから,正方形の上の2頂点はちょうど左右の斜辺上に乗り,4頂点すべてが $T$ の辺上または内部にある。

[1][2]より,求める最小値は $\dfrac{3+2\sqrt3}{3}$。$txt$,
$txt$「置き方の自由度(位置+回転)すべてに対する最小値」なので,特定の配置の計算だけでは答案にならない — 「任意の配置に通用する下からの評価」をどう作るかが本題。

その道具が Viviani の定理(内部の点から3辺への距離の和=高さ,面積分割で一行証明)。「和が一定」の量に対して,各距離を正方形の「方向別の張り出し(支持距離)$h(\psi)$」で下から押さえると,配置の情報が回転角 $\beta$ ただ1つに圧縮される。あとは $90^\circ$ 周期(正方形)と $120^\circ$ 間隔(正三角形)の噛み合わせで3つの角が $30^\circ$ 間隔に並び,$\sin$ の和の最小値問題(1変数)に落ちる。

最小を与えるのは $\beta=0^\circ$ — つまり正方形の辺が三角形の辺と平行な,直感どおりの配置。だが「斜めに置いた方が得では?」という可能性を消すのがこの問題の存在意義であり,1変数化してから合成で一括処理する流れそのものが解答の価値になっている。$txt$,
$txt$・「1辺 $1$ の正三角形に入る最大の正方形の1辺 $q$ を求めて $\dfrac{1}{q}$ を答える」という双対の方針でも同じ計算になる。
・座標でのごり押し: 正方形を角 $\varphi$ だけ傾けて置き,3辺の半平面条件に4頂点を代入して必要な $s$ を $\varphi$ の関数として書き,微分で最小を調べる(場合分けが多く重いが完遂可能)。
・凸図形の一般論「最小の外接三角形は3辺すべてが図形に接する」を経由する方法(答案ではこの事実自体の証明が必要になる)。$txt$,
$txt$・「底辺に載せた配置が最適」を無証明で仮定し,その配置の計算だけで答える(評価パートの欠落 — 大幅減点)。
・Viviani の定理を無証明で使う(面積分割による証明を一行添える)。
・張り出し $h(\psi)$ の絶対値の付け方(最も外側の頂点を選ぶ)を誤る。
・$\bmod\ 90^\circ$ への折り返しで $\beta$ の範囲($0^\circ$〜$30^\circ$)の設定を誤る。
・等号成立の配置(構成)の検証($s-\frac{2}{\sqrt3}=1$ の幅計算)を書き忘れる。$txt$,
$txt$・「4頂点が $T$ 内 ⟺ 正方形全体が $T$ 内」(凸性)への一言。
・Viviani の定理の証明(3つの三角形への面積分割)。
・$d_i\geqq h(\psi_i)$ の根拠(正方形が各辺の内側にあること)の明示。
・$\beta$ の範囲の正当化と $\sin(\beta+75^\circ)\geqq\sin75^\circ$ の評価。
・構成(等号例)での幅の計算と「4頂点が辺上・内部にある」ことの確認。$txt$,
$txt$・図形の最小値問題=「全配置に対する評価」+「等号を実現する構成」。片方だけでは解答にならない。
・「和が一定」(Viviani 等)の量は,各項を下から押さえて配置の自由度を殺す強力な足場になる。
・図形の「方向 $\psi$ への張り出し(支持距離)」という見方は,凸図形の内接・外接問題全般で通用する。$90^\circ$ と $120^\circ$ のような周期の噛み合わせは $\bmod$(最小公倍数)で整理する。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 4
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第5問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 3, 30,
$txt$回転体の体積($x$ 軸まわり,外径 $^2-$ 内径 $^2$)/和積・積和の公式/絶対値を含む定積分/図形の対称性の利用$txt$,
$txt$① 上下関係: $\sin(x+a)-\sin(x-a)=2\cos x\sin a\geqq0$ — 常に $y_1=\sin(x+a)$ が上,$y_2=\sin(x-a)$ が下で,$x=\pm\dfrac{\pi}{2}$ で一致(囲む領域の確認)。

② 回転体の断面は「線分 $[y_2,y_1]$ が $x$ 軸をまたぐか」で変わる: またぐ($y_1y_2<0$)なら半径 $\max(|y_1|,|y_2|)$ の円板,またがないなら円環。$y_1y_2=\sin^2x-\sin^2a$ より境目は $|\sin x|=\sin a$,つまり $b=\min(a,\pi-a)$ とおいて $|x|=b$。

③ $y_1^2+y_2^2=1-\cos2x\cos2a$,$y_1^2-y_2^2=\sin2a\sin2x$,および領域の原点対称性($y_2(x)=-y_1(-x)$)を使い,$\max=\dfrac{(和)+|差|}{2}$ で一括計算する。$txt$,
$txt$$b=\min(a,\ \pi-a)$ とおくと $V=\pi b+\dfrac{3\pi}{2}\sin2b$。場合分けで書けば
$$0<a\leqq\frac{\pi}{2}:\ V=\pi a+\frac{3\pi}{2}\sin2a,\qquad \frac{\pi}{2}\leqq a<\pi:\ V=\pi(\pi-a)-\frac{3\pi}{2}\sin2a$$$txt$,
$txt$$y_1=\sin(x+a),\ y_2=\sin(x-a)$ とおく。$-\dfrac{\pi}{2}\leqq x\leqq\dfrac{\pi}{2}$ では
$$y_1-y_2=2\cos x\sin a\geqq0(等号は\ x=\pm\tfrac{\pi}{2})$$
なので $D_a$ は上端 $y_1$,下端 $y_2$ に挟まれ,両端 $x=\pm\dfrac{\pi}{2}$ で閉じる領域である。また
$$y_1y_2=\sin^2x-\sin^2a,\qquad y_1^2-y_2^2=(y_1+y_2)(y_1-y_2)=\sin2x\sin2a,\qquad y_1^2+y_2^2=1-\cos2x\cos2a$$
(積和・和積による。)$b=\min(a,\pi-a)$($0<b\leqq\dfrac{\pi}{2}$)とおくと $\sin b=\sin a,\ \cos2b=\cos2a,\ \sin2b=|\sin2a|$ で
$$y_1y_2<0\ \Longleftrightarrow\ \sin^2x<\sin^2a\ \Longleftrightarrow\ |x|<b$$

$x$ を固定した断面: 線分 $[y_2,y_1]$ を $x$ 軸のまわりに回すと
・$|x|<b$($y_1y_2<0$,線分が軸をまたぐ): 半径 $\max(|y_1|,|y_2|)$ の円板,面積 $\pi\max(y_1^2,y_2^2)$
・$b<|x|\leqq\dfrac{\pi}{2}$($y_1y_2\geqq0$): 内径 $\min(|y_1|,|y_2|)$,外径 $\max$ の円環,面積 $\pi|y_1^2-y_2^2|$

$y_1(-x)=-y_2(x)$ より $D_a$ は原点対称で,回転体は面 $x=0$ に関して対称。よって $V=2\times(0\leqq x\leqq\frac{\pi}{2}\ の部分)$。$0\leqq x\leqq\dfrac{\pi}{2}$ では $\sin2x\geqq0$ だから $|y_1^2-y_2^2|=\sin2b\sin2x$,また $\max(y_1^2,y_2^2)=\dfrac{(y_1^2+y_2^2)+|y_1^2-y_2^2|}{2}$ を用いて
$$\frac{V}{2\pi}=\int_0^b\left\{\frac{1-\cos2x\cos2b}{2}+\frac{\sin2b\sin2x}{2}\right\}dx+\int_b^{\pi/2}\sin2b\sin2x\,dx$$
各項を計算する:
$$\int_0^b\frac{1-\cos2x\cos2b}{2}dx=\frac{b}{2}-\frac{\sin2b\cos2b}{4},\qquad \int_0^b\frac{\sin2b\sin2x}{2}dx=\frac{\sin2b(1-\cos2b)}{4}$$
$$\int_b^{\pi/2}\sin2b\sin2x\,dx=\frac{\sin2b(1+\cos2b)}{2}$$
和は
$$\frac{V}{2\pi}=\frac{b}{2}+\frac{\sin2b}{4}\{-\cos2b+1-\cos2b+2+2\cos2b\}=\frac{b}{2}+\frac{3}{4}\sin2b$$
$$\therefore\ V=\pi b+\frac{3\pi}{2}\sin2b\qquad(b=\min(a,\pi-a))$$
場合分けで書くと($\sin2b=|\sin2a|$ に注意)
$$0<a\leqq\frac{\pi}{2}:\ V=\pi a+\frac{3\pi}{2}\sin2a,\qquad \frac{\pi}{2}\leqq a<\pi:\ V=\pi(\pi-a)-\frac{3\pi}{2}\sin2a$$
($a=\dfrac{\pi}{2}$ ではどちらも $V=\dfrac{\pi^2}{2}$ で一致。)$txt$,
$txt$$x$ 軸まわりの回転体で最初に確認すべきは「領域が回転軸をまたぐか」。またぐ区間では下半分が上半分に呑み込まれて断面は円板(内径 $0$),またがない区間では円環 — この場合分けの境目 $|\sin x|=\sin a$ を先に求めてしまえば,あとは積分の作業になる。

$\sin(x\pm a)$ の対は,差 $2\cos x\sin a$・積 $\sin^2x-\sin^2a$・平方差 $\sin2x\sin2a$ とすべて因数分解された形で回る — 「和積・積和を先に済ませてから積分する」のがこの型の鉄則。$\max=\dfrac{(和)+|差|}{2}$ の変形を使うと外径の場合分け($|y_1|$ か $|y_2|$ か)を吸収できて計算が半分になる。

$a$ と $\pi-a$ で答えが同じ($b=\min(a,\pi-a)$ だけで書ける)のは,$a\mapsto\pi-a$ が領域を合同に移すため — 答えの対称性チェックは検算として優秀。$txt$,
$txt$・$\max$ の変形を使わず,$|x|<b$ の中でさらに「$|y_1|$ と $|y_2|$ のどちらが外径か」($\sin2x$ の符号など)で区間を割って計算してもよい(本解より場合分けが増える)。
・$\dfrac{\pi}{2}<a<\pi$ は $a'=\pi-a$ と置き換えると $y_1,y_2$ が入れ替わるだけで領域が合同に移るので,最初に $0<a\leqq\dfrac{\pi}{2}$ に帰着させてから計算する書き方もある(答案の見通しが良い)。
・断面積を「上側部分の回転 ∪ 下側部分の回転」とみて $\pi\max(y_1^2,y_2^2)=\pi y_1^2+\pi y_2^2-\pi\min(\cdots)$ 式に分解する方法もあるが,結局同じ積分に帰着する。$txt$,
$txt$・領域が $x$ 軸をまたぐことに気づかず $V=\pi\int(y_1^2-y_2^2)dx$ をそのまま計算する(内外径の設定ミス,最頻出)。
・またぐ区間で外径を $y_1$ と決め打ちする($x<0$ 側では $|y_2|$ が外径になる部分がある)。
・$\dfrac{\pi}{2}<a<\pi$ での $\sin2a<0$ の処理($|\sin2a|=\sin2b$)を落とし,体積が負になる式を書く。
・境目 $|x|=b$ を $a$ とだけ書き,$a>\dfrac{\pi}{2}$ のとき $b=\pi-a$ になることを見落とす。$txt$,
$txt$・上下関係 $y_1\geqq y_2$ の証明(差の因数分解 $2\cos x\sin a$)と等号($x=\pm\frac{\pi}{2}$,領域が閉じること)。
・断面が円板になる区間と円環になる区間の判定($y_1y_2=\sin^2x-\sin^2a$ の符号)の明示。
・対称性($D_a$ が原点対称)を使う場合はその根拠 $y_1(-x)=-y_2(x)$ を書く。
・場合分けの最終形と,$a=\frac{\pi}{2}$ での値の一致(連続性)の確認があると丁寧。$txt$,
$txt$・$x$ 軸回転は「軸をまたぐか」の判定が最初の一手。またぐ区間は $\pi\max(y_1^2,y_2^2)$,またがない区間は $\pi|y_1^2-y_2^2|$。
・$\sin(x+a),\ \sin(x-a)$ の対は和・差・積をすべて因数分解してから扱う(積和・和積)。
・$\max=\dfrac{(和)+|差|}{2}$ は場合分けを式変形で吸収するテクニック。答えの対称性($a\leftrightarrow\pi-a$)で検算する。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 5
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;

-- ---- 京都大学 2026 前期理系 第6問 ----
insert into solutions
  (problem_id, difficulty, target_time_min, prerequisites, approach, answer,
   full_solution, insight, alternatives, common_mistakes, grading_notes, takeaways)
select p.id, 2, 20,
$txt$組合せ ${}_n\mathrm{C}_r$ の計算/期待値の定義/$\displaystyle\sum_{k=r}^{n}{}_k\mathrm{C}_r={}_{n+1}\mathrm{C}_{r+1}$(ホッケースティック恒等式)$txt$,
$txt$最大値が $k$ となるのは「$k$ の札を取り,残り $2$ 枚を $1$〜$k-1$ から取る」場合だから
$$P(X=k)=\dfrac{{}_{k-1}\mathrm{C}_2}{{}_n\mathrm{C}_3}$$
期待値の和は $k\cdot{}_{k-1}\mathrm{C}_2=3\,{}_k\mathrm{C}_3$ と変形すると,$\displaystyle\sum_{k=3}^{n}{}_k\mathrm{C}_3={}_{n+1}\mathrm{C}_4$ で一気に閉じる。$txt$,
$txt$$E(X)=\dfrac{3(n+1)}{4}$$txt$,
$txt$取り出し方は全部で ${}_n\mathrm{C}_3$ 通りで,同時に取り出すからどれも同様に確からしい。
$X=k$($3\leqq k\leqq n$)となるのは,$k$ の札を取り,残り $2$ 枚を $1,2,\dots,k-1$ の $k-1$ 枚から取るときだから
$$P(X=k)=\frac{{}_{k-1}\mathrm{C}_2}{{}_n\mathrm{C}_3}$$
よって
$$E(X)=\frac{1}{{}_n\mathrm{C}_3}\sum_{k=3}^{n}k\cdot{}_{k-1}\mathrm{C}_2$$
ここで
$$k\cdot{}_{k-1}\mathrm{C}_2=k\cdot\frac{(k-1)(k-2)}{2}=3\cdot\frac{k(k-1)(k-2)}{6}=3\,{}_k\mathrm{C}_3$$
であり,パスカルの法則 ${}_k\mathrm{C}_3={}_{k+1}\mathrm{C}_4-{}_k\mathrm{C}_4$ による望遠鏡和(ホッケースティック恒等式)から
$$\sum_{k=3}^{n}{}_k\mathrm{C}_3={}_{n+1}\mathrm{C}_4$$
よって
$$E(X)=\frac{3\,{}_{n+1}\mathrm{C}_4}{{}_n\mathrm{C}_3}=3\cdot\frac{(n+1)n(n-1)(n-2)}{24}\cdot\frac{6}{n(n-1)(n-2)}=\frac{3(n+1)}{4}$$

検算: $n=3$ では $X=3$ で確定,$E=3=\dfrac{3\cdot4}{4}$ ✓。$n=4$ では $P(X=3)=\dfrac14,\ P(X=4)=\dfrac34$,$E=\dfrac{15}{4}=\dfrac{3\cdot5}{4}$ ✓。$txt$,
$txt$「最大値の分布」は「最大値を固定して残りを下から選ぶ」が定石: $X=k$ ⟺ $k$ を含み残り $2$ 枚は $k$ 未満。$P(X\leqq k)={}_k\mathrm{C}_3/{}_n\mathrm{C}_3$ の差分から求めてもよい。

和の計算は「組合せの和は組合せのまま閉じる」が鉄則。$k\cdot{}_{k-1}\mathrm{C}_2=3\,{}_k\mathrm{C}_3$(吸収公式)で次数を上げ,ホッケースティック恒等式で一発 — $\sum k^3$ などの多項式展開に持ち込むと計算量が数倍になる。

答え $\dfrac{3(n+1)}{4}$ の「$n+1$ の $\frac34$」という形は,下の別解(すき間の対等性)から先に予想できる — 答えの形に対称性の説明がつくかを確認する癖をつけたい。$txt$,
$txt$・対等性による別解: $3$ 枚を取ると $1$〜$n$ は「$X$ より上」「選んだ札の間 $\times2$」「最小より下」の $4$ つのすき間に分かれる。取らなかった $n-3$ 枚は対称性からどのすき間にも同等に入り,各すき間の期待枚数は $\dfrac{n-3}{4}$。$X=n-(上のすき間の枚数)$ より
$$E(X)=n-\frac{n-3}{4}=\frac{3(n+1)}{4}$$
計算がほぼゼロで済む(検算・時短に有効)。
・裾和公式 $E(X)=\sum_{k=1}^{n}P(X\geqq k)$ を使う方法でも同じ結果に至る。$txt$,
$txt$・$P(X=k)$ の分子を ${}_k\mathrm{C}_2$ とする($k$ 自身を含めるか含めないかの混同)。
・和の範囲($k=3$ から)の設定ミス。${}_{k-1}\mathrm{C}_2$ は $k<3$ で $0$ になることに注意。
・$\sum{}_k\mathrm{C}_3={}_{n+1}\mathrm{C}_4$ を暗記のまま使い,パスカルの法則による一行の根拠を添えない。
・最後の約分($n(n-1)(n-2)$ が消える)での計算ミス — $n=3,4$ の検算で防げる。$txt$,
$txt$・「同時に取り出す=組合せで等確率(同様に確からしい)」の一言。
・$P(X=k)$ の導出(最大が $k$ ⟺ $k$ を含み残りは $k-1$ 枚から $2$ 枚)。
・望遠鏡和(パスカルの法則)の式変形の明示。
・答えは $n$ の式 — $n=3$ などでの検算は答案には必須でないが事故防止に有効。$txt$,
$txt$・最大・最小の分布は「$P(X\leqq k)$ の差」または「最大値を固定して数える」。
・組合せの和は吸収公式 $k\cdot{}_{k-1}\mathrm{C}_{r-1}=r\,{}_k\mathrm{C}_r$ とホッケースティック恒等式で「組合せのまま」処理する。
・「すき間の対等性」による期待値の別解は計算ゼロの強力な検算手段。$txt$
from problems p
where p.university = '京都大学' and p.year = 2026 and p.exam_type = '前期理系' and p.question_no = 6
on conflict (problem_id) do update set
  difficulty      = excluded.difficulty,
  target_time_min = excluded.target_time_min,
  prerequisites   = excluded.prerequisites,
  approach        = excluded.approach,
  answer          = excluded.answer,
  full_solution   = excluded.full_solution,
  insight         = excluded.insight,
  alternatives    = excluded.alternatives,
  common_mistakes = excluded.common_mistakes,
  grading_notes   = excluded.grading_notes,
  takeaways       = excluded.takeaways;
