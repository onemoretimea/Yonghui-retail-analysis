-- ============================================================
-- Yonghui-retail-analysis | 03_store_kpi.sql
-- 单店营收 / 单店净利 / 库存周转 / 门店规模效应
-- 对应看板：单店效率与运营短板
-- ============================================================
USE yonghui_retail;

-- ------------------------------------------------------------
-- 1. 单店经营指标（用窗口函数 LAG 计算同比与变化）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_store_kpi;
CREATE TABLE ads_store_kpi AS
WITH s AS (
    SELECT
        k.year,
        k.revenue,
        k.net_profit,
        k.stores_end,
        k.inventory_turnover_days,
        k.revenue_yi,
        k.net_profit_yi,
        LAG(k.revenue)    OVER (ORDER BY k.year) AS revenue_prev,
        LAG(k.stores_end) OVER (ORDER BY k.year) AS stores_prev,
        LAG(k.revenue / k.stores_end) OVER (ORDER BY k.year) AS rev_per_store_prev
    FROM dws_yonghui_kpi k
)
SELECT
    year,
    stores_end,
    -- 单店营收（万元/店/年）
    ROUND(revenue / stores_end / 1e4, 2)              AS rev_per_store_wan,
    -- 单店营收同比 %
    ROUND((revenue / stores_end) / NULLIF(rev_per_store_prev, 0) * 100 - 100, 2) AS rev_per_store_yoy_pct,
    -- 单店归母净利（万元/店/年）：2020 约 +176 万 → 2021 起转负
    ROUND(net_profit / stores_end / 1e4, 2)           AS profit_per_store_wan,
    -- 门店净增减
    stores_end - stores_prev                          AS store_net_change,
    -- 库存周转天数（生鲜模式：>50 天意味着高损耗与资金占用）
    inventory_turnover_days,
    -- 存货压降速度 vs 营收收缩速度：周转天数能否跑赢收入下滑
    ROUND(inventory_turnover_days - LAG(inventory_turnover_days) OVER (ORDER BY year), 1) AS turnover_days_change
FROM s
WHERE revenue_prev IS NOT NULL;

SELECT * FROM ads_store_kpi ORDER BY year;

-- ------------------------------------------------------------
-- 2. 库存效率视角：存货压降 vs 营收收缩
--    生鲜超市理想周转 < 40 天；永辉长期 > 50 天且 2023 见顶
-- ------------------------------------------------------------
SELECT
    k.year,
    ROUND(k.revenue_yi, 1)          AS revenue_yi,
    ROUND(k.revenue_yoy_pct, 2)     AS revenue_yoy_pct,
    ROUND(a.inventory / 1e8, 1)     AS inventory_yi,
    k.inventory_turnover_days,
    CASE
        WHEN k.inventory_turnover_days >= 55 THEN '压力峰值'
        WHEN k.inventory_turnover_days >= 50 THEN '高位运行'
        ELSE '可控区间'
    END AS inventory_status
FROM dws_yonghui_kpi k
JOIN stg_yonghui_annual a USING (year)
ORDER BY k.year;

-- ------------------------------------------------------------
-- 3. 与胖东来的单店质量对标（规模 vs 质量的分野）
--    永辉单店营收约 0.87 亿元/店；胖东来约 8.6 亿元/店
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_vs_pangdonglai;
CREATE TABLE ads_vs_pangdonglai AS
SELECT
    k.year,
    '永辉超市'                                 AS company,
    ROUND(k.revenue / k.stores_end / 1e8, 3)   AS rev_per_store_yi,
    ROUND(k.net_profit / k.revenue * 100, 2)   AS net_margin_pct,
    k.stores_end                               AS stores,
    '全国29省'                                 AS footprint
FROM dws_yonghui_kpi k
WHERE k.year BETWEEN 2020 AND 2024
UNION ALL
SELECT
    p.year,
    '胖东来',
    ROUND(p.sales_yi / p.stores, 2),
    p.net_margin_pct,
    p.stores,
    '河南许昌+新乡（区域深耕）'
FROM stg_pangdonglai p
ORDER BY year, company;

SELECT * FROM ads_vs_pangdonglai;

-- 预期结论：
--   单店营收：永辉 93.25(百万,2020) → 87.19(2024) 持续走低；胖东来 ~5.6 → 8.6 亿元/店
--   规模没有带来单店质量：门店数是胖东来的 ~70 倍，单店产出只有其 ~1/10
