USE olist_ecommerce_project;

-- ============================================================
-- SECTION 1: ORDER COMPLETION AND DELIVERY PERFORMANCE
-- ============================================================


-- ------------------------------------------------------------
-- 1.1 HOW MANY ORDERS ARE IN EACH STATUS?
-- ------------------------------------------------------------

WITH status_counts AS (
    SELECT order_status, COUNT(*) AS number_of_orders
    FROM orders
    GROUP BY order_status
)
SELECT
    order_status,
    number_of_orders,
    ROUND(number_of_orders * 100.0 / SUM(number_of_orders) OVER (), 2) AS percentage_of_orders
FROM status_counts
ORDER BY number_of_orders DESC;

-- Finding: 97.02% of orders have a recorded status of delivered.
-- This measures delivery completion, not whether delivery was on time.


-- ------------------------------------------------------------
-- 1.2 HOW MANY DELIVERED ORDERS WERE ON TIME OR LATE?
-- ------------------------------------------------------------

WITH delivery_timing_status AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date IS NULL
              OR order_estimated_delivery_date IS NULL THEN 'Date Missing'
            WHEN DATE(order_delivered_customer_date) <= DATE(order_estimated_delivery_date) THEN 'On Time'
            ELSE 'Late'
        END AS delivery_timing
    FROM orders
    WHERE order_status = 'delivered'
),
timing_counts AS (
    SELECT delivery_timing, COUNT(*) AS number_of_orders
    FROM delivery_timing_status
    GROUP BY delivery_timing
)
SELECT
    delivery_timing,
    number_of_orders,
    ROUND(number_of_orders * 100.0 / SUM(number_of_orders) OVER (), 2) AS percentage_of_delivered_orders
FROM timing_counts
GROUP BY delivery_timing
ORDER BY number_of_orders DESC;

-- Finding: Of 96,478 delivered orders, 89,936 (93.22%) arrived
-- on or before the estimated delivery date.
-- Another 6,534 (6.77%) arrived late.
-- Eight orders (0.01%) could not be assessed because a date was missing.
-- Percentages use all delivered orders as the denominator.
-- Timing is assessed by calendar date, excluding the time of day.


-- ------------------------------------------------------------
-- 1.3 HOW LONG WERE LATE ORDERS DELAYED?
-- ------------------------------------------------------------

WITH late_deliveries AS (
    SELECT
        order_id,
        DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) AS days_late
    FROM orders
    WHERE order_status = 'delivered'
      AND DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
)
SELECT
    COUNT(*) AS late_deliveries,
    ROUND(AVG(days_late), 2) AS average_days_late,
    MIN(days_late) AS minimum_days_late,
    MAX(days_late) AS maximum_days_late
FROM late_deliveries;

-- Finding: Among 6,534 late delivered orders, the average delay
-- was 10.62 days, with delays ranging from 1 to 188 days.


-- ------------------------------------------------------------
-- 1.4 INSPECT THE ORDER WITH THE MAXIMUM RECORDED DELAY
-- ------------------------------------------------------------

SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_estimated_delivery_date,
    order_delivered_customer_date,
    DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) AS days_late
FROM orders
WHERE order_status = 'delivered'
  AND DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) = 188;

-- Finding: The maximum recorded delay was 188 calendar days.
-- The order was expected on 2018-03-15 and recorded as delivered
-- on 2018-09-19.
-- Retain this record: an unusually long delay alone does not
-- establish a data error, and its cause is unknown.


-- ------------------------------------------------------------
-- 1.5 HOW ARE LATE ORDERS DISTRIBUTED BY DELAY RANGE?
-- ------------------------------------------------------------

WITH late_deliveries AS (
    SELECT
        DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) AS days_late
    FROM orders
    WHERE order_status = 'delivered'
      AND DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
),
delay_ranges AS (
    SELECT
        days_late,
        CASE
            WHEN days_late <= 3 THEN '1–3 days'
            WHEN days_late <= 7 THEN '4–7 days'
            WHEN days_late <= 14 THEN '8–14 days'
            WHEN days_late <= 30 THEN '15–30 days'
            ELSE 'More than 30 days'
        END AS delay_range
    FROM late_deliveries
)
SELECT
    delay_range,
    COUNT(*) AS number_of_orders
FROM delay_ranges
GROUP BY delay_range
ORDER BY MIN(days_late);

-- Finding: Among late delivered orders, 56.20% arrived within
-- seven days after the estimated date.
-- However, 21.18% were more than 14 days late, including
-- 5.28% that were more than 30 days late.


-- ============================================================
-- SECTION 2: CUSTOMER FEEDBACK
-- ============================================================


-- ------------------------------------------------------------
-- 2.1 INSPECT REVIEWS ATTACHED TO DELIVERED ORDERS
-- ------------------------------------------------------------

SELECT
    o.customer_id,
    o.order_id,
    r.review_id,
    r.review_score
FROM orders AS o
JOIN order_reviews AS r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered';

-- Inspection query: each row represents a matching review record.
-- An order can appear more than once if it has multiple reviews.


-- ------------------------------------------------------------
-- 2.2 WHAT PERCENTAGE OF REVIEWED, DELIVERED ORDERS
--     HAD AN AVERAGE REVIEW SCORE OF 4 OR HIGHER?
-- ------------------------------------------------------------

WITH order_review_summary AS (
    SELECT
        o.order_id,
        AVG(r.review_score) AS average_review_score
    FROM orders AS o
    JOIN order_reviews AS r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
)
SELECT
    COUNT(*) AS total_reviewed_orders,
    SUM(CASE WHEN average_review_score >= 4 THEN 1 ELSE 0 END) AS orders_scoring_4_or_higher,
    ROUND(SUM(CASE WHEN average_review_score >= 4 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS percentage_scoring_4_or_higher
FROM order_review_summary;

-- Finding: Of 95,832 delivered orders with reviews, 75,626
-- had an average review score of 4 or higher (78.91%).
-- This indicates mostly positive feedback among reviewed,
-- delivered orders; it does not represent all customers.


-- ------------------------------------------------------------
-- 2.3 WHICH PRODUCT CATEGORIES HAVE THE HIGHEST
--     PERCENTAGE OF ORDERS WITH AT LEAST ONE POOR REVIEW?
-- ------------------------------------------------------------

-- A poor review is a score of 1 or 2.
-- This query uses "at least one poor review", whereas Section 2.2
-- uses an average score per order. These are different measures.
-- Include only categories with at least 100 reviewed orders.
-- Count each order once per category, regardless of item count.

WITH category_reviews AS (
    SELECT
        o.order_id,
        oi.order_item_id,
        oi.product_id,
        p.product_category_name,
        r.review_score
    FROM orders AS o
    JOIN order_items AS oi ON o.order_id = oi.order_id
    JOIN products AS p ON oi.product_id = p.product_id
    JOIN order_reviews AS r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
)
SELECT
    product_category_name,
    COUNT(DISTINCT order_id) AS reviewed_orders,
    COUNT(DISTINCT CASE WHEN review_score <= 2 THEN order_id END) AS poorly_reviewed_orders,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN review_score <= 2 THEN order_id END) / COUNT(DISTINCT order_id), 2) AS percentage_poorly_reviewed
FROM category_reviews
GROUP BY product_category_name
HAVING COUNT(DISTINCT order_id) >= 100
ORDER BY percentage_poorly_reviewed DESC, reviewed_orders DESC;

-- Findings: Among categories meeting the 100-order threshold,
-- men's clothing had the highest poor-rating rate:
-- 22.86% (24 of 105 reviewed orders).
-- Office furniture followed at 22.11% (275 of 1,244),
-- then audio at 21.74% (75 of 345).
--
-- Bed, bath and table products had a lower rate of 16.17%,
-- but accounted for 1,484 poorly rated orders.
-- Consider both the percentage and the affected order count
-- when selecting categories for further investigation.
--
-- An order containing products from multiple categories counts
-- once in each category, so category totals can overlap.
-- Reviews concern the order experience; these results do not
-- establish which product or service issue caused poor feedback.


with MA as
(
SELECT DISTINCT
	o.order_id,
	r.review_id,
	oi.seller_id,
	r.review_score,
	o.order_delivered_customer_date,
	r.review_answer_timestamp,
	r.review_comment_message,
    CASE
    WHEN r.review_answer_timestamp IS NULL
      OR o.order_delivered_customer_date IS NULL
        THEN 'Date missing'

    WHEN r.review_answer_timestamp < o.order_delivered_customer_date
        THEN 'Review before delivery'

    WHEN r.review_answer_timestamp > o.order_delivered_customer_date
        THEN 'Review after delivery'

    ELSE 'Same timestamp'
END AS review_delivery_timing
FROM order_reviews r
	join orders o on r.order_id = o.order_id
    join order_items oi on oi.order_id = o.order_id
    join products p on p.product_id = oi.product_id
    join sellers s on s.seller_id = oi.seller_id
where review_score <= 2
	AND order_status = 'delivered'
    AND s.seller_id = '7c67e1448b00f6e969d365cea6b010ab'
    AND o.order_delivered_customer_date IS NOT NULL
	AND p.product_category_name IN ('fashion_roupa_masculina', 'moveis_escritorio', 'audio')
    AND (
    LOWER(r.review_comment_message) LIKE '%não recebi%'
    OR LOWER(r.review_comment_message) LIKE '%nao recebi%'
    OR LOWER(r.review_comment_message) LIKE '%não me entregaram%'
    OR LOWER(r.review_comment_message) LIKE '%nao me entregaram%'
    OR LOWER(r.review_comment_message) LIKE '%não foi entregue%'
    OR LOWER(r.review_comment_message) LIKE '%nao foi entregue%'
    OR LOWER(r.review_comment_message) LIKE '%não chegou%'
    OR LOWER(r.review_comment_message) LIKE '%nao chegou%'
    OR LOWER(r.review_comment_message) LIKE '%não receby%'
)
ORDER BY o.order_id
)
SELECT
	order_id,
	review_id,
	seller_id,
	review_score,
	order_delivered_customer_date,
	review_answer_timestamp,
	review_comment_message,
    review_delivery_timing
from MA
WHERE review_delivery_timing = 'Review after delivery';

-- ============================================================
-- FOLLOW-UP: NON-RECEIPT PHRASE MATCHES AFTER RECORDED DELIVERY
-- ============================================================
-- Scope: Delivered orders associated with one selected seller
-- in men's clothing, office furniture, and audio.
-- Includes 1–2-star reviews matching selected Portuguese phrases,
-- submitted after the recorded delivery timestamp.
--
-- Finding: The query returned 17 review records across 17 orders.
-- Manual reading showed several issues: reported non-receipt,
-- partial deliveries, missing parts, collection problems,
-- and an incorrect product.
--
-- Limitation: Phrase matching also captured statements such as
-- "I did not receive a response", not just missing products.
-- These results do not establish 17 complete non-deliveries,
-- incorrect delivery statuses, or seller responsibility.
-- They also do not show the most common complaints across
-- all customers or the selected categories.
--
-- Recommendation: Investigate the flagged orders using delivery
-- confirmation and support records to clarify what happened.


SELECT
	p.product_category_name,
    sum(oi.price) as item_sales_value
    FROM orders as o
    JOIN order_items as oi ON oi.order_id = o.order_id
    JOIN products as p ON p.product_id = oi.product_id
    WHERE order_status = 'delivered'
    GROUP BY p.product_category_name
	ORDER BY item_sales_value DESC;
    -- DELIVERED ITEM SALES VALUE BY PRODUCT CATEGORY
	-- Sums item prices for delivered orders, excluding freight.
	-- Health and beauty ranks first, followed by watches and gifts,
	-- then bed, bath and table.
	-- This measures delivered item sales value, not profit or
	-- revenue adjusted for refunds and returns.
    
    With Sales_Assessment as
    (
    SELECT
	p.product_category_name,
    sum(oi.price) as item_sales_value
    FROM orders as o
    JOIN order_items as oi ON oi.order_id = o.order_id
    JOIN products as p ON p.product_id = oi.product_id
    WHERE order_status = 'delivered'
    GROUP BY p.product_category_name
	ORDER BY item_sales_value DESC
    ),
    TSA AS
    (
	SELECT
		sum(item_sales_value) as Total_Sales_Value
	FROM Sales_Assessment
    )
    SELECT
		sa.product_category_name,
        sa.item_sales_value,
		ROUND(100 * (item_sales_value/Total_Sales_Value),2) AS PROPORTION_CONTRIBUTED_BY_CATEGORY
      FROM Sales_Assessment as sa
      CROSS JOIN TSA
      ORDER BY 3 DESC;
      -- CATEGORY SHARE OF DELIVERED ITEM SALES VALUE
	  -- Health and beauty contributes 9.33%, followed by watches
	  -- and gifts at 8.82%, and bed, bath and table at 7.74%.
	  -- The top five categories together contribute approximately
	  -- 39.83% of total delivered item sales value.
	  -- Values exclude freight and are not adjusted for refunds or returns.
      
      
WITH category_sales AS (
    SELECT
        p.product_category_name,
        SUM(oi.price) AS item_sales_value
    FROM orders AS o
    JOIN order_items AS oi ON o.order_id = oi.order_id
    JOIN products AS p ON oi.product_id = p.product_id
    WHERE o.order_status = 'delivered'
    GROUP BY p.product_category_name
),

total_sales AS (
    SELECT SUM(item_sales_value) AS total_sales_value
    FROM category_sales
),

category_feedback AS (
    SELECT
        p.product_category_name,
        COUNT(DISTINCT o.order_id) AS reviewed_orders,
        COUNT(DISTINCT CASE WHEN r.review_score <= 2 THEN o.order_id END) AS orders_with_low_score_reviews
    FROM orders AS o
    JOIN order_items AS oi ON o.order_id = oi.order_id
    JOIN products AS p ON oi.product_id = p.product_id
    JOIN order_reviews AS r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY p.product_category_name
),

top_categories AS (
    SELECT product_category_name, item_sales_value
    FROM category_sales
    ORDER BY item_sales_value DESC, product_category_name
    LIMIT 10
)
SELECT
    s.product_category_name,
    s.item_sales_value,
    ROUND(100.0 * s.item_sales_value / t.total_sales_value, 2) AS sales_share_percentage,
    f.reviewed_orders,
    f.orders_with_low_score_reviews,
    ROUND(100.0 * f.orders_with_low_score_reviews / f.reviewed_orders, 2) AS low_score_order_percentage
FROM top_categories AS s
JOIN category_feedback AS f
    ON s.product_category_name = f.product_category_name
CROSS JOIN total_sales AS t
WHERE f.reviewed_orders >= 100
ORDER BY f.orders_with_low_score_reviews DESC, s.item_sales_value DESC;
-- PURPOSE: Identify which of the top 10 product categories by
-- delivered item sales value have the most orders receiving
-- at least one 1–2-star review.
--
-- This helps prioritize customer-experience investigations
-- in commercially important categories.
-- Includes only categories with at least 100 reviewed orders.
-- Shows both affected order counts and low-score percentages.
-- Does not measure refunds, lost revenue, or causes of poor feedback.

-- ============================================================
-- LOW-SCORE FEEDBACK AMONG THE TOP 10 SELLING CATEGORIES
-- ============================================================
-- Purpose: Identify commercially important categories with
-- substantial low-score feedback to prioritize investigation.
-- Selects the top 10 categories by delivered item sales value,
-- then keeps those with at least 100 reviewed orders.
-- An affected order has at least one review scoring 1 or 2.
--
-- Findings:
-- Bed, bath and table stands out: it contributes 7.74% of
-- delivered item sales value and has 1,484 affected orders
-- out of 9,177 reviewed orders (16.17%).
-- This is both the largest affected-order count and the
-- highest low-score rate among these top 10 categories.
--
-- Health and beauty contributes the largest sales share (9.33%)
-- and has 987 affected orders, with a lower rate of 11.48%.
--
-- Furniture and decoration has 971 affected orders (15.51%),
-- while computers and accessories has 951 (14.63%).
--
-- Implication: Prioritize investigation of bed, bath and table,
-- considering its sales contribution, affected-order count,
-- and elevated low-score rate within this group.
--
-- Limitations: These results do not establish the causes of
-- poor feedback, refunds, or lost revenue. Order counts can
-- overlap across categories when an order contains products
-- from more than one category.

-- ============================================================
-- SECTION 3: SALES PERFORMANCE
-- 3.4 QUARTERLY DELIVERED ITEM SALES TREND
-- ============================================================
-- Question: How does delivered item sales value change
-- from one purchase quarter to the next?
--
-- Approach: Group delivered orders by purchase year and quarter,
-- then sum their item prices, excluding freight.

-- ============================================================
-- 3.4 QUARTERLY DELIVERED ITEM SALES TREND
-- ============================================================
-- Question: How does delivered item sales value change
-- from one purchase quarter to the next?
--
-- Sales are assigned to the purchase quarter, using orders
-- whose recorded status is delivered. Item prices exclude freight.


-- ------------------------------------------------------------
-- A. CHECK MONTHLY DATA COVERAGE
-- ------------------------------------------------------------
-- Inspect all purchase months and all order statuses.
-- Include delivered-order counts to identify months that
-- contribute little or nothing to the delivered-sales measure.
-- Months with no recorded orders will not appear.

SELECT
    YEAR(order_purchase_timestamp) AS purchase_year,
    MONTH(order_purchase_timestamp) AS purchase_month,
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END) AS delivered_orders
FROM orders
GROUP BY 1, 2
ORDER BY 1, 2;

-- Findings:
-- 2016 contains 4 orders in September, 324 in October,
-- no recorded orders in November, and 1 in December.
-- January 2017 has 800 orders, beginning on 5 January.
-- July and August 2018 contain 6,292 and 6,512 orders.
-- September 2018 contains only 16 orders, none delivered.
-- October 2018 contains only 4 orders.
--
-- These patterns raise comparability concerns at the dataset
-- boundaries. They do not establish why activity is sparse
-- or prove that particular records are missing.

-- ------------------------------------------------------------
-- B. QUARTERLY SALES OVERVIEW ACROSS ALL AVAILABLE DATES
-- ------------------------------------------------------------
-- Retain this overview so excluded periods remain visible.

SELECT
    YEAR(o.order_purchase_timestamp) AS purchase_year,
    QUARTER(o.order_purchase_timestamp) AS purchase_quarter,
    SUM(oi.price) AS delivered_item_sales_value
FROM orders AS o
JOIN order_items AS oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Finding: Recorded delivered item sales value rises each
-- quarter from 2017 Q1 through 2018 Q2, then falls in Q3.
-- However, September 2018 contributes no delivered orders.
-- The Q3 decrease should not be interpreted as a confirmed
-- business downturn without evidence about dataset coverage.

-- ------------------------------------------------------------
-- C. MAIN QUARTERLY COMPARISON: 2017 Q2 THROUGH 2018 Q2
-- ------------------------------------------------------------
-- Select five consecutive quarters away from the sparse
-- boundary periods identified in the monthly check.
-- Excluding 2017 Q1 is a cautious scope choice because January
-- begins on the 5th; this does not prove January is incomplete.
-- Coverage of retained quarters has not been independently verified.

SELECT
    YEAR(o.order_purchase_timestamp) AS purchase_year,
    QUARTER(o.order_purchase_timestamp) AS purchase_quarter,
    SUM(oi.price) AS delivered_item_sales_value
FROM orders AS o
JOIN order_items AS oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
AND o.order_purchase_timestamp >= '2017-04-01'
AND o.order_purchase_timestamp < '2018-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Finding: Within the selected comparison period, delivered
-- item sales value increases each quarter, from 1,251,931.30
-- in 2017 Q2 to 2,807,156.64 in 2018 Q2.
-- This describes recorded delivered item sales value,
-- not profit or revenue adjusted for refunds and returns.


-- ============================================================
-- 3.5 SALES GROWTH: ORDER VOLUME AND AVERAGE ORDER VALUE
-- ============================================================
-- Question: Did sales growth come from more delivered orders,
-- higher average item sales value per order, or both?
-- Uses purchase quarters from 2017 Q2 through 2018 Q2.
-- Item sales value excludes freight.

SELECT
    YEAR(o.order_purchase_timestamp) AS purchase_year,
    QUARTER(o.order_purchase_timestamp) AS purchase_quarter,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    SUM(oi.price) AS delivered_item_sales_value,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS average_order_value
FROM orders AS o
JOIN order_items AS oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
AND o.order_purchase_timestamp >= '2017-04-01'
AND o.order_purchase_timestamp < '2018-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;
-- Comparing 2017 Q2 with 2018 Q2, delivered item sales growth
-- was mainly driven by increased order volume.
-- Delivered orders rose from 8,984 to 19,646, while average
-- order value increased slightly from 139.35 to 142.89.
--
-- However, between 2018 Q1 and Q2, order volume fell while
-- sales increased, supported by higher average order value.
-- Growth drivers therefore differed across quarterly comparisons.

-- ============================================================
-- 3.6 QUARTERLY PURCHASING CUSTOMER COUNT
-- ============================================================
-- Question: Did the number of purchasing customers increase
-- alongside delivered-order growth?
-- Counts customers with at least one delivered order purchased
-- in each quarter, from 2017 Q2 through 2018 Q2.
-- A customer is counted once within each quarter and may
-- appear again in another quarter.

SELECT
    YEAR(o.order_purchase_timestamp) AS purchase_year,
    QUARTER(o.order_purchase_timestamp) AS purchase_quarter,
    COUNT(DISTINCT c.customer_unique_id) AS purchasing_customers
FROM orders AS o
JOIN customers AS c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
AND o.order_purchase_timestamp >= '2017-04-01'
AND o.order_purchase_timestamp < '2018-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Purchasing customers increased from 8,793 in 2017 Q2
-- to 19,391 in 2018 Q2, alongside delivered-order growth.
-- Orders per customer remained close to one in both quarters.
-- This supports growth mainly through more purchasing customers,
-- rather than increased ordering frequency within each quarter.
-- These customers are not necessarily first-time buyers.


- ============================================================
-- 3.7 First time or repeating customers
-- ============================================================
-- QUESTION:
-- Among customers with delivered orders in each quarter,
-- how many were first-time customers and how many were returning?
--
-- First-time: first recorded purchase was in that quarter.
-- Returning: first recorded purchase was before that quarter.
-- First purchase considers all order statuses in the available history.

WITH first_purchase AS (
    -- BLOCK 1: Find each customer's earliest recorded purchase.
    -- Do not restrict the dates here: we need earlier history.

    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_purchase_date
    FROM orders AS o
    JOIN customers AS c
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),

quarterly_customers AS (
    -- BLOCK 2: List each purchasing customer once per quarter.
    -- Multiple delivered orders in a quarter still produce one row.

    SELECT DISTINCT
        YEAR(o.order_purchase_timestamp) AS purchase_year,
        QUARTER(o.order_purchase_timestamp) AS purchase_quarter,
        c.customer_unique_id
    FROM orders AS o
    JOIN customers AS c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-04-01'
      AND o.order_purchase_timestamp < '2018-07-01'
),

customer_classification AS (
    -- BLOCK 3: Compare the customer's first purchase
    -- with the quarter in which they are being counted.

    SELECT
        qc.purchase_year,
        qc.purchase_quarter,
        qc.customer_unique_id,
        CASE
            WHEN YEAR(fp.first_purchase_date) = qc.purchase_year
             AND QUARTER(fp.first_purchase_date) = qc.purchase_quarter
            THEN 'First-time'
            ELSE 'Returning'
        END AS customer_type
    FROM quarterly_customers AS qc
    JOIN first_purchase AS fp
        ON qc.customer_unique_id = fp.customer_unique_id
)

-- BLOCK 4: Count the two customer groups within each quarter.

SELECT
    purchase_year,
    purchase_quarter,
    COUNT(*) AS purchasing_customers,
    SUM(
        CASE WHEN customer_type = 'First-time' THEN 1 ELSE 0 END
    ) AS first_time_customers,
    SUM(
        CASE WHEN customer_type = 'Returning' THEN 1 ELSE 0 END
    ) AS returning_customers
FROM customer_classification
GROUP BY purchase_year, purchase_quarter
ORDER BY purchase_year, purchase_quarter;

-- Finding: Between 2017 Q2 and 2018 Q2, purchasing customers
-- increased from 8,793 to 19,391. First-time customers increased
-- from 8,742 to 18,953, while returning customers rose from 51 to 438.
--
-- First-time customers accounted for approximately 96.35% of
-- the increase in quarterly purchasing customers.
-- This suggests growth in the purchasing customer count was
-- predominantly associated with first-time purchasers.
--
-- First-time means first recorded purchase in the dataset.
-- Returning means first recorded purchase before the quarter.
-- Repeat purchases within a customer's first quarter do not
-- change their classification to returning.


-- ============================================================
-- SECTION 3: SALES PERFORMANCE
-- 3.8 DELIVERY PERFORMANCE DURING ORDER GROWTH
-- ============================================================
-- Question: As delivered orders increased, did the percentage
-- arriving late increase too?
--
-- Scope: Delivered orders purchased from 2017 Q2 to 2018 Q2.
-- Late means actual delivery occurred after the estimated
-- delivery date, comparing calendar dates.
--
-- Orders missing either delivery date are counted separately
-- and excluded from the late-delivery percentage denominator.
-- ============================================================4
SELECT
	YEAR(order_purchase_timestamp) as purchase_year,
	QUARTER(order_purchase_timestamp) as purchase_quarter,
    count(order_id) as delievered_orders,
    SUM(
    CASE
        WHEN order_delivered_customer_date IS NULL
          OR order_estimated_delivery_date IS NULL
        THEN 1
        ELSE 0
    END
) AS orders_missing_delivery_dates,
    sum(case when DATE(order_delivered_customer_date)
           > DATE(order_estimated_delivery_date) then 1 else 0 end)
		as late_delivery,
    ROUND(
    100.0 * SUM(
        CASE
            WHEN DATE(order_delivered_customer_date)
               > DATE(order_estimated_delivery_date)
            THEN 1 ELSE 0
        END
    )
    / NULLIF(
        SUM(
            CASE
                WHEN order_delivered_customer_date IS NOT NULL
                 AND order_estimated_delivery_date IS NOT NULL
                THEN 1 ELSE 0
            END
        ),
        0
    ),
    2
) AS percentage_of_late_deliveries
from orders
where order_purchase_timestamp >= '2017-04-01'
  AND order_purchase_timestamp <  '2018-07-01'
  AND order_status = 'delivered'
  group by 1,2;
  
  -- ============================================================
-- SECTION 3: SALES PERFORMANCE
-- 3.9 SEVERITY OF DELIVERY DELAYS
-- ============================================================
-- Question: For late delivered orders, how many days late
-- were they on average in each purchase quarter?
--
-- Scope: Orders purchased from 2017 Q2 through 2018 Q2.
-- Only delivered orders arriving after the estimated
-- delivery date are included, comparing calendar dates.
-- Orders missing either delivery date cannot qualify.
-- ============================================================

SELECT
    YEAR(order_purchase_timestamp) AS purchase_year,
    QUARTER(order_purchase_timestamp) AS purchase_quarter,
    COUNT(*) AS late_orders,
    ROUND(
        AVG(
            DATEDIFF(
                order_delivered_customer_date,
                order_estimated_delivery_date
            )
        ),
        2
    ) AS average_days_late
FROM orders
WHERE order_status = 'delivered'
  AND order_purchase_timestamp >= '2017-04-01'
  AND order_purchase_timestamp <  '2018-07-01'
  AND DATE(order_delivered_customer_date)
      > DATE(order_estimated_delivery_date)
GROUP BY purchase_year, purchase_quarter
ORDER BY purchase_year, purchase_quarter;

-- Finding: Among late delivered orders, average delay fell
-- from 11.19 days in 2018 Q1 to 8.87 days in 2018 Q2.
-- Over the same quarters, the late-delivery percentage
-- decreased from 12.88% to approximately 4.17%.
--
-- Delivery performance improved in both frequency and
-- average severity of delays. However, late orders in
-- 2018 Q2 still arrived almost nine days late on average.
--
-- Average days late includes only late delivered orders,
-- grouped by purchase quarter. It does not describe
-- the delay experienced by every order or identify causes.

-- ============================================================
-- SECTION 4: GEOGRAPHIC ANALYSIS
-- 4.1 DELIVERED ITEM SALES BY CUSTOMER STATE
-- ============================================================
-- Question: Which customer states contributed the most
-- delivered item sales value?
--
-- Purpose: Identify where sales are concentrated before
-- comparing delivery performance across states.
--
-- Measure: Sum of item prices for delivered orders,
-- excluding freight. State refers to the customer's location.
-- ============================================================

SELECT
	c.customer_state,
    sum(oi.price) as state_sales_value
FROM orders o
	join order_items oi on oi.order_id = o.order_id
    join products p on p.product_id = oi.product_id
    join customers c on c.customer_id = o.customer_id
where order_status = 'delivered'
group by 1
order by 2 desc;

-- ==================================================
-- 4.2 PERCENTAGE OF TOTAL SALES BY CUSTOMER STATE
-- ==================================================
-- Question: What percentage of total delivered item sales
-- does each customer state contribute?
-- Calculate each state's sales value divided by total sales,
-- multiplied by 100. Item sales value excludes freight.
With ma as (
SELECT
	c.customer_state,
    sum(oi.price) as state_sales_value
FROM orders o
	join order_items oi on oi.order_id = o.order_id
    join products p on p.product_id = oi.product_id
    join customers c on c.customer_id = o.customer_id
where order_status = 'delivered'
group by 1
order by 2 desc
),
MB AS (
SELECT
	SUM(state_sales_value) as total
FROM MA
)
SELECT
customer_state,
state_sales_value,
round(100*state_sales_value/total, 2) as Percentages
from ma
cross join mb
limit 10;

-- Finding: SP, RJ and MG together account for approximately
-- 63.38% of delivered item sales value across the dataset.
-- SP alone contributes 38.33%.

SELECT
	c.customer_state,
    count(distinct o.order_id) total_state_orders,
    COUNT(DISTINCT CASE
    WHEN DATE(o.order_delivered_customer_date)
       > DATE(o.order_estimated_delivery_date)
    THEN o.order_id
END) AS late_orders,
    ROUND(
    100.0 * COUNT(DISTINCT CASE
        WHEN DATE(o.order_delivered_customer_date)
           > DATE(o.order_estimated_delivery_date)
        THEN o.order_id
    END)
    / NULLIF(COUNT(DISTINCT o.order_id), 0),
    2
) AS percentage_late_orders
FROM orders o
    join customers c on c.customer_id = o.customer_id
where order_status = 'delivered'
group by 1
having count(distinct o.order_id) > 100
order by 4 desc;
