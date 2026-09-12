-- ============================================================
-- Yonghui-retail-analysis | 01_data_clean.sql
-- 基础数据清洗 + 衍生经营指标（毛利率 / 三费费用率 / 库存周转天数）
-- 对应看板：盈利结构（剪刀差）、库存周转
-- ============================================================
USE yonghui_retail;

-- ------------------------------------------------------------
-- 1. 年度财务清洗与衍生指标（含窗口函数 LAG 取上年存货，计算平均存货）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dws_yonghui_kpi;
CREATE TABLE dws_yonghui_kpi AS
WITH base AS (
    SELECT
        a.year,
        a.revenue,
        a.cogs,
        a.selling_exp,
        a.admin_exp,
        a.finance_exp,
        a.net_profit,
        a.inventory,
        a.stores_end,
        -- 平均存货 = (上年存货 + 本年存货) / 2，用窗口函数取上年
        (a.inventory + LAG(a.inventory) OVER (ORDER BY a.year)) / 2 AS avg_inventory,
        LAG(a.revenue)    OVER (ORDER BY a.year) AS revenue_prev,
        LAG(a.net_profit) OVER (ORDER BY a.year) AS net_profit_prev
    FROM stg_yonghui_annual a
)
SELECT
    year,
    revenue,
    cogs,
    -- 毛利与毛利率
    revenue - cogs                                AS gross_profit,
    ROUND((revenue - cogs) / revenue * 100, 2)    AS gross_margin_pct,
    -- 三项费用合计与费用率（体现固定成本刚性）
    selling_exp + admin_exp + finance_exp                          AS total_op_exp,
    ROUND((selling_exp + admin_exp + finance_exp) / revenue * 100, 2) AS op_exp_ratio_pct,
    ROUND(selling_exp  / revenue * 100, 2)        AS selling_exp_ratio_pct,
    ROUND(admin_exp    / revenue * 100, 2)        AS admin_exp_ratio_pct,
    ROUND(finance_exp  / revenue * 100, 2)        AS finance_exp_ratio_pct,
    -- 净利润与净利率
    net_profit,
    ROUND(net_profit / revenue * 100, 2)          AS net_margin_pct,
    -- 营收与净利同比
    ROUND((revenue    / revenue_prev    - 1) * 100, 2) AS revenue_yoy_pct,
    ROUND(net_profit - net_profit_prev, 2)            AS net_profit_change,
    -- 库存周转天数 = 365 * 平均存货 / 营业成本（生鲜模式的资金占用与损耗压力）
    ROUND(365 * avg_inventory / NULLIF(cogs, 0), 1) AS inventory_turnover_days,
    stores_end,
    -- 营收/净利 换算为亿元，方便看板展示
    ROUND(revenue    / 1e8, 2) AS revenue_yi,
    ROUND(net_profit / 1e8, 2) AS net_profit_yi
FROM base;

-- ------------------------------------------------------------
-- 2. 数据质量校验：毛利率区间、费用率单调性、周转天数合理性
-- ------------------------------------------------------------
SELECT
    year, gross_margin_pct, op_exp_ratio_pct, net_margin_pct,
    inventory_turnover_days
FROM dws_yonghui_kpi
ORDER BY year;

-- ------------------------------------------------------------
-- 3. 季度数据清洗：营收同比、净利率、亏损季度标记
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dws_quarterly;
CREATE TABLE dws_quarterly AS
SELECT
    quarter,
    revenue_yi,
    net_profit_yi,
    yoy_rev_pct,
    net_margin_pct,
    CASE WHEN net_profit_yi < 0 THEN 1 ELSE 0 END AS is_loss_quarter
FROM stg_yonghui_quarterly;

-- ------------------------------------------------------------
-- 4. “盈利剪刀差”数据集：营收指数 vs 净利率（以2020为基期=100）
--    用于 Tableau 双轴折线：收入收缩放大亏损（负经营杠杆）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_scissors;
CREATE TABLE ads_scissors AS
SELECT
    k.year,
    k.revenue_yi,
    k.net_profit_yi,
    k.gross_margin_pct,
    k.net_margin_pct,
    k.op_exp_ratio_pct,
    -- 剪刀差 = 毛利率 - 净利率（被费用吞噬的利润空间）
    ROUND(k.gross_margin_pct - k.net_margin_pct, 2) AS scissors_gap_pct,
    ROUND(100 * k.revenue / (SELECT revenue FROM stg_yonghui_annual WHERE year = 2020), 1) AS revenue_index
FROM dws_yonghui_kpi k
ORDER BY k.year;

SELECT * FROM ads_scissors;
