-- PROJECT: E-commerce Retention & RFM Analysis
-- AUTHOR: Ekaterina
-- DESCRIPTION: SQL queries for data cleaning, basic metrics, cohort analysis and RFM segmentation.


-- 1. Создаю виртуальную таблицу с очищенными данными cleaned_orders, для упрощения дальнейшей работы без повторного использования шагов очистки. 
-- Предварительно была проведена работа по выявлению некорректных данных и их фиксация. 
	-- (- очистка дат order_date и ship_date: приведение дат к единому формату; дополнительная чистка в ship_date: лишние пробелы, табуляции и другие наименования заменены на NULL.
	 -- очистка столбца Status: удаление лишних пробелов, использование CASE в целях замены слов с ошибками, приведение к единому регистру;
	 -- очистка столбца payment_method: удаление лишних пробелов, использование CASE в целях замены слов с ошибками, приведение к единому регистру;
	 -- очистка столбца Region: так как выявлены слова написанные Кириллицей с использованием букв английского алфавита, с помощью CASE произведена полная замена всех вариаций наименования 
-- городов с ошибками на единый формат, одновременно исправляя проблемы с регистром, пробелами, заменой английских букв и ошибками в написании)
-- В рамках проекта очистка некоторых показателей была необязательной (payment_method, ship_date), так как они участвовали в расчетах. 
-- Тем не менее, мною было принято решение очистить данные до "идеала" для самоудовлетворения.


CREATE VIEW IF NOT EXISTS cleaned_orders AS
SELECT 
	order_id, 
	customer_id,
CASE 
	WHEN TRIM(order_date) LIKE '__.__.____' THEN 
	SUBSTR(TRIM(order_date), 7, 4) || '-' || 
	SUBSTR(TRIM(order_date), 4, 2) || '-' || 
	SUBSTR(TRIM(order_date), 1, 2)
	WHEN TRIM(order_date) LIKE '__/__/____' THEN 
	SUBSTR(TRIM(order_date), 7, 4) || '-' || 
	SUBSTR(TRIM(order_date), 1, 2) || '-' || 
	SUBSTR(TRIM(order_date), 4, 2)
	ELSE TRIM(order_date) END AS order_date_clean,
CASE 
	WHEN TRIM(ship_date) LIKE '__.__.____' THEN 
	SUBSTR(TRIM(ship_date), 7, 4) || '-' || 
	SUBSTR(TRIM(ship_date), 4, 2) || '-' || 
	SUBSTR(TRIM(ship_date), 1, 2)
	WHEN LOWER(TRIM(ship_date)) IN ('n/a', 'nan',' ','-','--') THEN NULL
	WHEN REPLACE(REPLACE(REPLACE(ship_date,' ',''), char(9),''), char(160),'') = '' THEN NULL
	WHEN ship_date IS NULL THEN NULL
	ELSE TRIM(ship_date) END AS ship_date_clean,
CASE 
	WHEN LOWER(TRIM(status)) = 'deliverd' THEN 'Delivered' 
	WHEN LOWER(TRIM(status)) = 'canceled' THEN 'Cancelled' 
	ELSE UPPER(SUBSTR(TRIM(status), 1, 1)) || LOWER(SUBSTR(TRIM(status), 2)) 
END AS status_clean, 
CASE 
	WHEN LOWER(TRIM(payment_method)) IN ('credit crd', 'credit card') THEN 'Credit Card' 
	WHEN LOWER(TRIM(payment_method)) = 'cash on delivery' THEN 'Cash on Delivery' 
	WHEN LOWER(TRIM(payment_method)) = 'paypal' THEN 'PayPal' 
	WHEN LOWER(TRIM(payment_method)) = 'bank transfer' THEN 'Bank Transfer' 
	ELSE COALESCE(UPPER(SUBSTR(TRIM(payment_method), 1, 1)) || LOWER(SUBSTR(TRIM(payment_method), 2)), 'Unknown') 
END AS payment_clean, 
CASE 
	WHEN TRIM(region) IN ('Москва', 'москва', 'МОСКВА') THEN 'Москва' 
	WHEN TRIM(region) IN ('Казань', 'казань', 'КАЗАНЬ') THEN 'Казань' 
	WHEN TRIM(region) IN ('Новосибирск', 'новосибирск', 'НОВОСИБИРСК') THEN 'Новосибирск' 
	WHEN TRIM(region) IN ('Екатеринбург', 'екатеринбург', 'ЕКАТЕРИНБУРГ') THEN 'Екатеринбург' 
	WHEN TRIM(region) IN ('Санкт-Петербург', 'Санкт-петербург', 'санкт-петербург', 'САНКТ-ПЕТЕРБУРГ') THEN 'Санкт-Петербург' 
	WHEN TRIM(region) IN ('Ростов-На-Дону', 'Ростов-на-Дону', 'ростов-на-дону', 'РОСТОВ-НА-ДОНУ') THEN 'Ростов-на-Дону' 
	ELSE UPPER(SUBSTR(TRIM(REPLACE(REPLACE(region,'o','о'), 'a','а')),1,1))||LOWER(SUBSTR(TRIM(REPLACE(REPLACE(region,'o','о'), 'a','а')),2))
END AS region_clean, 
	total_amount, 
	category 
FROM project_orders;


-- 2. Считаю базовые метрики (BASIC METRICS): общую выручку, количество уникальных заказов, средний чек и количество уникальных клиентов 
-- (для всех расчетов сейчас и в последующем используем уже очищенную виртуальную таблицу. Не использовала AVG, так как есть номера-дубли в order_id, через формулу с уникальным количеством 
-- заказов результат более точный)

SELECT 
    SUM(CAST(total_amount AS REAL)) AS total_revenue,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(CAST(total_amount AS REAL)) / COUNT(DISTINCT order_id), 2) AS aov,
    COUNT(DISTINCT customer_id) AS total_customers
FROM cleaned_orders;

-- 3. Считаю выручку по категориям
SELECT 
    category, 
    SUM(CAST(total_amount AS REAL)) AS total_revenue,
    COUNT(DISTINCT order_id) AS orders_count
FROM cleaned_orders
GROUP BY category
ORDER BY total_revenue DESC;

-- 4. Считаю удержание клиентов по месяцам COHORT ANALYSIS (RETENTION RATE)
-- (Для получения необходимых нам показателей используем CTE. Считаем все пошагово:
-- шаг 1 - поиск 1 месяца покупки клиента;
-- шаг 2 - расчет количества прошедших месяцев с момента 1 заказа. Использую формулу разницы в месяцах: (Год заказа - Год когорты)*12 + (Месяц заказа - Месяц когорты), также использую JOIN для соединения 
-- 2-х таблиц: основной и 1 CTE)
-- шаг 3 - расчет количества уникальных клиентов по 1 месяцу и количеству месяцев
-- шаг 4 - обозначаем 0 месяц посредством выбора ГДЕ количество месяцев = 0
-- шаг 5 - считаем процент удержания (использую JOIN для соединения 2-х таблиц: 3 и 4 CTE)

WITH first_orders AS(
    SELECT customer_id, MIN(STRFTIME('%Y-%m', order_date_clean)) AS cohort_month
    FROM cleaned_orders GROUP BY customer_id),
orders_with_cohort AS(
    SELECT o.customer_id, f.cohort_month,
        (CAST(STRFTIME('%Y', o.order_date_clean) AS INTEGER) - CAST(SUBSTR(f.cohort_month, 1, 4) AS INTEGER)) * 12 +
        (CAST(STRFTIME('%m', o.order_date_clean) AS INTEGER) - CAST(SUBSTR(f.cohort_month, 6, 2) AS INTEGER)) AS month_number
    FROM cleaned_orders o JOIN first_orders f ON o.customer_id = f.customer_id),
cohort_sizes AS(
    SELECT cohort_month, month_number, COUNT(DISTINCT customer_id) AS customer_count
    FROM orders_with_cohort GROUP BY cohort_month, month_number),
base_sizes AS(
    SELECT cohort_month, customer_count AS base_count FROM cohort_sizes WHERE month_number = 0)
SELECT c.cohort_month, c.month_number, c.customer_count,
    ROUND(100.0 * c.customer_count / b.base_count, 2) AS retention_pct
FROM cohort_sizes c JOIN base_sizes b ON c.cohort_month = b.cohort_month
ORDER BY c.cohort_month, c.month_number;


-- 5. Разбиваем клиентов на сегменты VIP, Спящие, Под риском оттока, Новички, Обычные (RFM SEGMENTATION)
-- (Для получения необходимых нам показателей используем CTE. Считаем все пошагово:
-- шаг 1 - поиск последнего месяца покупки клиента;
-- шаг 2 - считаю сколько дней прошло от заказа до максимальной даты в базе (recency), расчет количества уникальных заказов (frequency), расчет суммы заказов по клиенту (monetary)
-- шаг 3 - произвожу разбивку показателей на 5 групп через оконную функцию NTILE (от 1 до 5). Для моего проекта, чем меньше дней - тем лучше, поэтому произвожу инвертирование (6-1=5, 6-5=1)
-- шаг 4 - в финальном SELECT использую CAST для приведения логики сегментов как Python 


WITH max_date AS(
    SELECT MAX(order_date_clean) AS max_order_date FROM cleaned_orders),
rfm_base AS(
    SELECT customer_id,
        CAST(JULIANDAY((SELECT max_order_date FROM max_date)) - JULIANDAY(MAX(order_date_clean)) AS INTEGER) AS recency,
        COUNT(DISTINCT order_id) AS frequency, SUM(total_amount) AS monetary
    FROM cleaned_orders GROUP BY customer_id),
rfm_scores AS(
    SELECT customer_id, recency, frequency, monetary,
        6 - NTILE(5) OVER (ORDER BY recency ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_base)
SELECT customer_id, recency, frequency, monetary, r_score, f_score, m_score,
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP'
        WHEN r_score <= 2 AND f_score >= 4 THEN 'Под риском оттока'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Спящие'
        WHEN r_score >= 4 AND f_score = 1 THEN 'Новички'
        ELSE 'Обычные'
    END AS segment
FROM rfm_scores
ORDER BY monetary DESC;

-- 6! Для проверки соответствия данных между расчета в Python и SQL дополнительно прикладываю код ниже, где добавлен шаг с расчетом количества клиентов по каждому сегменту. (ниже описание полученного результата)


WITH max_date AS(
   SELECT MAX(order_date_clean) AS max_order_date 
FROM cleaned_orders), 
rfm_base AS(
   SELECT customer_id, 
	CAST(JULIANDAY((SELECT max_order_date FROM max_date)) - JULIANDAY(MAX(order_date_clean)) AS INTEGER) AS recency, 
	COUNT(DISTINCT order_id) AS frequency, SUM(total_amount) AS monetary 
   FROM cleaned_orders GROUP BY customer_id), 
rfm_scores AS(
   SELECT customer_id, recency, frequency, monetary, 
	6 - NTILE(5) OVER (ORDER BY recency ASC) AS r_score, 
	NTILE(5) OVER (ORDER BY frequency ASC) AS f_score, 
	NTILE(5) OVER (ORDER BY monetary ASC) AS m_score 
   FROM rfm_base), 
rfm_segments AS(
   SELECT customer_id, 
	CASE 
	   WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'VIP' 
	   WHEN r_score <= 2 AND f_score >= 4 THEN 'Под риском оттока'
	   WHEN r_score <= 2 AND f_score <= 2 THEN 'Спящие' 
	   WHEN r_score >= 4 AND f_score = 1 THEN 'Новички' 
	   ELSE 'Обычные' END AS segment 
   FROM rfm_scores) 
SELECT segment, COUNT(*) AS customers_count 
FROM rfm_segments GROUP BY segment ORDER BY customers_count DESC;

-- по результатам расчетов, данные по сегментам совпали примерно на 95%, разница возникла из-за разного рабочего механизма используемых функций: 
-- qcut Pandas - учитывает все значения как заложено, NTILE SQL делит строго по заданному алгоритму. В рамках бизнес-процессов эта ситуация не значительна. 

