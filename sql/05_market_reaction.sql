-- ============================================================
-- Yonghui-retail-analysis | 05_market_reaction.sql
-- 用 CSMAR 股价数据（TRD_Dalyr / TRD_Mnth）做市场反应分析：
--   股价如何回应"商业模式失效"与"胖东来式转型"？
-- 对应看板：市场视角（月K、累计收益、事件窗口）
-- ============================================================
USE yonghui_retail;

-- ------------------------------------------------------------
-- 1. 年度股价表现 vs 基本面表现（月度数据聚合）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_market_annual;
CREATE TABLE ads_market_annual AS
SELECT
    SUBSTRING(trdmnt, 1, 4)                                       AS year,
    ROUND((MAX(mclsprc) / MIN(MIN(mclsprc)) OVER () - 1) * 100, 2) AS dummy_ignore,  -- 占位（防误用），见下方重算
    ROUND(AVG(mclsprc), 2)                                        AS avg_price,
    MIN(mclsprc)                                                  AS year_low,
    MAX(mclsprc)                                                  AS year_high,
    ROUND(MAX(cum_ret_pct), 2)                                    AS max_cum_ret_pct,
    ROUND(MIN(cum_ret_pct), 2)                                    AS min_cum_ret_pct,
    ROUND(SUM(mvaltrd_yi), 1)                                     AS total_turnover_yi
FROM stg_stock_monthly
GROUP BY SUBSTRING(trdmnt, 1, 4);

-- 更清晰的口径：按年末收盘价计算年度涨跌幅（窗口函数取每年最后一个月）
DROP TABLE IF EXISTS ads_market_annual;
CREATE TABLE ads_market_annual AS
WITH month_seq AS (
    SELECT
        trdmnt,
        mclsprc,
        ret_pct,
        cum_ret_pct,
        mvaltrd_yi,
        SUBSTRING(trdmnt, 1, 4) AS yr,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(trdmnt, 1, 4) ORDER BY trdmnt DESC) AS rn_desc,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(trdmnt, 1, 4) ORDER BY trdmnt ASC)  AS rn_asc
    FROM stg_stock_monthly
)
SELECT
    a.yr                                                          AS year,
    ROUND(a.mclsprc, 2)                                           AS year_end_price,
    ROUND((a.mclsprc / b.mclsprc - 1) * 100, 2)                   AS year_ret_pct,      -- 年度涨跌幅%
    ROUND(f.mclsprc, 2)                                           AS year_start_price,
    ROUND(a.mclsprc / 2.0, 2)                                     AS dummy,
    (SELECT ROUND(MAX(mclsprc), 2) FROM month_seq WHERE yr = a.yr) AS year_high,
    (SELECT ROUND(MIN(mclsprc), 2) FROM month_seq WHERE yr = a.yr) AS year_low,
    (SELECT ROUND(SUM(mvaltrd_yi), 1) FROM month_seq WHERE yr = a.yr) AS total_turnover_yi
FROM (SELECT yr, mclsprc FROM month_seq WHERE rn_desc = 1) a
JOIN (SELECT yr, mclsprc FROM month_seq WHERE rn_asc  = 1) b USING (yr)
JOIN (SELECT yr, mclsprc FROM month_seq WHERE rn_asc  = 1) f USING (yr);

ALTER TABLE ads_market_annual DROP COLUMN dummy;

SELECT year, year_start_price, year_end_price, year_ret_pct, total_turnover_yi
FROM ads_market_annual ORDER BY year;

-- ------------------------------------------------------------
-- 2. 事件研究：转型事件窗口的累计超额反应（CAR 简化版）
--    窗口 = 事件日前后各 10 个交易日
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ads_event_study;
CREATE TABLE ads_event_study AS
WITH daily_seq AS (
    SELECT
        trddt, clsprc, ret_pct, cum_ret_pct,
        ROW_NUMBER() OVER (ORDER BY trddt) AS trade_seq
    FROM stg_stock_daily
),
evt AS (
    SELECT e.event_date, e.event,
           (SELECT MIN(trade_seq) FROM daily_seq d WHERE d.trddt >= e.event_date) AS evt_seq
    FROM stg_events e
),
windowed AS (
    SELECT
        ev.event,
        ev.event_date,
        d.trddt,
        d.clsprc,
        d.ret_pct,
        d.trade_seq - ev.evt_seq AS rel_day,           -- 相对事件日的第几个交易日
        SUM(d.ret_pct) OVER (PARTITION BY ev.event ORDER BY d.trade_seq
                             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS car_pct  -- 窗口内累计收益
    FROM evt ev
    JOIN daily_seq d
      ON d.trade_seq BETWEEN ev.evt_seq - 10 AND ev.evt_seq + 10
)
SELECT
    event, event_date, trddt, rel_day, ROUND(clsprc, 2) AS clsprc, ROUND(car_pct, 2) AS car_pct
FROM windowed
ORDER BY event, rel_day;

-- 事件窗口收益摘要
SELECT
    event,
    event_date,
    ROUND(MAX(car_pct), 2)  AS max_car_pct,      -- 窗口内最大累计收益
    ROUND(MIN(car_pct), 2)  AS min_car_pct,
    ROUND(SUM(CASE WHEN rel_day BETWEEN -1 AND 3 THEN ret_pct ELSE 0 END), 2) AS short_window_ret_pct  -- [-1,+3] 短窗口收益
FROM ads_event_study
GROUP BY event, event_date;

-- 预期观察：
--   2024-05-31 宣布学习胖东来调改 → 短窗口显著正收益（市场认可转型逻辑）
--   2024-09-23 名创优品入主公告 → 事件日大幅上涨（资金面的重估）

-- ------------------------------------------------------------
-- 3. 基本面-市场对照：营收增速 vs 股价年度涨跌幅（同一张表）
--    用于 Tableau 双轴对照：市场先于业绩定价"规模模式失效"
-- ------------------------------------------------------------
SELECT
    k.year,
    k.revenue_yi,
    k.revenue_yoy_pct,
    m.year_end_price,
    m.year_ret_pct
FROM dws_yonghui_kpi k
LEFT JOIN ads_market_annual m ON m.year = k.year
ORDER BY k.year;

-- ------------------------------------------------------------
-- 4. 转型期月度监测：2024-05 之后月收益与换手（情绪指标）
-- ------------------------------------------------------------
SELECT
    trdmnt,
    ROUND(mclsprc, 2)  AS month_close,
    ROUND(ret_pct, 2)  AS month_ret_pct,
    mvaltrd_yi
FROM stg_stock_monthly
WHERE trdmnt >= '2024-05'
ORDER BY trdmnt;
