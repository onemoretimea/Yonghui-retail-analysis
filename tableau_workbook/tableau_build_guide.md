# Yonghui-retail-analysis · Tableau 看板搭建指南

> 本指南把项目 5 个看板逐一拆解为 Tableau 的"字段、标记、图表类型"操作步骤。
> 数据连接方式：`data/` 下的 CSV 全部导入 MySQL（跑完 `sql/00-05`）后，Tableau 连接 MySQL 的 `yonghui_retail` 库；也可以直接连接 CSV 文件（字段名一致）。
> 配色约定：**红色 = 增长/上涨，绿色 = 下滑/下跌**（中国行情惯例）；对标胖东来用橙色。

---

## 0. 数据连接与数据源准备

| 数据源表 / CSV | 用途 | 关键字段 |
|---|---|---|
| `dws_yonghui_kpi` / yonghui_annual.csv | 年度财务KPI | year, revenue_yi, gross_margin_pct, op_exp_ratio_pct, net_margin_pct, inventory_turnover_days |
| `ads_revenue_decomposition`（跑 02 脚本产出） | 同店效应拆解 | year, revenue_change_yi, same_store_effect_yi, store_count_effect_yi |
| `ads_store_kpi` | 单店指标 | year, rev_per_store_wan, profit_per_store_wan, stores_end |
| `ads_region_summary` / yonghui_region.csv | 区域分析 | year, region, revenue_yi, revenue_share_pct, gross_margin_pct |
| `stg_pangdonglai` / pangdonglai.csv | 胖东来对标 | year, sales_yi, net_profit_yi, rev_per_store_yi |
| `dws_quarterly` / yonghui_quarterly.csv | 转型期季度 | quarter, revenue_yi, net_profit_yi, yoy_rev_pct |
| `stg_stock_monthly` / yh_stock_monthly.csv | 市场视角 | trdmnt, mclsprc, ret_pct, cum_ret_pct |

**日期处理**：`trdmnt`（如 `2024-05`）在 Tableau 中用「创建计算字段」转日期：
```
MAKEDATE(INT(LEFT([trdmnt],4)), INT(RIGHT([trdmnt],2)), 1)
```

**单位统一**：所有金额面板统一展示为「亿元」；单店指标用「万元/店」。

---

## 看板 1｜营收拆解：下滑来自关店还是同店？

**故事线**：营收 2020 见顶 932 亿 → 2024 年 675.7 亿；拆解出"门店数效应"和"同店效应"。

**Sheet 1.1 营收与门店双轴**
- 列：`year`（连续）；行：`revenue_yi`（条形图）
- 行（右轴）：`stores_end`（折线，右对齐标记"双轴/合并轴"）
- 标题：`总营收（亿元）与年末门店数`

**Sheet 1.2 同店效应拆解（核心图）**
- 列：`year`；行：`same_store_effect_yi`、`store_count_effect_yi`
- 用「并排条形图」（将两个字段并列放到行区，选择"并排"）
- 颜色：same_store_effect_yi > 0 → 红 / < 0 → 绿；store_count_effect_yi 用蓝灰
- 参考线：`revenue_change_yi` 合计值
- 标题：`营收变化拆解：同店效应 vs 门店数效应（亿元）`
- **看板解读区**（文本对象）：2020-2023 同店效应持续为负 → 2024 同店效应转正（+6.6亿），关店 225 家换存量质量

**Sheet 1.3 阶段诊断表**
- `year, same_store_effect_yi, store_count_effect_yi, diagnosis`（03 脚本的阶段判定字段），表格样式

---

## 看板 2｜盈利结构：毛利率稳定为何持续亏损？

**故事线**："剪刀差"：毛利率 18.7%-21.6% 稳定，净利率 2021 起深度为负。

**Sheet 2.1 剪刀差双轴折线**
- 列：`year`；行：`gross_margin_pct`（红线）
- 行（右轴）：`net_margin_pct`（绿线，负值区间）
- 辅助：`op_exp_ratio_pct`（灰虚线）
- 标题：`毛利率稳定 vs 净利率塌陷：盈利剪刀差`

**Sheet 2.2 费用吞噬毛利（2024 年瀑布图）**
- 数据：2024 毛利 138.2 亿 → 销售费用 130.6 亿 → 管理费用 17.9 亿 → 财务费用 11.4 亿 → 净亏损
- 实现：用 yonghui_annual.csv 2024 行构建 4 行数据（可用 Tableau「转置」或手工小表），
  甘特条形图法做瀑布：`RUNNING_SUM` 计算累计
- 标题：`2024：毛利被费用完全吞噬（亿元）`

**Sheet 2.3 费用率趋势**
- 列：`year`；行：`selling_exp_ratio_pct`、`admin_exp_ratio_pct`、`finance_exp_ratio_pct`
- 面积图 / 折线；标注 2021 财务费用率跳升（借款利息上升）
- 标题：`三费费用率：收入收缩下的刚性爬升`

**Sheet 2.4 转型期季度追踪**
- 列：`quarter`；行：`revenue_yi`（条形），右轴 `net_profit_yi`（红绿标记）
- 筛选器：quarter >= 2024Q1
- 标注：2025Q1-Q3 同店累计转正（文本注释）
- 标题：`转型期季度营收与净利（2024Q1-2025Q3）`

---

## 看板 3｜单店效率与运营短板

**Sheet 3.1 单店营收下滑**
- 列：`year`；行：`rev_per_store_wan`（条形，数值标注）
- 参考线：2020 值 93.25 百万（93,250 元换算口径以表内为准）
- 标题：`单店营收（万元/店）：93.25M → 87.2M（2020→2024）`

**Sheet 3.2 单店净利转负**
- 行：`profit_per_store_wan`；颜色：>0 红 / <0 绿
- 标题：`单店归母净利（万元/店）：2020 +176 → 2021 起持续为负`

**Sheet 3.3 库存周转天数**
- 行：`inventory_turnover_days`；参考线：50 天（生鲜超市警戒线）、40 天（行业优秀水平）
- 标注 2023 峰值（55 天+）
- 标题：`生鲜库存周转天数：长期 >50 天`

---

## 看板 4｜区域经营与胖东来对标

**Sheet 4.1 区域营收份额 vs 毛利率（散点/气泡）**
- 列：`revenue_share_pct`（2024）；行：`gross_margin_pct`；大小：`revenue_yi`；颜色：`region`
- 筛选：year = 2024
- **看板解读**：头部营收区域（华西+西南）毛利率并不更高 → 规模未兑现毛利
- 标题：`区域营收占比 vs 毛利率（2024）`

**Sheet 4.2 区域条形图**
- 列：`revenue_yi`；行：`region`（排序）；颜色按 region；可加 `year` 播放器（Pages）看演变

**Sheet 4.3 永辉 vs 胖东来**
- 用 `ads_vs_pangdonglai`（03 脚本产出）或两张 CSV 关联
- 左图：`rev_per_store_yi` 条形（company 分色：永辉蓝 / 胖东来橙）
- 右图：`net_margin_pct` 折线（company 分色）
- 标注：胖东来 14 家店单店产出约 8.6 亿 ≈ 永辉的 10 倍；净利率 +8.8% vs -2.2%

**Sheet 4.4 员工与模式对标卡片**
- 用 `pdl_benchmark.csv` 做 5 张文本表卡片（月薪 9886 元 / 流失率 5% / 年假 140 天等）

---

## 看板 5｜市场视角：股价如何为转型定价（CSMAR 数据）

**Sheet 5.1 月收盘价与累计收益**
- 列：`month_date`（计算字段）；行：`mclsprc`（折线）
- 右轴：`cum_ret_pct`（面积，基期 2019-01）
- 标注点（注释/参考线）：2024-05 调改宣布、2024-09-23 名创优品入主
- 标题：`601933 月收盘价与累计收益（2019-01 至 2025-10）`

**Sheet 5.2 事件窗口（可选进阶）**
- 用 `ads_event_study`（05 脚本产出）：列 `rel_day`，行 `car_pct`，按 `event` 分色
- 标题：`事件研究：转型公告的市场反应（[-10,+10] 交易日 CAR）`

**Sheet 5.3 基本面 vs 股价**
- 双轴：`revenue_yoy_pct`（条形）与 `year_ret_pct`（折线）
- 标题：`营收增速 vs 股价年度涨跌幅`

---

## 仪表盘组装建议（Dashboard）

1. **总览页**：顶部标题 + KPI 大数字（2024 营收 675.7 亿 / -14.1%、归母净利 -14.65 亿、门店 775 家、同店效应 +6.6 亿），下方 Sheet 1.1 + 1.2
2. **盈利诊断页**：Sheet 2.1（左上）+ 2.2（右上）+ 2.3（左下）+ 2.4（右下）
3. **运营短板页**：Sheet 3.1/3.2/3.3 三联排
4. **对标页**：Sheet 4.1 + 4.3 + 员工卡片
5. **市场页**：Sheet 5.1 占主体 + 5.3 底部

**交互设置**：
- 全局筛选器：`year`（范围滑块）挂在所有仪表盘
- Sheet 1.2 点选年份 → 联动跳转"盈利诊断页"（Dashboard Action → Go to Sheet）
- Tooltip 中加入 `diagnosis`、`inventory_status` 等解读字段

**导出**：仪表盘导出 PNG/PDF 放入 `report/figures/`；`.twbx` 打包保存到 `tableau_workbook/`。

---

## 数据口径备忘（写进看板脚注）

- 营收口径：营业总收入（含服务业收入）；单店指标 = 年度营收 / 年末门店数
- 同店效应拆解：假定营收 = 上年单店产出 × 本年年末门店数（与课程报告 PPT 口径一致）
- 库存周转天数 = 365 × 平均存货 / 营业成本
- 区域面板 2024 为年报披露口径，早年为按年报结构回溯的估算（`is_estimated=1`），仅课程分析用
- 胖东来为非上市公司，数据来自公开披露/新闻报道
- 股价数据来自 CSMAR（TRD_Dalyr / TRD_Mnth），日频 2020-01-02 至 2024-12-31，月频 2019-01 至 2025-10
