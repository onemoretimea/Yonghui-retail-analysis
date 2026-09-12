-- ============================================================
-- Yonghui-retail-analysis | 00_schema_and_load.sql
-- 建库、建表、导入 CSV 数据（MySQL 8.0+）
-- 数据源：永辉超市(601933) 2019-2024 年报、2025 三季报、
--         胖东来公开披露、CSMAR 日/月个股交易数据（已清洗）
-- 使用方法：
--   1) 先用本文件建库建表
--   2) 修改下方 LOAD DATA 路径为你的 data/ 目录绝对路径
--   3) 逐条执行 LOAD DATA（Windows 路径用 / 分隔）
-- ============================================================

CREATE DATABASE IF NOT EXISTS yonghui_retail
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE yonghui_retail;

-- ---------- 1. 年度财务主表（元，来自年报） ----------
DROP TABLE IF EXISTS stg_yonghui_annual;
CREATE TABLE stg_yonghui_annual (
    year           INT          NOT NULL PRIMARY KEY,   -- 年度
    revenue        DECIMAL(20,2) NOT NULL,              -- 营业总收入（元）
    cogs           DECIMAL(20,2) NOT NULL,              -- 营业成本（元）
    selling_exp    DECIMAL(20,2) NOT NULL,              -- 销售费用（元）
    admin_exp      DECIMAL(20,2) NOT NULL,              -- 管理费用（元）
    finance_exp    DECIMAL(20,2) NOT NULL,              -- 财务费用（元）
    net_profit     DECIMAL(20,2) NOT NULL,              -- 归母净利润（元）
    inventory      DECIMAL(20,2) NOT NULL,              -- 年末存货（元）
    stores_end     INT          NOT NULL                -- 年末门店数（家）
);

-- ---------- 2. 门店数量表 ----------
DROP TABLE IF EXISTS stg_yonghui_stores;
CREATE TABLE stg_yonghui_stores (
    year        INT NOT NULL PRIMARY KEY,
    stores_end  INT NOT NULL,          -- 年末门店数
    net_change  INT NULL               -- 净增减 = stores_end - 上年 stores_end（导入后由 SQL 计算）
);

-- ---------- 3. 区域营收/毛利面板（亿元；2024 为年报披露口径，早年为按年报结构回溯的估算值，见 is_estimated） ----------
DROP TABLE IF EXISTS stg_yonghui_region;
CREATE TABLE stg_yonghui_region (
    year               INT    NOT NULL,
    region             VARCHAR(16) NOT NULL,   -- 华西/西南/华东/华北/华中/华南
    revenue_yi         DECIMAL(12,2) NOT NULL, -- 区域营收（亿元）
    revenue_share_pct  DECIMAL(6,2)  NOT NULL, -- 营收占比 %
    gross_margin_pct   DECIMAL(6,2)  NOT NULL, -- 区域毛利率 %
    is_estimated       TINYINT      NOT NULL,  -- 1=估算值 0=年报披露值
    PRIMARY KEY (year, region)
);

-- ---------- 4. 季度经营表（亿元） ----------
DROP TABLE IF EXISTS stg_yonghui_quarterly;
CREATE TABLE stg_yonghui_quarterly (
    quarter        VARCHAR(8)  NOT NULL PRIMARY KEY,  -- 2024Q1 ... 2025Q3
    revenue_yi     DECIMAL(12,2) NOT NULL,            -- 季度营收（亿元）
    net_profit_yi  DECIMAL(12,2) NOT NULL,            -- 季度归母净利润（亿元）
    yoy_rev_pct    DECIMAL(8,2)  NULL,                -- 营收同比 %
    net_margin_pct DECIMAL(8,2)  NULL                 -- 净利率 %
);

-- ---------- 5. 胖东来对标表 ----------
DROP TABLE IF EXISTS stg_pangdonglai;
CREATE TABLE stg_pangdonglai (
    year             INT NOT NULL PRIMARY KEY,
    sales_yi         DECIMAL(12,2) NOT NULL,   -- 年销售额（亿元，公开披露）
    net_profit_yi    DECIMAL(12,2) NOT NULL,   -- 净利润（亿元）
    stores           INT          NOT NULL,   -- 门店数（许昌11+新乡3）
    region_focus     VARCHAR(64)  NOT NULL,
    net_margin_pct   DECIMAL(8,2)  NULL,
    rev_per_store_yi DECIMAL(12,3) NULL
);

-- ---------- 6. 股价数据（CSMAR 清洗后） ----------
DROP TABLE IF EXISTS stg_stock_daily;
CREATE TABLE stg_stock_daily (
    trddt              DATE NOT NULL PRIMARY KEY,   -- 交易日
    opnprc             DECIMAL(12,4),               -- 开盘价
    hiprc              DECIMAL(12,4),               -- 最高价
    loprc              DECIMAL(12,4),               -- 最低价
    clsprc             DECIMAL(12,4),               -- 收盘价
    ret_pct            DECIMAL(12,4),               -- 日收益率 %
    cum_ret_pct        DECIMAL(12,4),               -- 区间累计收益率 %
    dnshrtrd           BIGINT,                      -- 成交量（股）
    turnover_value_yi  DECIMAL(14,2)                -- 成交额（亿元）
);

DROP TABLE IF EXISTS stg_stock_monthly;
CREATE TABLE stg_stock_monthly (
    trdmnt        VARCHAR(8) NOT NULL PRIMARY KEY,  -- 交易月份 2019-01 ... 2025-10
    mopnprc       DECIMAL(12,4),
    mclsprc       DECIMAL(12,4),                    -- 月收盘价
    ret_pct       DECIMAL(12,4),                    -- 月收益率 %
    cum_ret_pct   DECIMAL(12,4),                    -- 累计收益率 %
    mnshrtrd      BIGINT,                           -- 月成交量（股）
    mvaltrd_yi    DECIMAL(14,2)                     -- 月成交额（亿元）
);

-- ---------- 7. 关键事件表（用于市场反应分析） ----------
DROP TABLE IF EXISTS stg_events;
CREATE TABLE stg_events (
    event_date  DATE NOT NULL PRIMARY KEY,
    event       VARCHAR(128) NOT NULL
);

-- ============================================================
-- LOAD DATA（把路径替换成你的 data/ 目录，Windows 用正斜杠）
-- ============================================================
/*
LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yonghui_annual.csv'
INTO TABLE stg_yonghui_annual
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yonghui_stores.csv'
INTO TABLE stg_yonghui_stores
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES (year, stores_end, @net_change);

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yonghui_region.csv'
INTO TABLE stg_yonghui_region
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yonghui_quarterly.csv'
INTO TABLE stg_yonghui_quarterly
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES (quarter, revenue_yi, net_profit_yi, @yoy, net_margin_pct);

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/pangdonglai.csv'
INTO TABLE stg_pangdonglai
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yh_stock_daily.csv'
INTO TABLE stg_stock_daily
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yh_stock_monthly.csv'
INTO TABLE stg_stock_monthly
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/.../Yonghui-retail-analysis/data/yh_events.csv'
INTO TABLE stg_events
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' IGNORE 1 LINES;
*/
-- 提示：若 MySQL 禁用了 local_infile，先执行 SET GLOBAL local_infile = 1;
--       或改用 MySQL Workbench / navicat 的导入向导（UTF-8，跳过首行表头）。
