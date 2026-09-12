-- ============================================================
-- Yonghui-retail-analysis | 02_same_store.sql
-- 核心：窗口函数计算同店效应 & 门店规模效应（营收变化拆解）
--
-- 方法论（与课程报告一致）：
--   单店产出(上年)  = 上年营收 / 上年年末门店数
--   假定营收(本年)  = 单店产出(上年) * 本年年末门店数
--                     —— 即“如果只变门店数、单店效率不变”的虚拟营收
--   门店数效应      = 假定营收 - 上年营收     （纯规模扩张/收缩的贡献）
--   同店效应        = 本年营收 - 假定营收     （存量门店经营质量的变化）
--   恒等式：ΔRev = 门店数效应 + 同店效应
-- ============================================================
USE yonghui_retail;

-- ------------------------------------------------------------
-- 1. 用窗口函数 LAG 生成拆解明细表
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_revenue_decomposition;
CREATE TABLE ads_revenue_decomposition AS
WITH YoY AS (
    SELECT
        a.year,
        a.revenue,
        a.stores_end,
        LAG(a.revenue)   OVER (ORDER BY a.year) AS revenue_prev,
        LAG(a.stores_end) OVER (ORDER BY a.year) AS stores_prev
    FROM stg_yonghui_annual a
    WHERE a.year BETWEEN 2019 AND 2024
),
calc AS (
    SELECT
        *,
        revenue_prev / NULLIF(stores_prev, 0) AS rev_per_store_prev,      -- 上年单店产出
        (revenue_prev / NULLIF(stores_prev, 0)) * stores_end AS assumed_rev  -- 假定营收
    FROM YoY
    WHERE revenue_prev IS NOT NULL
)
SELECT
    year,
    CONCAT(year - 1, ' vs ', year - 2)                                   AS compare_years,
    stores_prev,
    stores_end,
    stores_end - stores_prev                                             AS store_net_change,
    ROUND(revenue_prev / 1e8, 2)                                         AS revenue_prev_yi,
    ROUND(revenue / 1e8, 2)                                              AS revenue_yi,
    ROUND((revenue - revenue_prev) / 1e8, 2)                             AS revenue_change_yi,
    -- 两大效应（亿元）
    ROUND((assumed_rev - revenue_prev) / 1e8, 2)                         AS store_count_effect_yi,  -- 门店数效应
    ROUND((revenue - assumed_rev) / 1e8, 2)                              AS same_store_effect_yi,   -- 同店效应
    -- 假定营收与单店产出（中间过程，用于 Tableau 瀑布图/表格）
    ROUND(assumed_rev / 1e8, 2)                                          AS assumed_revenue_yi,
    ROUND(revenue_prev / stores_prev / 1e8, 4)                           AS rev_per_store_prev_yi,
    -- 结构占比：同店效应贡献率（判断增长质量）
    ROUND((revenue - assumed_rev) / NULLIF(revenue - revenue_prev, 0) * 100, 1) AS same_store_contrib_pct
FROM calc;

SELECT * FROM ads_revenue_decomposition ORDER BY year;

-- ------------------------------------------------------------
-- 2. 结论验证：两大效应之和 = 营收变化（恒等式自检）
-- ------------------------------------------------------------
SELECT
    year,
    revenue_change_yi,
    store_count_effect_yi + same_store_effect_yi AS effect_sum_yi,
    ROUND(store_count_effect_yi + same_store_effect_yi - revenue_change_yi, 2) AS check_diff
FROM ads_revenue_decomposition;

-- ------------------------------------------------------------
-- 3. 阶段判定：侵蚀期（2020-2023）vs 战略收缩期（2024）
-- ------------------------------------------------------------
SELECT
    CASE WHEN year <= 2023 THEN 'Phase1 侵蚀期(2020-2023)' ELSE 'Phase2 战略收缩期(2024)' END AS phase,
    year,
    same_store_effect_yi,
    store_count_effect_yi,
    CASE
        WHEN same_store_effect_yi > 0 AND store_count_effect_yi > 0 THEN '双轮增长'
        WHEN same_store_effect_yi < 0 AND store_count_effect_yi > 0 THEN '扩张掩盖同店恶化'
        WHEN same_store_effect_yi < 0 AND store_count_effect_yi < 0 THEN '双杀下滑'
        WHEN same_store_effect_yi > 0 AND store_count_effect_yi < 0 THEN '关店提效（质量优先）'
    END AS diagnosis
FROM ads_revenue_decomposition
ORDER BY year;

-- 预期结论：
--   2020  +9.88 亿门店效应 / -1.55 亿同店  → 新店拉动掩盖存量下滑
--   2021  +3.62 / -5.76                    → 同店恶化成为主要拖累
--   2022  -2.07 / +1.10                    → 首次关店但同店微修复
--   2023  -2.88 / -8.57                    → 同店效应主导的深度下滑
--   2024  -17.70 / +6.63                   → 大规模关店（-225家），留存门店单店产出大幅修复
