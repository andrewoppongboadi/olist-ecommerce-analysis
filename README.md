# Olist Brazilian E-commerce Analysis

A portfolio project using Python, pandas, and MySQL to investigate delivery performance, customer feedback, and sales in the Olist Brazilian e-commerce dataset.

## Project status

- Python data preparation: completed.
- SQL analysis: in progress; scripts will be added to this repository.

## Business questions

- How many orders were delivered, and how often were deliveries late?
- Which product categories receive the most low-score feedback?
- Which categories contribute the most delivered item sales value?
- How does delivered item sales value change over time?

## Data preparation

The Python script prepares nine related datasets for SQL analysis.

Tasks include:
- Inspecting missing values, data types, and duplicate identifiers.
- Converting date columns to datetime format.
- Checking relationships between tables.
- Flagging inconsistencies between order status and delivery dates.
- Standardizing customer and seller ZIP-code prefixes.
- Handling missing product categories and supplementing category translations.
- Inspecting repeated review records without automatically deleting them.
- Preparing a geolocation lookup with one row per ZIP-code prefix.
- Exporting cleaned CSV files for MySQL.

## Repository contents

- `olist_data_preparation.py`: data inspection, cleaning, validation, and export script.

## Tools

- Python and pandas
- MySQL and MySQL Workbench

## Running the Python script

The script requires Python, pandas, and the original Olist CSV files.

It currently uses local file paths. Update the input paths and output folder to match your computer before running:

`python olist_data_preparation.py`

Running the script prints validation results and writes cleaned CSV files to the configured output folder. Existing exports with the same filenames are overwritten.

## Data source

Brazilian E-Commerce Public Dataset by Olist, distributed through Kaggle.

The source CSV files are not included in this repository.

## Interpretation notes

Delivered item sales value is calculated from item prices, excluding freight. It is not profit or revenue adjusted for refunds and returns.

Reviews describe the order experience and cannot automatically be attributed to a particular product or seller.
