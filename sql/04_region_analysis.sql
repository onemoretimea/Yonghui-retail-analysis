-- ============================================================
-- Yonghui-retail-analysis | 04_region_analysis.sql
-- 区域营收 & 毛利聚合：高营收区域是否带来高毛利？
-- 注意：区域面板中 is_estimated=1 的行为按年报披露结构回溯的估算值
--       （2024 年为年报披露口径），仅用于课程分析
-- ============================================================
USE yonghui_retail;

-- ------------------------------------------------------------
-- 1. 区域年度聚合：营收、占比、毛利率
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_region_summary;
CREATE TABLE ads_region_summary AS
SELECT
    r.year,
    r.region,
    SUM(r.revenue_yi)                                        AS revenue_yi,
    ROUND(SUM(r.revenue_yi) / SUM(SUM(r.revenue_yi)) OVER (PARTITION BY r.year) * 100, 2) AS revenue_share_pct,
    ROUND(AVG(r.gross_margin_pct), 2)                        AS gross_margin_pct,
    MAX(r.is_estimated)                                      AS is_estimated
FROM stg_yonghui_region r
GROUP BY r.year, r.region;

-- ------------------------------------------------------------
-- 2. 核心检验：营收规模与毛利率是否正相关？
--    用窗口函数给区域内排秩，对比头部区域与尾部区域的毛利率
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT
        year, region, revenue_yi, revenue_share_pct, gross_margin_pct,
        RANK() OVER (PARTITION BY year ORDER BY revenue_yi DESC) AS rev_rank
    FROM ads_region_summary
    WHERE year = 2024
)
SELECT
    region,
    ROUND(revenue_yi, 1)     AS revenue_yi,
    revenue_share_pct,
    gross_margin_pct,
    rev_rank,
    CASE WHEN rev_rank <= 2 THEN '头部营收区域' ELSE '其他区域' END AS tier
FROM ranked
ORDER BY rev_rank;

-- 预期结论：华西/西南为头部营收区域（合计约 35%），但毛利率（~15.9%）
--           并不高于华北（~18.2%）：高营收 ≠ 高毛利，规模优势未兑现

-- ------------------------------------------------------------
-- 3. 集中度指标：Top2 区域营收占比的年度演变（窗口函数趋势）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_region_concentration;
CREATE TABLE ads_region_concentration AS
WITH yearly AS (
    SELECT
        year,
        SUM(revenue_yi) AS total_rev_yi
    FROM ads_region_summary
    GROUP BY year
),
top2 AS (
    SELECT year, SUM(revenue_yi) AS top2_rev_yi
    FROM (
        SELECT year, revenue_yi,
               ROW_NUMBER() OVER (PARTITION BY year ORDER BY revenue_yi DESC) AS rn
        FROM ads_region_summary
    ) t
    WHERE rn <= 2
    GROUP BY year
)
SELECT
    y.year,
    ROUND(y.total_rev_yi, 1)                                   AS total_rev_yi,
    ROUND(t.top2_rev_yi, 1)                                    AS top2_rev_yi,
    ROUND(t.top2_rev_yi / y.total_rev_yi * 100, 1)             AS top2_share_pct,
    ROUND(t.top2_rev_yi / y.total_rev_yi * 100
          - LAG(t.top2_rev_yi / y.total_rev_yi * 100) OVER (ORDER BY y.year), 1) AS share_change_pp
FROM yearly y JOIN top2 t USING (year);

SELECT * FROM ads_region_concentration ORDER BY year;

-- ------------------------------------------------------------
-- 4. 区域毛利率离散度：跨区域扩张是否摊薄整体盈利
-- ------------------------------------------------------------
SELECT
    year,
    ROUND(AVG(gross_margin_pct), 2)                     AS avg_gm_pct,
    ROUND(MAX(gross_margin_pct) - MIN(gross_margin_pct), 2) AS gm_spread_pp,
    ROUND(STDDEV_POP(gross_margin_pct), 2)              AS gm_stddev
FROM ads_region_summary
GROUP BY year
ORDER BY year;

-- 业务含义：区域毛利率离散度有限（各区域毛利率都在 15%-20% 区间），
--           说明跨区域扩张既没有形成区域规模溢价，也没有明显的高毛利根据地；
--           收入向华西/西南集中，但这两大区域毛利率反而偏低 → 结构性稀释
