"""Olist data preparation and validation.

Workflow: load raw CSVs -> inspect and prepare each table -> export for SQL.
This reorganizes the existing analysis; it adds no new business analysis.
Printed checks must be reviewed: comments summarize previously recorded findings,
not independently verified results from this version.

Running this script reads the original Downloads CSV files and overwrites the
cleaned CSV exports in Downloads/olist_cleaned, matching the original workflow.
"""

from pathlib import Path

import pandas as pd

# ============================================================
# 1. LOAD SOURCE TABLES AND CREATE WORKING COPIES
# ============================================================

orders=pd.read_csv(r'/Users/andrewboadi/Downloads/olist_orders_dataset.csv')

orders_clean = orders.copy()

order_items=pd.read_csv(r'/Users/andrewboadi/Downloads/olist_order_items_dataset.csv')

order_items_clean = order_items.copy()

products=pd.read_csv(r'/Users/andrewboadi/Downloads/olist_products_dataset.csv')

products_clean = products.copy()

customers=pd.read_csv(r'/Users/andrewboadi/Downloads/olist_customers_dataset.csv')

customers_clean = customers.copy()

category_translations=pd.read_csv(r'/Users/andrewboadi/Downloads/product_category_name_translation.csv')

category_translations_clean = category_translations.copy()

order_payments = pd.read_csv(
    r"/Users/andrewboadi/Downloads/olist_order_payments_dataset.csv"
)

order_payments_clean = order_payments.copy()

order_reviews = pd.read_csv(
    r"/Users/andrewboadi/Downloads/olist_order_reviews_dataset.csv"
)

order_reviews_clean = order_reviews.copy()

sellers = pd.read_csv(
    r"/Users/andrewboadi/Downloads/olist_sellers_dataset.csv"
)

sellers_clean = sellers.copy()

geolocation = pd.read_csv(
    r"/Users/andrewboadi/Downloads/olist_geolocation_dataset.csv"
)

geolocation_clean = geolocation.copy()



# ============================================================
# 2. ORDERS: STRUCTURE, STATUS, DATES AND IDENTIFIERS
# ============================================================

print('Orders:', orders.shape)
print('Order Items:', order_items.shape)
print("Products:", products.shape)
print("Customers:", customers.shape)
print("Category translations:", category_translations.shape)
orders.info()
print(orders.isna().sum())
print(orders["order_status"].value_counts())
print(pd.crosstab(
    orders["order_status"],
    orders["order_delivered_customer_date"].isna()
))
suspicious_orders = orders[
    (
        (orders["order_status"] == "delivered")
        & (orders["order_delivered_customer_date"].isna())
    )
    |
    (
        (orders["order_status"] == "canceled")
        & (orders["order_delivered_customer_date"].notna())
    )
]
print(suspicious_orders[[
    "order_id",
    "order_status",
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date"
]])

# Create a flag for inconsistencies between status and delivery date
orders_clean["status_date_issue"] = (
    (
        (orders_clean["order_status"] == "delivered")
        & orders_clean["order_delivered_customer_date"].isna()
    )
    |
    (
        (orders_clean["order_status"] == "canceled")
        & orders_clean["order_delivered_customer_date"].notna()
    )
)

print(orders_clean["status_date_issue"].value_counts())

date_columns = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date"
]
orders_clean[date_columns]= orders_clean[date_columns].apply(pd.to_datetime, errors='coerce')
orders_clean.info()

print("Duplicate order IDs:")
print(orders_clean["order_id"].duplicated().sum())

print("Duplicate customer IDs:")
print(orders_clean["customer_id"].duplicated().sum())


# ============================================================
# 3. ORDER ITEMS: KEYS, VALUES AND TABLE RELATIONSHIPS
# ============================================================

# ============================================================
# ORDER ITEMS TABLE: INITIAL INSPECTION
# ============================================================

order_items_clean.info()

print("Missing values:")
print(order_items_clean.isna().sum())

order_items_clean["shipping_limit_date"] = pd.to_datetime(
    order_items_clean["shipping_limit_date"],
    errors="coerce"
)
print(
    order_items_clean["shipping_limit_date"].isna().sum()
)
print(order_items_clean["shipping_limit_date"].dtype)

print("Duplicate order item IDs:")
print(order_items_clean[["order_id", "order_item_id"]].duplicated().sum())
print(order_items_clean[['freight_value', 'price']].describe()) 
print('Freight Value is 0:')
print((order_items_clean['freight_value']==0).sum())
zero_freight_orders = order_items_clean[order_items_clean['freight_value']==0]
print(zero_freight_orders.head())
order_items_clean["free_shipping"] = order_items_clean["freight_value"] == 0
# 383 item rows have zero freight.
# Retained because zero freight may represent free shipping or a promotion.
# Added a zero-freight flag for later analysis.
# The flag does not establish why freight was zero.

orphaned_items = order_items_clean[
    ~order_items_clean['order_id'].isin(orders_clean['order_id'])]
print("Orphaned order items:")
print(orphaned_items)
# Every order_id in order_items_clean exists in orders_clean.
# No orphaned order-item rows were found.

orphaned_products = order_items_clean[
    ~order_items_clean["product_id"].isin(products_clean["product_id"])
]

print("Items without matching products:")
print(orphaned_products)


# ============================================================
# 4. PRODUCTS: IDENTIFIERS AND MISSING CATEGORIES
# ============================================================

# ==========================================================
# PRODUCTS TABLE: INITIAL INSPECTION
# ==========================================================

products_clean.info()

print("Missing values:")
print(products_clean.isna().sum())

print("Duplicate product IDs:")
print(products_clean["product_id"].duplicated().sum())
#
missing_product_details = products_clean[
    products_clean["product_category_name"].isna()
]

print(missing_product_details.head())
print("Products missing a category:", len(missing_product_details))

products_clean["product_category_name"] = products_clean["product_category_name"].fillna("unknown")

print(products_clean["product_category_name"].isna().sum())


# ============================================================
# 5. CUSTOMERS: IDENTIFIERS AND ZIP PREFIXES
# ============================================================

# ==========================================================
# CUSTOMERS TABLE: INITIAL INSPECTION
# ==========================================================

# Inspect row count, column names, non-null counts and data types.
customers_clean.info()

# Count missing values in every column.
print("Missing values:")
print(customers_clean.isna().sum())


# ==========================================================
# CUSTOMER ZIP-CODE PREFIX: INVESTIGATION
# ==========================================================

# Create a temporary string version of the ZIP-prefix column.
# This allows us to examine character lengths without changing
# the actual column yet.
zip_as_text = (
    customers_clean["customer_zip_code_prefix"]
    .astype(str)
)

# Count how many ZIP prefixes contain 4 or 5 characters.
print("ZIP-prefix lengths before cleaning:")
print(
    zip_as_text
    .str.len()
    .value_counts()
    .sort_index()
)

# Select customer rows whose ZIP prefix contains only 4 characters.
short_zip_codes = customers_clean[
    zip_as_text.str.len() == 4
]

# Inspect examples before making any changes.
print("Examples of four-character ZIP prefixes:")
print(short_zip_codes[[
    "customer_zip_code_prefix",
    "customer_city",
    "customer_state"
]].head(10))


# ==========================================================
# CUSTOMER ZIP-CODE PREFIX: CORRECTION
# ==========================================================

# Convert the actual column to text and add enough leading zeros
# to make every ZIP prefix 5 characters long.
customers_clean["customer_zip_code_prefix"] = (
    customers_clean["customer_zip_code_prefix"]
    .astype(str)
    .str.zfill(5)
)


# ==========================================================
# CUSTOMER ZIP-CODE PREFIX: VERIFICATION
# ==========================================================

# Check the lengths again after the correction.
print("ZIP-prefix lengths after cleaning:")
print(
    customers_clean["customer_zip_code_prefix"]
    .str.len()
    .value_counts()
    .sort_index()
)

# Inspect examples from the corrected table.
print("Examples after cleaning:")
print(customers_clean[[
    "customer_zip_code_prefix",
    "customer_city",
    "customer_state"
]].head(10))


# ==========================================================
# CUSTOMER IDENTIFIER CHECKS
# ==========================================================

# customer_id should be unique because it identifies the
# customer record associated with a particular order.
print("Duplicate customer IDs:")
print(
    customers_clean["customer_id"]
    .duplicated()
    .sum()
)

# Count order-specific customer records.
print("Number of customer IDs:")
print(customers_clean["customer_id"].nunique())

# Count distinct persistent customer identifiers.
# This can be smaller because the same identifier may place multiple orders.
print("Number of unique customer identifiers:")
print(customers_clean["customer_unique_id"].nunique())

# ==========================================================
# CUSTOMERS TABLE: FINAL VALIDATION
# ==========================================================

print("Number of rows:")
print(len(customers_clean))

print("Missing values:")
print(customers_clean.isna().sum())

print("Duplicate customer IDs:")
print(customers_clean["customer_id"].duplicated().sum())

print("Duplicate complete rows:")
print(customers_clean.duplicated().sum())

print("ZIP prefixes not exactly 5 characters:")
print(
    (
        customers_clean["customer_zip_code_prefix"]
        .str.len() != 5
    ).sum()
)

print("ZIP prefixes containing non-numeric characters:")
print(
    (
        ~customers_clean["customer_zip_code_prefix"]
        .str.fullmatch(r"\d{5}")
    ).sum()
)

print("Customer states:")
print(
    customers_clean["customer_state"]
    .value_counts()
    .sort_index()
)

# ============================================================
# 6. CATEGORY TRANSLATIONS: COVERAGE AND MANUAL ADDITIONS
# ============================================================

# ==========================================================
# CATEGORY TRANSLATION TABLE: INITIAL INSPECTION
# ==========================================================

category_translations_clean.info()

print("Missing values:")
print(category_translations_clean.isna().sum())

print("Duplicate Portuguese category names:")
print(
    category_translations_clean[
        "product_category_name"
    ].duplicated().sum()
)

print("Duplicate complete rows:")
print(category_translations_clean.duplicated().sum())

print("First ten translations:")
print(category_translations_clean.head(10))

# ==========================================================
# PRODUCTS-CATEGORY TRANSLATION RELATIONSHIP CHECK
# ==========================================================
products_without_translation = products_clean[(~products_clean["product_category_name"].isin(category_translations_clean["product_category_name"])) & (products_clean["product_category_name"] != "unknown")]

print("Products without an English category translation:")
print(len(products_without_translation))

print("Category names without translations:")
print(
    products_without_translation[
        "product_category_name"
    ]
    .drop_duplicates()
    .sort_values()
)
print(
    products_without_translation[
        "product_category_name"
    ].value_counts()
)
print(
    products_without_translation[
        "product_category_name"
    ].nunique()
)

# 13 products belong to two categories that are absent
# from the English category translation table:
# - pc_gamer
# - portateis_cozinha_e_preparadores_de_alimentos


missing_category_translations = pd.DataFrame({
    "product_category_name": [
        "pc_gamer",
        "portateis_cozinha_e_preparadores_de_alimentos"
    ],
    "product_category_name_english": [
        "pc_gaming",
        "portable_kitchen_food_preparers"
    ]
})

# Add two manually supplied English labels (not original source translations).
# Add the two new rows to the original 71-row working table
category_translations_clean = pd.concat(
    [
        category_translations_clean,
        missing_category_translations
    ],
    ignore_index=True
)

print("Translation table shape:")
print(category_translations_clean.shape)
print("Duplicate Portuguese category names:")
print(
    category_translations_clean[
        "product_category_name"
    ].duplicated().sum())


# ============================================================
# 7. PAYMENTS: STRUCTURE, VALUES AND RELATIONSHIPS
# ============================================================

# ============================================================
# ORDER PAYMENTS TABLE: INITIAL INSPECTION
# ============================================================

print("Order payments shape:")
print(order_payments_clean.shape)

order_payments_clean.info()

print("Missing values:")
print(order_payments_clean.isna().sum())

print("First five rows:")
print(order_payments_clean.head())

print("Duplicate order/payment sequence combinations:")  
print(order_payments_clean[['order_id', 'payment_sequential']].duplicated().sum())

# ============================================================
# ORDER PAYMENTS TABLE: PAYMENT DETAILS
# ============================================================

print("Payment types:")
print(order_payments_clean["payment_type"].value_counts())

print("Payment instalments:")
print(
    order_payments_clean[
        "payment_installments"
    ].value_counts().sort_index()
)
print("Payment-value summary:")
print(order_payments_clean["payment_value"].describe())

zero_installment_payments = order_payments_clean[
    order_payments_clean["payment_installments"] == 0
]
one_installment_payments = order_payments_clean[
    order_payments_clean["payment_installments"] == 1
]
print("Payments with zero instalments:")
print(zero_installment_payments)
print("Payments with one instalments:")
print(one_installment_payments.head(5))

# Flag payment records with an unusual zero instalment count
order_payments_clean["installment_issue"] = (
    order_payments_clean["payment_installments"] == 0
)

print(order_payments_clean["installment_issue"].value_counts())

orphaned_payments = order_payments_clean[
    ~order_payments_clean["order_id"].isin(
        orders_clean["order_id"]
    )
]

print("Payments without a matching order:")
print(len(orphaned_payments))

# Order payments cleaning summary:
# - No missing values found.
# - Each order_id/payment_sequential combination is unique.
# - Two records have zero instalments; retained and flagged.
# - Payment values retained without modification.
# - Checked that every payment belongs to a valid order.


# ============================================================
# 8. REVIEWS: SCORES, DATES AND REPEATED IDENTIFIERS
# ============================================================

# ============================================================
# ORDER REVIEWS TABLE: INITIAL INSPECTION
# ============================================================

print("Order reviews shape:")
print(order_reviews_clean.shape)

order_reviews_clean.info()

print("Missing values:")
print(order_reviews_clean.isna().sum())

print("First five rows:")
print(order_reviews_clean.head())

review_date_columns = [
    "review_creation_date",
    "review_answer_timestamp"
]

order_reviews_clean[review_date_columns] = (
    order_reviews_clean[review_date_columns]
    .apply(pd.to_datetime, errors="coerce")
)

# ============================================================
# ORDER REVIEWS TABLE: REVIEW SCORE CHECK
# ============================================================

print("Review-score distribution:")
print(
    order_reviews_clean["review_score"]
    .value_counts()
    .sort_index()
)
invalid_review_scores = order_reviews_clean[
    ~order_reviews_clean["review_score"].between(1, 5)
]

print("Reviews with scores outside 1–5")
print(len(invalid_review_scores))

print("Duplicate review IDs:")
print(order_reviews_clean["review_id"].duplicated().sum())

print("Duplicate order IDs:")
print(order_reviews_clean["order_id"].duplicated().sum())

print("Duplicate complete rows:")
print(
    order_reviews_clean
    .duplicated()
    .sum()
)

# ============================================================
# ORDER REVIEWS TABLE: INSPECT REPEATED REVIEW IDS
# ============================================================

duplicate_review_records = order_reviews_clean[
    order_reviews_clean["review_id"].duplicated(keep=False)
].sort_values(
    ["review_id", "review_answer_timestamp"]
)

print("Records with repeated review IDs:")
print(
    duplicate_review_records[[
        "review_id",
        "order_id",
        "review_score",
        "review_comment_title",
        "review_comment_message",
        "review_creation_date",
        "review_answer_timestamp"
    ]].head(20)
)

# ============================================================
# ORDER REVIEWS TABLE: INSPECT REPEATED ORDER IDS
# ============================================================

repeated_order_review_records = order_reviews_clean[
    order_reviews_clean["order_id"].duplicated(keep=False)
].sort_values(
    ["order_id", "review_answer_timestamp"]
)

print("Records with repeated order IDs:")
print(
    repeated_order_review_records[[
        "order_id",
        "review_id",
        "review_score",
        "review_comment_title",
        "review_comment_message",
        "review_creation_date",
        "review_answer_timestamp"
    ]].head(20)
)
# Interpretation of the recorded inspection:
# Some review IDs occur against multiple order IDs, and some orders
# have multiple review records. The reason has not been established.
# Repeated IDs alone do not establish that rows are duplicates.
# Retain these records; choose and document an order-level review
# rule in SQL (for example, average score or at least one poor review).


# ============================================================
# 9. SELLERS: IDENTIFIERS, ZIP PREFIXES AND RELATIONSHIPS
# ============================================================

# ============================================================
# SELLERS TABLE: INITIAL INSPECTION
# ============================================================

print("Sellers table shape:")
print(sellers_clean.shape)

sellers_clean.info()

print("Missing values:")
print(sellers_clean.isna().sum())

print("First five rows:")
print(sellers_clean.head())

seller_zip_as_text = sellers_clean['seller_zip_code_prefix'].astype(str)

print("Seller ZIP-code lengths:")
print(
    seller_zip_as_text
    .str.len()

    .value_counts()
    .sort_index()
)

short_seller_zips = sellers_clean[
    seller_zip_as_text.str.len() == 4
]

print("Examples of seller ZIP codes stored with four digits:")
print(
    short_seller_zips[[
        "seller_id",
        "seller_zip_code_prefix",
        "seller_city",
        "seller_state"
    ]].head(10)
)

sellers_clean["seller_zip_code_prefix"] = sellers_clean["seller_zip_code_prefix"].astype(str).str.zfill(5)

print("Seller ZIP-code lengths after cleaning:")
print(
    sellers_clean["seller_zip_code_prefix"]
    .str.len()
    .value_counts() #Verification of change.
)

# ============================================================
# SELLERS TABLE: SELLER ID CHECK
# ============================================================

print("Duplicate seller IDs:")
print(
    sellers_clean["seller_id"]
    .duplicated()
    .sum()
)

print("Number of seller records:")
print(len(sellers_clean))

print("Number of unique seller IDs:")
print(
    sellers_clean["seller_id"]
    .nunique()
)

# ============================================================
# SELLERS TABLE: RELATIONSHIP WITH ORDER ITEMS
# ============================================================

order_items_without_seller = order_items_clean[
    ~order_items_clean["seller_id"].isin(
        sellers_clean["seller_id"]
    )
]

print("Order-item rows without a matching seller:")
print(len(order_items_without_seller))

sellers_without_items = sellers_clean[
    ~sellers_clean["seller_id"].isin(
        order_items_clean["seller_id"]
    )
]

print("Sellers without any order items:")
print(len(sellers_without_items))


# ============================================================
# 10. GEOLOCATION: CLEANING, COVERAGE AND ZIP LOOKUP
# ============================================================

# ============================================================
# GEOLOCATION TABLE: INITIAL INSPECTION
# ============================================================

print("Geolocation table shape:")
print(geolocation_clean.shape)

geolocation_clean.info()

print("Missing values:")
print(geolocation_clean.isna().sum())

print("First five rows:")
print(geolocation_clean.head())

# ============================================================
# GEOLOCATION TABLE: ZIP-CODE INSPECTION
# ============================================================

geolocation_zip_as_text = geolocation_clean["geolocation_zip_code_prefix"].astype(str)

print("Geolocation ZIP-code lengths:")
print(
    geolocation_zip_as_text
    .str.len()
    .value_counts()
    .sort_index()
)

short_geolocation_zips = geolocation_clean[
    geolocation_zip_as_text.str.len() == 4
]

print("Examples of four-character geolocation ZIP prefixes:")
print(
    short_geolocation_zips[[
        "geolocation_zip_code_prefix",
        "geolocation_city",
        "geolocation_state"
    ]].head(10)
)

# Convert the ZIP prefix to text and restore leading zeros.
geolocation_clean["geolocation_zip_code_prefix"] = geolocation_clean["geolocation_zip_code_prefix"].astype(str).str.zfill(5)

# ============================================================
# GEOLOCATION TABLE: DUPLICATE INSPECTION
# ============================================================

print("Total geolocation rows:")
print(len(geolocation_clean))

print("Unique ZIP-code prefixes:")
print(
    geolocation_clean[
        "geolocation_zip_code_prefix"
    ].nunique()
)

print("Duplicate complete rows:")
print(
    geolocation_clean
    .duplicated()
    .sum()
)

# Remove rows that are identical in every column.
geolocation_clean = (
    geolocation_clean
    .drop_duplicates()
)

print("Geolocation shape after removing exact duplicates:")
print(geolocation_clean.shape)

print("Duplicate complete rows remaining:")
print(
    geolocation_clean
    .duplicated()
    .sum()
)

# ============================================================
# GEOLOCATION TABLE: COORDINATE INSPECTION
# ============================================================

print("Latitude and longitude summary:")
print(
    geolocation_clean[
        ["geolocation_lat", "geolocation_lng"]
    ].describe()
)


# Apply the existing approximate bounding-box screening rule.
# Coordinates inside this box are not necessarily inside Brazil;
# coordinates outside it are excluded from the location lookup only.
plausible_brazil_coordinates = geolocation_clean["geolocation_lat"].between(-34, 6) & geolocation_clean["geolocation_lng"].between(-75, -30)


# Select records outside those boundaries
invalid_coordinates = geolocation_clean[
    ~plausible_brazil_coordinates
]

print("Coordinates outside the expected Brazilian range:")
print(len(invalid_coordinates))

print(
    invalid_coordinates[
        [
            "geolocation_zip_code_prefix",
            "geolocation_lat",
            "geolocation_lng",
            "geolocation_city",
            "geolocation_state"
        ]
    ].sort_values("geolocation_zip_code_prefix")
)

geolocation_clean = geolocation_clean[
    plausible_brazil_coordinates
].copy()

# ============================================================
# GEOLOCATION TABLE: VERIFY COORDINATE CLEANING
# ============================================================

# Recalculate the condition using the cleaned table.
plausible_brazil_coordinates_after_cleaning = geolocation_clean["geolocation_lat"].between(-34, 6) & geolocation_clean["geolocation_lng"].between(-75, -30)

#Check whether any invalid coordinates remain.
invalid_coordinates_after_cleaning = geolocation_clean[
    ~plausible_brazil_coordinates_after_cleaning
]

print("Geolocation shape after removing invalid coordinates:")
print(geolocation_clean.shape)

print("Coordinates still outside the expected range:")
print(len(invalid_coordinates_after_cleaning))

# ============================================================
# GEOLOCATION TABLE: CUSTOMER AND SELLER ZIP-CODE COVERAGE
# ============================================================

# Find customer records whose ZIP prefixes do not appear
# in the cleaned geolocation table.
customers_without_geolocation = customers_clean[
    ~customers_clean["customer_zip_code_prefix"].isin(
        geolocation_clean["geolocation_zip_code_prefix"]
    )
]

print("Customer records without matching geolocation:")
print(len(customers_without_geolocation))

print("Unique customer ZIP prefixes without matching geolocation:")
print(
    customers_without_geolocation[
        "customer_zip_code_prefix"
    ].nunique()
)
# Find seller records whose ZIP prefixes do not appear
# in the cleaned geolocation table.
sellers_without_geolocation = sellers_clean[
    ~sellers_clean["seller_zip_code_prefix"].isin(
        geolocation_clean["geolocation_zip_code_prefix"]
    )
]

print("Seller records without matching geolocation:")
print(len(sellers_without_geolocation))

print("Unique seller ZIP prefixes without matching geolocation:")
print(
    sellers_without_geolocation[
        "seller_zip_code_prefix"
    ].nunique()
)

# ============================================================
# GEOLOCATION CLEANING: IMPACT ON SELLER MATCHES
# ============================================================

# Get the original geolocation ZIP prefixes before
# invalid coordinates were removed.
geolocation_zips_before_coordinate_cleaning = (
    geolocation["geolocation_zip_code_prefix"]
    .astype(str)
    .str.zfill(5)
)

# Get the ZIP prefixes remaining after coordinate cleaning.
geolocation_zips_after_coordinate_cleaning = (
    geolocation_clean["geolocation_zip_code_prefix"]
)

# Check whether each seller had a match before cleaning.
seller_had_match_before_cleaning = (
    sellers_clean["seller_zip_code_prefix"].isin(
        geolocation_zips_before_coordinate_cleaning
    )
)

# Check whether each seller has a match after cleaning.
seller_has_match_after_cleaning = (
    sellers_clean["seller_zip_code_prefix"].isin(
        geolocation_zips_after_coordinate_cleaning
    )
)

# Find sellers who had a match before but lost it after cleaning.
sellers_that_lost_geolocation = sellers_clean[
    seller_had_match_before_cleaning
    & ~seller_has_match_after_cleaning
]

print("Sellers that lost geolocation because of coordinate cleaning:")
print(len(sellers_that_lost_geolocation))

# ============================================================
# GEOLOCATION CLEANING: IMPACT ON CUSTOMER MATCHES
# ============================================================

customer_had_match_before_cleaning = (
    customers_clean["customer_zip_code_prefix"].isin(
        geolocation_zips_before_coordinate_cleaning
    )
)

customer_has_match_after_cleaning = (
    customers_clean["customer_zip_code_prefix"].isin(
        geolocation_zips_after_coordinate_cleaning
    )
)

customers_that_lost_geolocation = customers_clean[
    customer_had_match_before_cleaning
    & ~customer_has_match_after_cleaning
]

print("Customer records that lost geolocation because of coordinate cleaning:")
print(len(customers_that_lost_geolocation))

print("ZIP prefixes that lost geolocation:")
print(
    customers_that_lost_geolocation[
        "customer_zip_code_prefix"
    ].unique()
)

# ============================================================
# GEOLOCATION TABLE: CREATE ONE ROW PER ZIP PREFIX
# ============================================================

# Group records by ZIP prefix and calculate one representative
# latitude and longitude using the median.
geolocation_zip_lookup = geolocation_clean.groupby("geolocation_zip_code_prefix", as_index=False)[["geolocation_lat", "geolocation_lng"]].median()

# ============================================================
# GEOLOCATION ZIP LOOKUP: VERIFICATION
# ============================================================

print("Geolocation ZIP lookup shape:")
print(geolocation_zip_lookup.shape)

print("Number of unique ZIP prefixes:")
print(geolocation_zip_lookup["geolocation_zip_code_prefix"].nunique())

print("Duplicate ZIP prefixes:")
print(geolocation_zip_lookup["geolocation_zip_code_prefix"].duplicated().sum())

print("First five rows:")
print(geolocation_zip_lookup.head())


# ============================================================
# 11. FINAL INVENTORY
# ============================================================

# ============================================================
# FINAL CLEANED TABLE INVENTORY
# ============================================================

print("Orders:")
print(orders_clean.shape)

print("Order items:")
print(order_items_clean.shape)

print("Products:")
print(products_clean.shape)

print("Customers:")
print(customers_clean.shape)

print("Category translations:")
print(category_translations_clean.shape)

print("Order payments:")
print(order_payments_clean.shape)

print("Order reviews:")
print(order_reviews_clean.shape)

print("Sellers:")
print(sellers_clean.shape)

print("Geolocation ZIP lookup:")
print(geolocation_zip_lookup.shape)


# ============================================================
# 12. EXPORT CLEANED TABLES FOR SQL
# ============================================================

# ============================================================
# EXPORT CLEANED TABLES FOR SQL
# ============================================================


# Create a folder for the cleaned CSV files.
output_folder = Path(
    "/Users/andrewboadi/Downloads/olist_cleaned"
)

output_folder.mkdir(
    parents=True,
    exist_ok=True
)

# Export each cleaned table without the Pandas index.
orders_clean.to_csv(
    output_folder / "orders_clean.csv",
    index=False
)

order_items_clean.to_csv(
    output_folder / "order_items_clean.csv",
    index=False
)

products_clean.to_csv(
    output_folder / "products_clean.csv",
    index=False
)

customers_clean.to_csv(
    output_folder / "customers_clean.csv",
    index=False
)

category_translations_clean.to_csv(
    output_folder / "category_translations_clean.csv",
    index=False
)

order_payments_clean.to_csv(
    output_folder / "order_payments_clean.csv",
    index=False
)

order_reviews_clean.to_csv(
    output_folder / "order_reviews_clean.csv",
    index=False
)

sellers_clean.to_csv(
    output_folder / "sellers_clean.csv",
    index=False
)

geolocation_zip_lookup.to_csv(
    output_folder / "geolocation_zip_lookup.csv",
    index=False
)

print("Cleaned tables exported to:")
print(output_folder)