
-- 1. 公司整体
SELECT c.`渠道`, c.`目标Sales($)`, c.`实际Sales($)`,
       ROUND(c.`实际Sales($)` / NULLIF(c.`目标Sales($)`, 0) * 100, 2) AS `达成率(%)`,
       c.`实际Sales($)` - c.`目标Sales($)` AS `超额或缺口($)`,
       p.`金额($)` AS `经营利润($)`,
       ROUND(p.`金额($)` / NULLIF(c.`实际Sales($)`, 0) * 100, 2) AS `利润率(%)`
FROM `02_BF分渠道汇总` c
JOIN `06_BF完整P&L` p ON c.`渠道` = p.`渠道`
WHERE p.`项目` = '净利润';

-- 预算情况
SELECT SUM(`实际Sales($)`) AS `总销售额($)`,
       SUM(`Ad Spend($)`) AS `广告花费($)`,
       180000 AS `批准广告预算($)`,
       SUM(`Ad Spend($)`) - 180000 AS `超预算金额($)`
FROM `02_BF分渠道汇总`;

-- 2. EU销售过程：先按天求和，再计算订单转化率和客单价。
SELECT `日期`, SUM(`Sessions`) AS `访问会话数`, SUM(`Orders`) AS `订单量`,
       SUM(`Sales($)`) AS `销售额($)`,
       ROUND(SUM(`Orders`) / NULLIF(SUM(`Sessions`), 0) * 100, 2) AS `订单转化率(%)`,
       ROUND(SUM(`Sales($)`) / NULLIF(SUM(`Orders`), 0), 2) AS `客单价($)`
FROM `03_BF小时级监控`
WHERE `渠道` = 'Amazon EU'
GROUP BY `日期`
ORDER BY `日期`;

-- 3. EU优惠券异常
-- 取首日异常前、中、后，以及后两天同一时段。每段均为4小时。
WITH eu_hours AS (
    SELECT *,
           CASE
               WHEN `日期` = '2024-11-29' AND `小时(ET)` >= '10:00' AND `小时(ET)` < '14:00' THEN '异常前'
               WHEN `日期` = '2024-11-29' AND `小时(ET)` >= '14:00' AND `小时(ET)` < '18:00' THEN '异常期间'
               WHEN `日期` = '2024-11-29' AND `小时(ET)` >= '18:00' AND `小时(ET)` < '22:00' THEN '异常后'
               WHEN `日期` IN ('2024-11-30', '2024-12-01') AND `小时(ET)` >= '14:00' AND `小时(ET)` < '18:00' THEN '后续同时间'
           END AS `比较时段`
    FROM `03_BF小时级监控`
    WHERE `渠道` = 'Amazon EU'
)
SELECT `日期`, `比较时段`, COUNT(*) AS `小时数`,
       SUM(`Sessions`) AS `访问会话数`, SUM(`Orders`) AS `订单量`,
       SUM(`Sales($)`) AS `销售额($)`,
       ROUND(SUM(`Orders`) / NULLIF(SUM(`Sessions`), 0) * 100, 2) AS `订单转化率(%)`,
       ROUND(SUM(`Sales($)`) / NULLIF(SUM(`Orders`), 0), 2) AS `客单价($)`
FROM eu_hours
WHERE `比较时段` IS NOT NULL
GROUP BY `日期`, `比较时段`
ORDER BY `日期`, MIN(`小时(ET)`);

-- 4. 广告效率
SELECT `渠道`, `广告类型`, `花费($)`,
       ROUND(`花费($)` / NULLIF(SUM(`花费($)`) OVER(PARTITION BY `渠道`), 0) * 100, 2) AS `站点花费占比(%)`,
       ROUND(`Attributed Sales($)` / NULLIF(`花费($)`, 0), 2) AS `ROAS`,
       ROUND((`Attributed Sales($)` / NULLIF(`花费($)`, 0) / NULLIF(`日常ROAS`, 0) - 1) * 100, 2) AS `ROAS变化(%)`,
       ROUND((`CPC($)` / NULLIF(`日常CPC($)`, 0) - 1) * 100, 2) AS `CPC变化(%)`
FROM `05_BF广告效率`
WHERE `渠道` <> '全渠道'
ORDER BY `渠道`, `花费($)` DESC;

-- 5. 成本构成
SELECT c.`渠道`, c.`项目`, -c.`金额($)` AS `费用($)`,
       ROUND(-c.`金额($)` / NULLIF(s.`金额($)`, 0) * 100, 2) AS `占销售额比例(%)`
FROM `06_BF完整P&L` c
JOIN `06_BF完整P&L` s ON c.`渠道` = s.`渠道` AND s.`项目` = '销售收入'
WHERE c.`项目` NOT IN ('销售收入', '净利润')
ORDER BY c.`渠道`, `占销售额比例(%)` DESC;

-- 6. TikTok保本广告上限：收入减去非广告成本。
WITH tk_cost AS (
    SELECT SUM(CASE WHEN `项目` = '销售收入' THEN `金额($)` ELSE 0 END) AS sales,
           -SUM(CASE WHEN `项目` = '广告费用' THEN `金额($)` ELSE 0 END) AS ad_cost,
           -SUM(CASE WHEN `项目` NOT IN ('销售收入', '广告费用', '净利润') THEN `金额($)` ELSE 0 END) AS non_ad_cost,
           SUM(CASE WHEN `项目` = '净利润' THEN `金额($)` ELSE 0 END) AS profit
    FROM `06_BF完整P&L`
    WHERE `渠道` = 'TikTok Shop SEA'
)
SELECT sales AS `销售额($)`, non_ad_cost AS `非广告成本($)`,
       sales - non_ad_cost AS `静态保本广告上限($)`,
       ad_cost AS `实际广告花费($)`,
       ad_cost - (sales - non_ad_cost) AS `超过保本上限金额($)`,
       profit AS `经营利润($)`
FROM tk_cost;


-- 7. 商品库存
SELECT `渠道`, `ASIN`, `产品名称`, `Sales($)`,
       ROUND(`Sales($)` / NULLIF(SUM(`Sales($)`) OVER(PARTITION BY `渠道`), 0) * 100, 2) AS `销售贡献(%)`,
       ROUND(`Ad Spend($)` / NULLIF(`Sales($)`, 0) * 100, 2) AS `广告占销售(%)`,
       ROUND(`Units` * 100.0 / NULLIF(`BF前库存`, 0), 2) AS `活动库存消化率(%)`,
       `BF后库存`,
       ROUND(`BF后库存` * 100.0 / NULLIF(SUM(`BF后库存`) OVER(PARTITION BY `渠道`), 0), 2) AS `期末库存占比(%)`,
       `状态`
FROM `04_BF分ASIN表现`
ORDER BY `渠道`, `Sales($)` DESC;

-- 8. 四段异常
SELECT `渠道`, `日期`, `备注`, MIN(`小时(ET)`) AS `起始小时`,
       MAX(`小时(ET)`) AS `末条小时`, COUNT(*) AS `标记小时数`,
       SUM(`Sales($)`) AS `销售额($)`,
       ROUND(SUM(`Orders`) * 100.0 / NULLIF(SUM(`Sessions`), 0), 2) AS `订单转化率(%)`,
       ROUND(SUM(`Sales($)`) / NULLIF(SUM(`Orders`), 0), 2) AS `客单价($)`
FROM `03_BF小时级监控`
WHERE `备注` IS NOT NULL AND TRIM(`备注`) <> ''
GROUP BY `渠道`, `日期`, `备注`
ORDER BY `日期`, `起始小时`;
