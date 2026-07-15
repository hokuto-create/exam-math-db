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
  (university, year, exam_type, question_no, unit_tags, method_tags, source_url, problem_text, admin_note)
values
  -- ---- 京都大学 2026 前期理系(数学・理系)----
  ('京都大学', 2026, '前期理系', 1, '{21,22}', '{16,29}',   'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'$a$ は $1$ より大きい実数とし,$k$ は実数とする。$0<x<1$ において定義された関数を
$$f(x)=\frac{1}{x^2\left(\log\dfrac{a}{x}\right)^2}$$
とおく。$y=f(x)$ と $y=k$ のグラフの共有点がちょうど $2$ 個存在するような実数の組 $(a,\ k)$ の集合を,座標平面上に図示せよ。ただし $\log x$ は自然対数とする。また,$\displaystyle\lim_{x\to+0}x\log x=0$ が成り立つことを証明なしに用いてよい。

出典:京都大学 2026年度 入学試験問題 数学(理系)第1問(原本より数式の組版を変更して転載)',
   'f(x)=1/(x²(log(a/x))²) と y=k の共有点がちょうど2個となる (a,k) の集合の図示'),
  ('京都大学', 2026, '前期理系', 2, '{18}',    '{22,26}',   'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'$r$ は正の実数とする。$1$ 辺の長さが $1$ の正四面体 $\mathrm{OABC}$ において,辺 $\mathrm{OA}$ 上に点 $\mathrm{P}$ をとる。点 $\mathrm{P}$ が辺 $\mathrm{OA}$ 上のどこにあっても,点 $\mathrm{P}$ を中心とする半径 $r$ の球面が,辺 $\mathrm{BC}$ と共有点をもたないような $r$ の範囲を求めよ。ただし,点 $\mathrm{O},\ \mathrm{A}$ は辺 $\mathrm{OA}$ に含まれ,点 $\mathrm{B},\ \mathrm{C}$ は辺 $\mathrm{BC}$ に含まれるとする。

出典:京都大学 2026年度 入学試験問題 数学(理系)第2問(原本より数式の組版を変更して転載)',
   '正四面体OABCの辺OA上の任意の点Pを中心とする半径rの球面が辺BCと交わらないrの範囲'),
  ('京都大学', 2026, '前期理系', 3, '{7}',     '{6,11}',    'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'$n$ は正の整数とする。整数係数の多項式
$$(x+1)^{2^{n+1}}-(x^2+1)^{2^n}$$
のすべての係数が $2^m$ で割り切れるような正の整数 $m$ のうち,最大のものは $n+1$ であることを示せ。

出典:京都大学 2026年度 入学試験問題 数学(理系)第3問(原本より数式の組版を変更して転載)',
   '(x+1)^{2^{n+1}}−(x²+1)^{2^n} の全係数を割り切る 2^m の最大の m が n+1 であることの証明'),
  ('京都大学', 2026, '前期理系', 4, '{3,11}',  '{3,25,29}', 'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'平面において,次の条件 $(*)$ を満たす正三角形の $1$ 辺の長さの最小値を求めよ。

$(*)$ $1$ 辺の長さが $1$ の正方形であって,$4$ つの頂点がすべてその正三角形の内部または辺上にあるようなものが存在する。

出典:京都大学 2026年度 入学試験問題 数学(理系)第4問(原本より数式の組版を変更して転載)',
   '1辺1の正方形を内部または辺上に含む正三角形の1辺の長さの最小値'),
  ('京都大学', 2026, '前期理系', 5, '{23,24}', '{3}',       'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'$a$ は $0<a<\pi$ を満たす実数とする。$2$ つの関数 $y=\sin(x+a)$ と $y=\sin(x-a)$ のグラフの,$-\dfrac{\pi}{2}\leqq x\leqq\dfrac{\pi}{2}$ の部分が囲む領域を $D_a$ とする。$x$ 軸のまわりに $D_a$ を $1$ 回転してできる立体の体積を求めよ。

出典:京都大学 2026年度 入学試験問題 数学(理系)第5問(原本より数式の組版を変更して転載)',
   'y=sin(x+a) と y=sin(x−a) が囲む領域 D_a の x軸回転体の体積'),
  ('京都大学', 2026, '前期理系', 6, '{5,4}',   '{35}',      'https://www.kyoto-u.ac.jp/sites/default/files/inline-files/admissionsundergradpast_eqR08_eqdocumentsR08_3M04-67eab9889126ec2b1c07384f2e5e4fff.pdf',
'$n$ は $3$ 以上の整数とする。$1$ から $n$ までの番号が書かれた $n$ 枚の札が袋に入っている。ただし,同じ番号が書かれた札はないとする。この袋から $3$ 枚の札を同時に取り出し,一番大きな番号を $X$ とする。$X$ の期待値を求めよ。

出典:京都大学 2026年度 入学試験問題 数学(理系)第6問(原本より数式の組版を変更して転載)',
   'n枚から3枚同時に取り出したときの最大番号 X の期待値')
on conflict (university, year, exam_type, question_no)
do update set
  unit_tags    = excluded.unit_tags,
  method_tags  = excluded.method_tags,
  source_url   = excluded.source_url,
  problem_text = excluded.problem_text,
  admin_note   = excluded.admin_note;
