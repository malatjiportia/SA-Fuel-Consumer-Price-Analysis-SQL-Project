-- ================================================================
--  SA Fuel Prices & Cost-of-Living Analysis — COMPLETE SQL PROJECT
--  Months: 40  |  Provinces: 4  |  Jan 2021–April 2024
--  Records: 160 clean rows  |  Engine: MySQL
-- ==========================================================

-- ────────────────────────────────────────────────────────────
--  SECTION 1 — SCHEMA
-- ────────────────────────────────────────────────────────────

-- ── CLEANED table (normalised, typed, enriched) ─────────────
CREATE TABLE fuel_consumer_cleaned (
    record_id           INTEGER PRIMARY KEY,
    price_date          DATE        NOT NULL,          -- 2021-01-01 format
    month_year          VARCHAR(10) NOT NULL,          -- Jan-2021
    yr                  SMALLINT    NOT NULL,
    mo                  SMALLINT    NOT NULL,
    province            VARCHAR(50) NOT NULL,
    city                VARCHAR(50) NOT NULL,
    fuel_type           VARCHAR(20) NOT NULL,
    petrol_price        NUMERIC(6,2),
    diesel_price        NUMERIC(6,2),
    bread_price         NUMERIC(6,2),
    maize_meal_10kg     NUMERIC(6,2),
    chicken_1kg         NUMERIC(6,2),
    milk_1l             NUMERIC(6,2),
    eggs_6pack          NUMERIC(6,2),
    transport_fare      NUMERIC(6,2),
    cpi_index           NUMERIC(6,1),
    unemployment_pct    NUMERIC(4,1),
    -- Computed / enriched columns
    basic_basket_zar    NUMERIC(8,2) GENERATED ALWAYS AS (
                            bread_price +
                            ROUND(maize_meal_10kg / 4, 2) +
                            chicken_1kg +
                            milk_1l * 4 +
                            eggs_6pack
                        ) STORED,
    petrol_affordability NUMERIC(8,4) GENERATED ALWAYS AS (
                            CASE WHEN cpi_index > 0
                                 THEN ROUND(petrol_price / cpi_index * 100, 4)
                                 ELSE NULL END
                        ) STORED,
    period_flag         VARCHAR(40),
    data_note           TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- ── DATA QUALITY LOG ────────────────────────────────────────
CREATE TABLE data_quality_log (
    issue_id        SERIAL PRIMARY KEY,
    issue_number    SMALLINT,
    issue_type      VARCHAR(60),
    field_affected  VARCHAR(60),
    description     TEXT,
    records_affected INTEGER,
    action_taken    VARCHAR(20),
    resolution      TEXT,
    logged_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
--  SECTION 2 — DATA QUALITY LOG (issues found in raw CSV)
-- ============================================================

INSERT INTO data_quality_log
    (issue_number, issue_type, field_affected, description,
     records_affected, action_taken, resolution)
VALUES
(1, 'Date format inconsistency', 'month_year',
 'Three formats found: "Jan-2021" (standard), "February 2021" (full month name), '
 '"2021-03-01" (ISO date). Cannot sort or GROUP BY without normalisation.',
 3, 'FIXED',
 'All dates parsed to ISO DATE (YYYY-MM-01) + Mon-YYYY label using TO_DATE() in cleaning step.'),

(2, 'Province abbreviation', 'province',
 '"KZN" used instead of "KwaZulu-Natal" for Apr-2021 Durban row. '
 'Creates phantom province in GROUP BY and JOINs.',
 1, 'FIXED',
 'REPLACE / CASE statement: KZN → KwaZulu-Natal in cleaning CTE.'),

(3, 'City case inconsistencies', 'city',
 '"cape town" (Jun-2022) and "POLOKWANE" (Jul-2023) — wrong casing. '
 'DISTINCT and GROUP BY would produce duplicate city groups.',
 2, 'FIXED',
 'INITCAP(TRIM(city)) applied in cleaning CTE.'),

(4, 'Fuel type name — 4 variants', 'fuel_type',
 '"ULP 95", "Petrol 95", "95 Unleaded" all refer to same product. '
 '"ULP 93" is a redundant second entry for Johannesburg Jan-2021 only.',
 4, 'STANDARDISED',
 'CASE statement maps Petrol 95 / 95 Unleaded → ULP 95. ULP 93 row removed.'),

(5, 'Duplicate fuel type row (ULP 93)', 'fuel_type / city',
 'Johannesburg Jan-2021 has ULP 93 and ULP 95 rows. '
 'All 39 other months only have ULP 95. Skews city averages.',
 1, 'REMOVED',
 'WHERE fuel_type != ''ULP 93'' filter in cleaning CTE.'),

(6, 'Exact duplicate row', 'all columns',
 'Apr-2023 Gauteng/Johannesburg row appears twice. Notes says "DUPLICATE". '
 'Double-counts the month in all aggregations.',
 1, 'REMOVED',
 'ROW_NUMBER() PARTITION BY province, city, price_date, fuel_type — keep rn=1 only.'),

(7, 'Diesel price outlier — R99.85', 'diesel_price',
 'Mar-2022 Gauteng diesel = R99.85 (~5× normal range). '
 'Notes: "likely data entry error (cents entered as rands?)". '
 'Correct value ~R19.12 based on surrounding months.',
 1, 'CORRECTED',
 'CASE WHEN province=''Gauteng'' AND price_date=''2022-03-01'' AND diesel_price>50 '
 'THEN 19.12 ELSE diesel_price END in cleaning CTE.'),

(8, 'Missing petrol price', 'petrol_price',
 'Jul-2022 Limpopo petrol_price is NULL. Limpopo historically R0.13–R0.20 above Gauteng.',
 1, 'IMPUTED',
 'COALESCE with sub-select: Gauteng Jul-2022 price + 0.19 premium = R26.51.'),

(9, 'Numeric columns stored as text', 'all price columns',
 'CSV loaded all prices as VARCHAR. Cannot SUM/AVG without explicit cast.',
 11, 'FIXED',
 'CAST(... AS NUMERIC(6,2)) applied to all 11 numeric columns in cleaning CTE.');

SELECT `data_quality_log`.`issue_id`,
    `data_quality_log`.`issue_number`,
    `data_quality_log`.`issue_type`,
    `data_quality_log`.`field_affected`,
    `data_quality_log`.`description`,
    `data_quality_log`.`records_affected`,
    `data_quality_log`.`action_taken`,
    `data_quality_log`.`resolution`,
    `data_quality_log`.`logged_at`
FROM `sa fuel price`.`data_quality_log`;

-- ============================================================
--  SECTION 3 — LOAD CLEANED DATA
-- ============================================================
-- NOTE: In a real pipeline you would COPY FROM CSV into fuel_consumer_raw,
-- then run the cleaning CTE in Section 4.
-- Here we INSERT the already-cleaned & enriched rows directly for portability.

INSERT INTO fuel_consumer_cleaned
    (record_id, price_date, month_year, yr, mo,
     province, city, fuel_type,
     petrol_price, diesel_price, bread_price, maize_meal_10kg,
     chicken_1kg, milk_1l, eggs_6pack,
     transport_fare, cpi_index, unemployment_pct,
     period_flag, data_note)
VALUES
    ('1', '2021-01-01', 'Jan-2021', '2021', '1', 'Gauteng', 'Johannesburg', 'ULP 95', 15.09, 13.19, 14.99, 68.99, 39.99, 49.99, 17.49, 19.99, 12.0, 116.2, 32.5, ''),
    ('2', '2021-01-01', 'Jan-2021', '2021', '1', 'Limpopo', 'Polokwane', 'ULP 95', 15.22, 13.29, 15.49, 70.99, 41.99, 51.99, 17.99, 20.49, 10.0, 116.2, 32.5, ''),
    ('3', '2021-01-01', 'Jan-2021', '2021', '1', 'Western Cape', 'Cape Town', 'ULP 95', 15.09, 13.19, 15.99, 72.99, 40.99, 52.99, 18.49, 21.99, 13.5, 116.2, 32.5, ''),
    ('4', '2021-01-01', 'Jan-2021', '2021', '1', 'KwaZulu-Natal', 'Durban', 'ULP 95', 15.09, 13.19, 14.49, 67.99, 38.99, 48.99, 17.29, 19.49, 11.5, 116.2, 32.5, ''),
    ('5', '2021-02-01', 'Feb-2021', '2021', '2', 'Gauteng', 'Johannesburg', 'ULP 95', 14.98, 13.05, 14.99, 68.99, 39.99, 49.99, 17.49, 19.99, 12.0, 116.8, 32.5, 'Date format inconsistency'),
    ('6', '2021-02-01', 'Feb-2021', '2021', '2', 'Limpopo', 'Polokwane', 'ULP 95', 15.11, 13.15, 15.49, 70.99, 41.99, 51.99, 17.99, 20.49, 10.0, 116.8, 32.5, ''),
    ('7', '2021-02-01', 'Feb-2021', '2021', '2', 'Western Cape', 'Cape Town', 'ULP 95', 14.98, 13.05, 15.99, 72.99, 40.99, 52.99, 18.49, 21.99, 13.5, 116.8, 32.5, ''),
    ('8', '2021-02-01', 'Feb-2021', '2021', '2', 'KwaZulu-Natal', 'Durban', 'ULP 95', 14.98, 13.05, 14.49, 67.99, 38.99, 48.99, 17.29, 19.49, 11.5, 116.8, 32.5, ''),
    ('9', '2021-03-01', 'Mar-2021', '2021', '3', 'Gauteng', 'Johannesburg', 'ULP 95', 15.36, 13.42, 14.99, 68.99, 39.99, 51.99, 17.49, 20.49, 12.0, 117.4, 32.6, 'Another date format'),
    ('10', '2021-03-01', 'Mar-2021', '2021', '3', 'Limpopo', 'Polokwane', 'ULP 95', 15.5, 13.52, 15.49, 71.99, 41.99, 53.99, 17.99, 20.99, 10.0, 117.4, 32.6, ''),
    ('11', '2021-03-01', 'Mar-2021', '2021', '3', 'Western Cape', 'Cape Town', 'ULP 95', 15.36, 13.42, 15.99, 73.99, 40.99, 54.99, 18.49, 22.49, 13.5, 117.4, 32.6, ''),
    ('12', '2021-03-01', 'Mar-2021', '2021', '3', 'KwaZulu-Natal', 'Durban', 'ULP 95', 15.36, 13.42, 14.49, 67.99, 38.99, 50.99, 17.29, 19.99, 11.5, 117.4, 32.6, ''),
    ('13', '2021-04-01', 'Apr-2021', '2021', '4', 'Gauteng', 'Johannesburg', 'ULP 95', 15.84, 13.88, 14.99, 69.99, 40.99, 51.99, 17.49, 20.49, 12.0, 117.9, 32.6, ''),
    ('14', '2021-04-01', 'Apr-2021', '2021', '4', 'Limpopo', 'Polokwane', 'ULP 95', 15.98, 13.98, 15.49, 71.99, 42.99, 53.99, 17.99, 20.99, 10.0, 117.9, 32.6, ''),
    ('15', '2021-04-01', 'Apr-2021', '2021', '4', 'Western Cape', 'Cape Town', 'ULP 95', 15.84, 13.88, 15.99, 73.99, 41.99, 54.99, 18.49, 22.49, 13.5, 117.9, 32.6, ''),
    ('16', '2021-04-01', 'Apr-2021', '2021', '4', 'KwaZulu-Natal', 'Durban', 'ULP 95', 15.84, 13.88, 14.49, 68.99, 39.99, 50.99, 17.29, 19.99, 11.5, 117.9, 32.6, 'Province abbreviation inconsistency'),
    ('17', '2021-05-01', 'May-2021', '2021', '5', 'Gauteng', 'Johannesburg', 'ULP 95', 16.01, 14.02, 14.99, 69.99, 40.99, 51.99, 17.49, 20.49, 12.0, 118.3, 32.6, ''),
    ('18', '2021-05-01', 'May-2021', '2021', '5', 'Limpopo', 'Polokwane', 'ULP 95', 16.15, 14.12, 15.49, 71.99, 42.99, 53.99, 17.99, 20.99, 10.0, 118.3, 32.6, ''),
    ('19', '2021-05-01', 'May-2021', '2021', '5', 'Western Cape', 'Cape Town', 'ULP 95', 16.01, 14.02, 15.99, 73.99, 41.99, 54.99, 18.49, 22.49, 13.5, 118.3, 32.6, ''),
    ('20', '2021-05-01', 'May-2021', '2021', '5', 'KwaZulu-Natal', 'Durban', 'ULP 95', 16.01, 14.02, 14.49, 68.99, 39.99, 50.99, 17.29, 19.99, 11.5, 118.3, 32.6, ''),
    ('21', '2021-06-01', 'Jun-2021', '2021', '6', 'Gauteng', 'Johannesburg', 'ULP 95', 17.1, 14.98, 15.49, 70.99, 41.99, 53.99, 17.99, 21.49, 12.5, 118.9, 34.4, 'Large fuel price increase - load shedding period'),
    ('22', '2021-06-01', 'Jun-2021', '2021', '6', 'Limpopo', 'Polokwane', 'ULP 95', 17.25, 15.09, 15.99, 72.99, 43.99, 55.99, 18.49, 21.99, 10.5, 118.9, 34.4, ''),
    ('23', '2021-06-01', 'Jun-2021', '2021', '6', 'Western Cape', 'Cape Town', 'ULP 95', 17.1, 14.98, 16.49, 74.99, 42.99, 56.99, 18.99, 23.49, 14.0, 118.9, 34.4, ''),
    ('24', '2021-06-01', 'Jun-2021', '2021', '6', 'KwaZulu-Natal', 'Durban', 'ULP 95', 17.1, 14.98, 14.99, 69.99, 40.99, 52.99, 17.79, 20.49, 12.0, 118.9, 34.4, ''),
    ('25', '2021-07-01', 'Jul-2021', '2021', '7', 'Gauteng', 'Johannesburg', 'ULP 95', 17.48, 15.28, 15.49, 70.99, 41.99, 53.99, 17.99, 21.49, 12.5, 119.3, 34.4, 'Fuel type name inconsistency'),
    ('26', '2021-07-01', 'Jul-2021', '2021', '7', 'Limpopo', 'Polokwane', 'ULP 95', 17.63, 15.39, 15.99, 72.99, 43.99, 55.99, 18.49, 21.99, 10.5, 119.3, 34.4, ''),
    ('27', '2021-07-01', 'Jul-2021', '2021', '7', 'Western Cape', 'Cape Town', 'ULP 95', 17.48, 15.28, 16.49, 74.99, 42.99, 56.99, 18.99, 23.49, 14.0, 119.3, 34.4, ''),
    ('28', '2021-07-01', 'Jul-2021', '2021', '7', 'KwaZulu-Natal', 'Durban', 'ULP 95', 17.48, 15.28, 14.99, 69.99, 40.99, 52.99, 17.79, 20.49, 12.0, 119.3, 34.4, ''),
    ('29', '2021-08-01', 'Aug-2021', '2021', '8', 'Gauteng', 'Johannesburg', 'ULP 95', 17.8, 15.61, 15.49, 71.99, 42.99, 55.99, 18.49, 21.99, 12.5, 119.9, 34.9, ''),
    ('30', '2021-08-01', 'Aug-2021', '2021', '8', 'Limpopo', 'Polokwane', 'ULP 95', 17.95, 15.72, 15.99, 73.99, 44.99, 57.99, 18.99, 22.49, 10.5, 119.9, 34.9, ''),
    ('31', '2021-08-01', 'Aug-2021', '2021', '8', 'Western Cape', 'Cape Town', 'ULP 95', 17.8, 15.61, 16.49, 75.99, 43.99, 57.99, 19.49, 23.99, 14.0, 119.9, 34.9, ''),
    ('32', '2021-08-01', 'Aug-2021', '2021', '8', 'KwaZulu-Natal', 'Durban', 'ULP 95', 17.8, 15.61, 14.99, 70.99, 41.99, 53.99, 17.99, 20.99, 12.0, 119.9, 34.9, ''),
    ('33', '2021-09-01', 'Sep-2021', '2021', '9', 'Gauteng', 'Johannesburg', 'ULP 95', 18.22, 16.0, 15.99, 71.99, 42.99, 55.99, 18.49, 21.99, 13.0, 120.4, 34.9, ''),
    ('34', '2021-09-01', 'Sep-2021', '2021', '9', 'Limpopo', 'Polokwane', 'ULP 95', 18.38, 16.11, 16.49, 73.99, 44.99, 57.99, 18.99, 22.49, 11.0, 120.4, 34.9, ''),
    ('35', '2021-09-01', 'Sep-2021', '2021', '9', 'Western Cape', 'Cape Town', 'ULP 95', 18.22, 16.0, 16.99, 75.99, 43.99, 58.99, 19.49, 23.99, 14.5, 120.4, 34.9, ''),
    ('36', '2021-09-01', 'Sep-2021', '2021', '9', 'KwaZulu-Natal', 'Durban', 'ULP 95', 18.22, 16.0, 15.49, 70.99, 41.99, 54.99, 17.99, 20.99, 12.0, 120.4, 34.9, ''),
    ('37', '2021-10-01', 'Oct-2021', '2021', '10', 'Gauteng', 'Johannesburg', 'ULP 95', 18.68, 16.39, 15.99, 72.99, 43.99, 56.99, 18.49, 22.49, 13.0, 121.0, 35.3, ''),
    ('38', '2021-10-01', 'Oct-2021', '2021', '10', 'Limpopo', 'Polokwane', 'ULP 95', 18.84, 16.5, 16.49, 74.99, 45.99, 58.99, 18.99, 22.99, 11.0, 121.0, 35.3, ''),
    ('39', '2021-10-01', 'Oct-2021', '2021', '10', 'Western Cape', 'Cape Town', 'ULP 95', 18.68, 16.39, 16.99, 76.99, 44.99, 59.99, 19.49, 24.49, 14.5, 121.0, 35.3, ''),
    ('40', '2021-10-01', 'Oct-2021', '2021', '10', 'KwaZulu-Natal', 'Durban', 'ULP 95', 18.68, 16.39, 15.49, 71.99, 42.99, 55.99, 18.49, 21.49, 12.0, 121.0, 35.3, ''),
    ('41', '2021-11-01', 'Nov-2021', '2021', '11', 'Gauteng', 'Johannesburg', 'ULP 95', 19.12, 16.8, 15.99, 72.99, 43.99, 56.99, 18.49, 22.49, 13.0, 121.5, 35.3, ''),
    ('42', '2021-11-01', 'Nov-2021', '2021', '11', 'Limpopo', 'Polokwane', 'ULP 95', 19.28, 16.91, 16.49, 74.99, 45.99, 58.99, 18.99, 22.99, 11.0, 121.5, 35.3, ''),
    ('43', '2021-11-01', 'Nov-2021', '2021', '11', 'Western Cape', 'Cape Town', 'ULP 95', 19.12, 16.8, 16.99, 76.99, 44.99, 59.99, 19.49, 24.49, 14.5, 121.5, 35.3, ''),
    ('44', '2021-11-01', 'Nov-2021', '2021', '11', 'KwaZulu-Natal', 'Durban', 'ULP 95', 19.12, 16.8, 15.49, 71.99, 42.99, 55.99, 18.49, 21.49, 12.0, 121.5, 35.3, ''),
    ('45', '2021-12-01', 'Dec-2021', '2021', '12', 'Gauteng', 'Johannesburg', 'ULP 95', 19.52, 17.14, 16.49, 74.99, 45.99, 62.99, 19.49, 24.49, 13.0, 122.2, 35.3, 'December festive premium'),
    ('46', '2021-12-01', 'Dec-2021', '2021', '12', 'Limpopo', 'Polokwane', 'ULP 95', 19.68, 17.26, 16.99, 76.99, 47.99, 64.99, 19.99, 24.99, 11.0, 122.2, 35.3, ''),
    ('47', '2021-12-01', 'Dec-2021', '2021', '12', 'Western Cape', 'Cape Town', 'ULP 95', 19.52, 17.14, 17.49, 78.99, 46.99, 65.99, 20.49, 26.49, 15.0, 122.2, 35.3, ''),
    ('48', '2021-12-01', 'Dec-2021', '2021', '12', 'KwaZulu-Natal', 'Durban', 'ULP 95', 19.52, 17.14, 15.99, 73.99, 44.99, 60.99, 19.49, 22.99, 12.5, 122.2, 35.3, ''),
    ('49', '2022-01-01', 'Jan-2022', '2022', '1', 'Gauteng', 'Johannesburg', 'ULP 95', 19.84, 17.41, 16.49, 74.99, 45.99, 62.99, 19.49, 24.49, 13.0, 123.0, 35.7, ''),
    ('50', '2022-01-01', 'Jan-2022', '2022', '1', 'Limpopo', 'Polokwane', 'ULP 95', 20.0, 17.53, 16.99, 76.99, 47.99, 64.99, 19.99, 24.99, 11.0, 123.0, 35.7, ''),
    ('51', '2022-01-01', 'Jan-2022', '2022', '1', 'Western Cape', 'Cape Town', 'ULP 95', 19.84, 17.41, 17.49, 78.99, 46.99, 65.99, 20.49, 26.49, 15.0, 123.0, 35.7, ''),
    ('52', '2022-01-01', 'Jan-2022', '2022', '1', 'KwaZulu-Natal', 'Durban', 'ULP 95', 19.84, 17.41, 15.99, 73.99, 44.99, 60.99, 19.49, 22.99, 12.5, 123.0, 35.7, ''),
    ('53', '2022-02-01', 'Feb-2022', '2022', '2', 'Gauteng', 'Johannesburg', 'ULP 95', 20.48, 17.98, 16.99, 75.99, 46.99, 63.99, 19.99, 24.99, 13.0, 123.9, 35.7, ''),
    ('54', '2022-02-01', 'Feb-2022', '2022', '2', 'Limpopo', 'Polokwane', 'ULP 95', 20.65, 18.1, 17.49, 77.99, 48.99, 65.99, 20.49, 25.49, 11.0, 123.9, 35.7, ''),
    ('55', '2022-02-01', 'Feb-2022', '2022', '2', 'Western Cape', 'Cape Town', 'ULP 95', 20.48, 17.98, 17.99, 79.99, 47.99, 66.99, 20.99, 26.99, 15.0, 123.9, 35.7, ''),
    ('56', '2022-02-01', 'Feb-2022', '2022', '2', 'KwaZulu-Natal', 'Durban', 'ULP 95', 20.48, 17.98, 16.49, 74.99, 45.99, 61.99, 19.99, 23.49, 12.5, 123.9, 35.7, ''),
    ('57', '2022-03-01', 'Mar-2022', '2022', '3', 'Gauteng', 'Johannesburg', 'ULP 95', 21.6, 19.12, 16.99, 76.99, 47.99, 64.99, 20.49, 25.49, 13.5, 124.9, 35.7, 'Diesel price outlier - likely data entry error (cents entered as rands?)'),
    ('58', '2022-03-01', 'Mar-2022', '2022', '3', 'Limpopo', 'Polokwane', 'ULP 95', 21.78, 19.12, 17.49, 78.99, 49.99, 66.99, 20.99, 25.99, 11.5, 124.9, 35.7, ''),
    ('59', '2022-03-01', 'Mar-2022', '2022', '3', 'Western Cape', 'Cape Town', 'ULP 95', 21.6, 18.98, 17.99, 80.99, 48.99, 67.99, 21.49, 27.49, 15.5, 124.9, 35.7, ''),
    ('60', '2022-03-01', 'Mar-2022', '2022', '3', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.6, 18.98, 16.49, 75.99, 46.99, 62.99, 20.49, 23.99, 13.0, 124.9, 35.7, ''),
    ('61', '2022-04-01', 'Apr-2022', '2022', '4', 'Gauteng', 'Johannesburg', 'ULP 95', 23.38, 20.52, 17.49, 77.99, 48.99, 65.99, 20.49, 25.49, 13.5, 126.1, 35.3, 'Russia-Ukraine war impact on fuel'),
    ('62', '2022-04-01', 'Apr-2022', '2022', '4', 'Limpopo', 'Polokwane', 'ULP 95', 23.57, 20.65, 17.99, 79.99, 50.99, 67.99, 20.99, 25.99, 11.5, 126.1, 35.3, ''),
    ('63', '2022-04-01', 'Apr-2022', '2022', '4', 'Western Cape', 'Cape Town', 'ULP 95', 23.38, 20.52, 18.49, 81.99, 49.99, 68.99, 21.49, 27.49, 15.5, 126.1, 35.3, ''),
    ('64', '2022-04-01', 'Apr-2022', '2022', '4', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.38, 20.52, 16.99, 76.99, 47.99, 63.99, 20.49, 24.49, 13.0, 126.1, 35.3, ''),
    ('65', '2022-05-01', 'May-2022', '2022', '5', 'Gauteng', 'Johannesburg', 'ULP 95', 23.38, 20.52, 17.49, 77.99, 48.99, 65.99, 20.49, 25.49, 13.5, 127.1, 35.3, ''),
    ('66', '2022-05-01', 'May-2022', '2022', '5', 'Limpopo', 'Polokwane', 'ULP 95', 23.57, 20.65, 17.99, 79.99, 50.99, 67.99, 20.99, 25.99, 11.5, 127.1, 35.3, ''),
    ('67', '2022-05-01', 'May-2022', '2022', '5', 'Western Cape', 'Cape Town', 'ULP 95', 23.38, 20.52, 18.49, 81.99, 49.99, 68.99, 21.49, 27.49, 15.5, 127.1, 35.3, ''),
    ('68', '2022-05-01', 'May-2022', '2022', '5', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.38, 20.52, 16.99, 76.99, 47.99, 63.99, 20.49, 24.49, 13.0, 127.1, 35.3, ''),
    ('69', '2022-06-01', 'Jun-2022', '2022', '6', 'Gauteng', 'Johannesburg', 'ULP 95', 25.99, 22.98, 17.99, 79.99, 50.99, 67.99, 21.49, 26.49, 14.0, 128.6, 33.9, 'Record high fuel price'),
    ('70', '2022-06-01', 'Jun-2022', '2022', '6', 'Limpopo', 'Polokwane', 'ULP 95', 26.19, 23.12, 18.49, 81.99, 52.99, 69.99, 21.99, 26.99, 12.0, 128.6, 33.9, ''),
    ('71', '2022-06-01', 'Jun-2022', '2022', '6', 'Western Cape', 'Cape Town', 'ULP 95', 25.99, 22.98, 18.99, 83.99, 51.99, 70.99, 22.49, 28.49, 16.0, 128.6, 33.9, 'City not capitalised'),
    ('72', '2022-06-01', 'Jun-2022', '2022', '6', 'KwaZulu-Natal', 'Durban', 'ULP 95', 25.99, 22.98, 17.49, 78.99, 49.99, 65.99, 21.49, 25.49, 13.5, 128.6, 33.9, ''),
    ('73', '2022-07-01', 'Jul-2022', '2022', '7', 'Gauteng', 'Johannesburg', 'ULP 95', 26.32, 23.27, 17.99, 79.99, 51.99, 67.99, 21.49, 26.49, 14.0, 129.3, 33.9, ''),
    ('74', '2022-07-01', 'Jul-2022', '2022', '7', 'Limpopo', 'Polokwane', 'ULP 95', 26.51, 23.41, 18.49, 81.99, 52.99, 69.99, 21.99, 26.99, 12.0, 129.3, 33.9, 'Missing petrol price'),
    ('75', '2022-07-01', 'Jul-2022', '2022', '7', 'Western Cape', 'Cape Town', 'ULP 95', 26.32, 23.27, 18.99, 83.99, 51.99, 71.99, 22.49, 28.49, 16.0, 129.3, 33.9, ''),
    ('76', '2022-07-01', 'Jul-2022', '2022', '7', 'KwaZulu-Natal', 'Durban', 'ULP 95', 26.32, 23.27, 17.49, 78.99, 49.99, 65.99, 21.49, 25.49, 13.5, 129.3, 33.9, ''),
    ('77', '2022-08-01', 'Aug-2022', '2022', '8', 'Gauteng', 'Johannesburg', 'ULP 95', 24.17, 21.38, 17.99, 80.99, 51.99, 68.99, 21.99, 26.49, 14.0, 130.0, 33.9, 'Fuel decrease after record high'),
    ('78', '2022-08-01', 'Aug-2022', '2022', '8', 'Limpopo', 'Polokwane', 'ULP 95', 24.35, 21.51, 18.49, 82.99, 53.99, 70.99, 22.49, 26.99, 12.0, 130.0, 33.9, ''),
    ('79', '2022-08-01', 'Aug-2022', '2022', '8', 'Western Cape', 'Cape Town', 'ULP 95', 24.17, 21.38, 18.99, 84.99, 52.99, 72.99, 22.99, 28.99, 16.0, 130.0, 33.9, ''),
    ('80', '2022-08-01', 'Aug-2022', '2022', '8', 'KwaZulu-Natal', 'Durban', 'ULP 95', 24.17, 21.38, 17.49, 79.99, 50.99, 66.99, 21.99, 25.99, 13.5, 130.0, 33.9, ''),
    ('81', '2022-09-01', 'Sep-2022', '2022', '9', 'Gauteng', 'Johannesburg', 'ULP 95', 23.59, 20.88, 18.49, 80.99, 52.99, 69.99, 22.49, 26.99, 14.0, 130.8, 33.9, ''),
    ('82', '2022-09-01', 'Sep-2022', '2022', '9', 'Limpopo', 'Polokwane', 'ULP 95', 23.77, 21.01, 18.99, 82.99, 54.99, 71.99, 22.99, 27.49, 12.0, 130.8, 33.9, ''),
    ('83', '2022-09-01', 'Sep-2022', '2022', '9', 'Western Cape', 'Cape Town', 'ULP 95', 23.59, 20.88, 19.49, 84.99, 53.99, 72.99, 23.49, 29.49, 16.0, 130.8, 33.9, ''),
    ('84', '2022-09-01', 'Sep-2022', '2022', '9', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.59, 20.88, 17.99, 79.99, 51.99, 67.99, 22.49, 26.49, 13.5, 130.8, 33.9, ''),
    ('85', '2022-10-01', 'Oct-2022', '2022', '10', 'Gauteng', 'Johannesburg', 'ULP 95', 22.8, 20.19, 18.49, 82.99, 53.99, 70.99, 22.49, 27.49, 14.5, 131.6, 33.5, ''),
    ('86', '2022-10-01', 'Oct-2022', '2022', '10', 'Limpopo', 'Polokwane', 'ULP 95', 22.98, 20.32, 18.99, 84.99, 55.99, 72.99, 22.99, 27.99, 12.5, 131.6, 33.5, ''),
    ('87', '2022-10-01', 'Oct-2022', '2022', '10', 'Western Cape', 'Cape Town', 'ULP 95', 22.8, 20.19, 19.49, 86.99, 54.99, 73.99, 23.49, 29.99, 16.5, 131.6, 33.5, ''),
    ('88', '2022-10-01', 'Oct-2022', '2022', '10', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.8, 20.19, 17.99, 81.99, 52.99, 68.99, 22.49, 26.99, 14.0, 131.6, 33.5, ''),
    ('89', '2022-11-01', 'Nov-2022', '2022', '11', 'Gauteng', 'Johannesburg', 'ULP 95', 21.8, 19.3, 18.99, 82.99, 53.99, 70.99, 22.99, 27.49, 14.5, 132.3, 33.5, ''),
    ('90', '2022-11-01', 'Nov-2022', '2022', '11', 'Limpopo', 'Polokwane', 'ULP 95', 21.98, 19.43, 19.49, 84.99, 55.99, 72.99, 23.49, 27.99, 12.5, 132.3, 33.5, ''),
    ('91', '2022-11-01', 'Nov-2022', '2022', '11', 'Western Cape', 'Cape Town', 'ULP 95', 21.8, 19.3, 19.99, 86.99, 54.99, 74.99, 23.99, 30.49, 16.5, 132.3, 33.5, ''),
    ('92', '2022-11-01', 'Nov-2022', '2022', '11', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.8, 19.3, 18.49, 81.99, 52.99, 69.99, 22.99, 27.49, 14.0, 132.3, 33.5, ''),
    ('93', '2022-12-01', 'Dec-2022', '2022', '12', 'Gauteng', 'Johannesburg', 'ULP 95', 21.6, 19.12, 19.49, 84.99, 55.99, 75.99, 23.49, 28.99, 14.5, 132.9, 33.5, ''),
    ('94', '2022-12-01', 'Dec-2022', '2022', '12', 'Limpopo', 'Polokwane', 'ULP 95', 21.78, 19.25, 19.99, 86.99, 57.99, 77.99, 23.99, 29.49, 12.5, 132.9, 33.5, ''),
    ('95', '2022-12-01', 'Dec-2022', '2022', '12', 'Western Cape', 'Cape Town', 'ULP 95', 21.6, 19.12, 20.49, 88.99, 56.99, 78.99, 24.49, 31.49, 17.0, 132.9, 33.5, ''),
    ('96', '2022-12-01', 'Dec-2022', '2022', '12', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.6, 19.12, 18.99, 83.99, 54.99, 74.99, 23.99, 28.49, 14.5, 132.9, 33.5, ''),
    ('97', '2023-01-01', 'Jan-2023', '2023', '1', 'Gauteng', 'Johannesburg', 'ULP 95', 21.09, 18.68, 19.49, 84.99, 55.99, 75.99, 23.99, 28.99, 15.0, 133.8, 32.9, ''),
    ('98', '2023-01-01', 'Jan-2023', '2023', '1', 'Limpopo', 'Polokwane', 'ULP 95', 21.27, 18.81, 19.99, 86.99, 57.99, 77.99, 24.49, 29.49, 13.0, 133.8, 32.9, ''),
    ('99', '2023-01-01', 'Jan-2023', '2023', '1', 'Western Cape', 'Cape Town', 'ULP 95', 21.09, 18.68, 20.49, 88.99, 56.99, 78.99, 24.99, 31.49, 17.0, 133.8, 32.9, ''),
    ('100', '2023-01-01', 'Jan-2023', '2023', '1', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.09, 18.68, 18.99, 83.99, 54.99, 74.99, 24.49, 28.49, 15.0, 133.8, 32.9, ''),
    ('101', '2023-02-01', 'Feb-2023', '2023', '2', 'Gauteng', 'Johannesburg', 'ULP 95', 21.08, 18.66, 19.49, 85.99, 56.99, 76.99, 24.49, 29.49, 15.0, 134.6, 32.9, ''),
    ('102', '2023-02-01', 'Feb-2023', '2023', '2', 'Limpopo', 'Polokwane', 'ULP 95', 21.26, 18.79, 19.99, 87.99, 58.99, 78.99, 24.99, 29.99, 13.0, 134.6, 32.9, ''),
    ('103', '2023-02-01', 'Feb-2023', '2023', '2', 'Western Cape', 'Cape Town', 'ULP 95', 21.08, 18.66, 20.49, 89.99, 57.99, 79.99, 25.49, 31.99, 17.0, 134.6, 32.9, ''),
    ('104', '2023-02-01', 'Feb-2023', '2023', '2', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.08, 18.66, 18.99, 84.99, 55.99, 75.99, 24.99, 28.99, 15.0, 134.6, 32.9, ''),
    ('105', '2023-03-01', 'Mar-2023', '2023', '3', 'Gauteng', 'Johannesburg', 'ULP 95', 22.38, 19.82, 19.99, 85.99, 57.99, 76.99, 24.99, 29.49, 15.0, 135.2, 32.9, ''),
    ('106', '2023-03-01', 'Mar-2023', '2023', '3', 'Limpopo', 'Polokwane', 'ULP 95', 22.57, 19.95, 20.49, 87.99, 59.99, 78.99, 25.49, 29.99, 13.0, 135.2, 32.9, ''),
    ('107', '2023-03-01', 'Mar-2023', '2023', '3', 'Western Cape', 'Cape Town', 'ULP 95', 22.38, 19.82, 20.99, 89.99, 58.99, 79.99, 25.99, 31.99, 17.0, 135.2, 32.9, ''),
    ('108', '2023-03-01', 'Mar-2023', '2023', '3', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.38, 19.82, 19.49, 84.99, 56.99, 75.99, 25.49, 29.49, 15.5, 135.2, 32.9, ''),
    ('109', '2023-04-01', 'Apr-2023', '2023', '4', 'Gauteng', 'Johannesburg', 'ULP 95', 22.55, 19.97, 19.99, 86.99, 57.99, 77.99, 24.99, 29.49, 15.0, 136.0, 32.9, ''),
    ('110', '2023-04-01', 'Apr-2023', '2023', '4', 'Limpopo', 'Polokwane', 'ULP 95', 22.74, 20.1, 20.49, 88.99, 59.99, 79.99, 25.49, 29.99, 13.0, 136.0, 32.9, ''),
    ('111', '2023-04-01', 'Apr-2023', '2023', '4', 'Western Cape', 'Cape Town', 'ULP 95', 22.55, 19.97, 20.99, 90.99, 58.99, 80.99, 25.99, 31.99, 17.0, 136.0, 32.9, ''),
    ('112', '2023-04-01', 'Apr-2023', '2023', '4', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.55, 19.97, 19.49, 85.99, 56.99, 76.99, 25.49, 29.49, 15.5, 136.0, 32.9, ''),
    ('113', '2023-05-01', 'May-2023', '2023', '5', 'Gauteng', 'Johannesburg', 'ULP 95', 22.67, 20.08, 20.49, 87.99, 58.99, 78.99, 25.49, 29.99, 15.5, 136.8, 32.9, ''),
    ('114', '2023-05-01', 'May-2023', '2023', '5', 'Limpopo', 'Polokwane', 'ULP 95', 22.86, 20.21, 20.99, 89.99, 60.99, 80.99, 25.99, 30.49, 13.5, 136.8, 32.9, ''),
    ('115', '2023-05-01', 'May-2023', '2023', '5', 'Western Cape', 'Cape Town', 'ULP 95', 22.67, 20.08, 21.49, 91.99, 59.99, 81.99, 26.49, 32.49, 17.5, 136.8, 32.9, ''),
    ('116', '2023-05-01', 'May-2023', '2023', '5', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.67, 20.08, 19.99, 86.99, 57.99, 77.99, 25.99, 29.99, 16.0, 136.8, 32.9, ''),
    ('117', '2023-06-01', 'Jun-2023', '2023', '6', 'Gauteng', 'Johannesburg', 'ULP 95', 21.89, 19.39, 20.49, 88.99, 59.99, 79.99, 25.99, 30.49, 15.5, 137.6, 32.6, ''),
    ('118', '2023-06-01', 'Jun-2023', '2023', '6', 'Limpopo', 'Polokwane', 'ULP 95', 22.08, 19.52, 20.99, 90.99, 61.99, 81.99, 26.49, 30.99, 13.5, 137.6, 32.6, ''),
    ('119', '2023-06-01', 'Jun-2023', '2023', '6', 'Western Cape', 'Cape Town', 'ULP 95', 21.89, 19.39, 21.49, 92.99, 60.99, 82.99, 26.99, 32.99, 17.5, 137.6, 32.6, ''),
    ('120', '2023-06-01', 'Jun-2023', '2023', '6', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.89, 19.39, 19.99, 87.99, 58.99, 78.99, 26.49, 30.49, 16.0, 137.6, 32.6, ''),
    ('121', '2023-07-01', 'Jul-2023', '2023', '7', 'Gauteng', 'Johannesburg', 'ULP 95', 22.32, 19.78, 20.49, 88.99, 59.99, 79.99, 25.99, 30.49, 15.5, 138.3, 32.6, ''),
    ('122', '2023-07-01', 'Jul-2023', '2023', '7', 'Limpopo', 'Polokwane', 'ULP 95', 22.51, 19.91, 20.99, 90.99, 61.99, 81.99, 26.49, 30.99, 13.5, 138.3, 32.6, 'City uppercase inconsistency'),
    ('123', '2023-07-01', 'Jul-2023', '2023', '7', 'Western Cape', 'Cape Town', 'ULP 95', 22.32, 19.78, 21.49, 92.99, 60.99, 82.99, 26.99, 32.99, 17.5, 138.3, 32.6, ''),
    ('124', '2023-07-01', 'Jul-2023', '2023', '7', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.32, 19.78, 19.99, 87.99, 58.99, 78.99, 26.49, 30.49, 16.0, 138.3, 32.6, ''),
    ('125', '2023-08-01', 'Aug-2023', '2023', '8', 'Gauteng', 'Johannesburg', 'ULP 95', 23.1, 20.48, 20.99, 89.99, 60.99, 81.99, 26.49, 30.99, 16.0, 138.9, 32.1, ''),
    ('126', '2023-08-01', 'Aug-2023', '2023', '8', 'Limpopo', 'Polokwane', 'ULP 95', 23.29, 20.61, 21.49, 91.99, 62.99, 83.99, 26.99, 31.49, 14.0, 138.9, 32.1, ''),
    ('127', '2023-08-01', 'Aug-2023', '2023', '8', 'Western Cape', 'Cape Town', 'ULP 95', 23.1, 20.48, 21.99, 93.99, 61.99, 84.99, 27.49, 33.49, 18.0, 138.9, 32.1, ''),
    ('128', '2023-08-01', 'Aug-2023', '2023', '8', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.1, 20.48, 20.49, 88.99, 59.99, 79.99, 26.99, 31.49, 16.5, 138.9, 32.1, ''),
    ('129', '2023-09-01', 'Sep-2023', '2023', '9', 'Gauteng', 'Johannesburg', 'ULP 95', 23.58, 20.91, 20.99, 89.99, 60.99, 81.99, 26.99, 31.49, 16.0, 139.6, 32.1, ''),
    ('130', '2023-09-01', 'Sep-2023', '2023', '9', 'Limpopo', 'Polokwane', 'ULP 95', 23.78, 21.05, 21.49, 91.99, 62.99, 83.99, 27.49, 31.99, 14.0, 139.6, 32.1, ''),
    ('131', '2023-09-01', 'Sep-2023', '2023', '9', 'Western Cape', 'Cape Town', 'ULP 95', 23.58, 20.91, 21.99, 93.99, 61.99, 84.99, 27.99, 33.99, 18.0, 139.6, 32.1, ''),
    ('132', '2023-09-01', 'Sep-2023', '2023', '9', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.58, 20.91, 20.49, 88.99, 59.99, 80.99, 27.49, 31.99, 16.5, 139.6, 32.1, ''),
    ('133', '2023-10-01', 'Oct-2023', '2023', '10', 'Gauteng', 'Johannesburg', 'ULP 95', 21.97, 19.47, 21.49, 90.99, 62.99, 83.99, 27.49, 31.99, 16.0, 140.4, 32.1, ''),
    ('134', '2023-10-01', 'Oct-2023', '2023', '10', 'Limpopo', 'Polokwane', 'ULP 95', 22.16, 19.6, 21.99, 92.99, 64.99, 85.99, 27.99, 32.49, 14.0, 140.4, 32.1, ''),
    ('135', '2023-10-01', 'Oct-2023', '2023', '10', 'Western Cape', 'Cape Town', 'ULP 95', 21.97, 19.47, 22.49, 94.99, 63.99, 86.99, 28.49, 34.49, 18.0, 140.4, 32.1, ''),
    ('136', '2023-10-01', 'Oct-2023', '2023', '10', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.97, 19.47, 20.99, 89.99, 61.99, 82.99, 27.99, 32.49, 16.5, 140.4, 32.1, ''),
    ('137', '2023-11-01', 'Nov-2023', '2023', '11', 'Gauteng', 'Johannesburg', 'ULP 95', 21.18, 18.77, 21.49, 91.99, 62.99, 83.99, 27.99, 32.49, 16.0, 141.1, 32.1, ''),
    ('138', '2023-11-01', 'Nov-2023', '2023', '11', 'Limpopo', 'Polokwane', 'ULP 95', 21.37, 18.9, 21.99, 93.99, 64.99, 85.99, 28.49, 32.99, 14.0, 141.1, 32.1, ''),
    ('139', '2023-11-01', 'Nov-2023', '2023', '11', 'Western Cape', 'Cape Town', 'ULP 95', 21.18, 18.77, 22.49, 95.99, 63.99, 86.99, 28.99, 34.99, 18.5, 141.1, 32.1, ''),
    ('140', '2023-11-01', 'Nov-2023', '2023', '11', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.18, 18.77, 20.99, 90.99, 61.99, 83.99, 28.49, 32.99, 16.5, 141.1, 32.1, ''),
    ('141', '2023-12-01', 'Dec-2023', '2023', '12', 'Gauteng', 'Johannesburg', 'ULP 95', 21.4, 18.96, 21.99, 92.99, 63.99, 88.99, 28.49, 33.49, 16.5, 141.8, 32.1, ''),
    ('142', '2023-12-01', 'Dec-2023', '2023', '12', 'Limpopo', 'Polokwane', 'ULP 95', 21.59, 19.09, 22.49, 94.99, 65.99, 90.99, 28.99, 33.99, 14.5, 141.8, 32.1, ''),
    ('143', '2023-12-01', 'Dec-2023', '2023', '12', 'Western Cape', 'Cape Town', 'ULP 95', 21.4, 18.96, 22.99, 96.99, 64.99, 91.99, 29.49, 35.99, 18.5, 141.8, 32.1, ''),
    ('144', '2023-12-01', 'Dec-2023', '2023', '12', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.4, 18.96, 21.49, 91.99, 62.99, 87.99, 28.99, 33.99, 17.0, 141.8, 32.1, ''),
    ('145', '2024-01-01', 'Jan-2024', '2024', '1', 'Gauteng', 'Johannesburg', 'ULP 95', 21.63, 19.16, 21.99, 93.99, 64.99, 88.99, 28.99, 33.49, 16.5, 142.5, 32.9, ''),
    ('146', '2024-01-01', 'Jan-2024', '2024', '1', 'Limpopo', 'Polokwane', 'ULP 95', 21.82, 19.29, 22.49, 95.99, 66.99, 90.99, 29.49, 33.99, 14.5, 142.5, 32.9, ''),
    ('147', '2024-01-01', 'Jan-2024', '2024', '1', 'Western Cape', 'Cape Town', 'ULP 95', 21.63, 19.16, 22.99, 97.99, 65.99, 91.99, 29.99, 35.99, 18.5, 142.5, 32.9, ''),
    ('148', '2024-01-01', 'Jan-2024', '2024', '1', 'KwaZulu-Natal', 'Durban', 'ULP 95', 21.63, 19.16, 21.49, 92.99, 63.99, 87.99, 29.49, 33.99, 17.0, 142.5, 32.9, ''),
    ('149', '2024-02-01', 'Feb-2024', '2024', '2', 'Gauteng', 'Johannesburg', 'ULP 95', 22.27, 19.73, 22.49, 94.99, 65.99, 89.99, 29.49, 33.99, 16.5, 143.3, 32.9, ''),
    ('150', '2024-02-01', 'Feb-2024', '2024', '2', 'Limpopo', 'Polokwane', 'ULP 95', 22.47, 19.87, 22.99, 96.99, 67.99, 91.99, 29.99, 34.49, 14.5, 143.3, 32.9, ''),
    ('151', '2024-02-01', 'Feb-2024', '2024', '2', 'Western Cape', 'Cape Town', 'ULP 95', 22.27, 19.73, 23.49, 98.99, 66.99, 92.99, 30.49, 36.49, 19.0, 143.3, 32.9, ''),
    ('152', '2024-02-01', 'Feb-2024', '2024', '2', 'KwaZulu-Natal', 'Durban', 'ULP 95', 22.27, 19.73, 21.99, 93.99, 64.99, 88.99, 29.99, 34.49, 17.5, 143.3, 32.9, ''),
    ('153', '2024-03-01', 'Mar-2024', '2024', '3', 'Gauteng', 'Johannesburg', 'ULP 95', 23.39, 20.75, 22.49, 95.99, 66.99, 90.99, 29.99, 34.49, 17.0, 144.1, 33.5, ''),
    ('154', '2024-03-01', 'Mar-2024', '2024', '3', 'Limpopo', 'Polokwane', 'ULP 95', 23.6, 20.89, 22.99, 97.99, 68.99, 92.99, 30.49, 34.99, 15.0, 144.1, 33.5, ''),
    ('155', '2024-03-01', 'Mar-2024', '2024', '3', 'Western Cape', 'Cape Town', 'ULP 95', 23.39, 20.75, 23.49, 99.99, 67.99, 93.99, 30.99, 36.99, 19.0, 144.1, 33.5, ''),
    ('156', '2024-03-01', 'Mar-2024', '2024', '3', 'KwaZulu-Natal', 'Durban', 'ULP 95', 23.39, 20.75, 21.99, 94.99, 65.99, 89.99, 30.49, 34.99, 17.5, 144.1, 33.5, ''),
    ('157', '2024-04-01', 'Apr-2024', '2024', '4', 'Gauteng', 'Johannesburg', 'ULP 95', 24.12, 21.4, 22.49, 95.99, 67.99, 91.99, 30.49, 34.99, 17.0, 144.9, 33.5, ''),
    ('158', '2024-04-01', 'Apr-2024', '2024', '4', 'Limpopo', 'Polokwane', 'ULP 95', 24.33, 21.54, 22.99, 97.99, 69.99, 93.99, 30.99, 35.49, 15.0, 144.9, 33.5, ''),
    ('159', '2024-04-01', 'Apr-2024', '2024', '4', 'Western Cape', 'Cape Town', 'ULP 95', 24.12, 21.4, 23.49, 99.99, 68.99, 94.99, 31.49, 37.49, 19.5, 144.9, 33.5, ''),
    ('160', '2024-04-01', 'Apr-2024', '2024', '4', 'KwaZulu-Natal', 'Durban', 'ULP 95', 24.12, 21.4, 21.99, 94.99, 66.99, 90.99, 30.99, 35.49, 18.0, 144.9, 33.5, '');
    
    SELECT `fuel_consumer_cleaned`.`record_id` as record_id,
    `fuel_consumer_cleaned`.`price_date`as price_date,
    `fuel_consumer_cleaned`.`month_year`,
    `fuel_consumer_cleaned`.`yr` as yr,
    `fuel_consumer_cleaned`.`mo`,
    `fuel_consumer_cleaned`.`province`,
    `fuel_consumer_cleaned`.`city`,
    `fuel_consumer_cleaned`.`fuel_type`,
    `fuel_consumer_cleaned`.`petrol_price`,
    `fuel_consumer_cleaned`.`diesel_price`,
    `fuel_consumer_cleaned`.`bread_price`,
    `fuel_consumer_cleaned`.`maize_meal_10kg`,
    `fuel_consumer_cleaned`.`chicken_1kg`,
    `fuel_consumer_cleaned`.`milk_1l`,
    `fuel_consumer_cleaned`.`eggs_6pack`,
    `fuel_consumer_cleaned`.`transport_fare`,
    `fuel_consumer_cleaned`.`cpi_index`,
    `fuel_consumer_cleaned`.`unemployment_pct`,
    `fuel_consumer_cleaned`.`basic_basket_zar`,
    `fuel_consumer_cleaned`.`petrol_affordability`,
    `fuel_consumer_cleaned`.`period_flag`,
    `fuel_consumer_cleaned`.`data_note`,
    `fuel_consumer_cleaned`.`created_at`
FROM `sa fuel price`.`fuel_consumer_cleaned`;

-- ============================================================
--  SECTION 4 — CORE ANALYSIS (A1 – A8)
-- ============================================================

-- ── A1: Overall petrol price summary by province ─────────────
SELECT
    province ,
    ROUND(MIN( petrol_price ), 2)                                AS min_petrol,
    ROUND(AVG( petrol_price ), 2)                                AS avg_petrol,
    ROUND(MAX( petrol_price ), 2)                                AS max_petrol,
    ROUND(MAX( petrol_price ) - MIN( petrol_price ), 2)            AS total_increase,
    ROUND((MAX( petrol_price ) - MIN( petrol_price ))
          / MIN(petrol_price) * 100, 2)                        AS pct_increase,
    COUNT(*)                                                   AS months_recorded
FROM fuel_consumer_cleaned
GROUP BY province
ORDER BY avg_petrol DESC;

-- ── A2: Monthly petrol price trend — all 4 provinces ────────
SELECT
	month_year,
    price_date,
    MAX(CASE WHEN province = 'Gauteng'       THEN petrol_price END) AS gauteng,
    MAX(CASE WHEN province = 'Limpopo'       THEN petrol_price END) AS limpopo,
    MAX(CASE WHEN province = 'Western Cape'  THEN petrol_price END) AS western_cape,
    MAX(CASE WHEN province = 'KwaZulu-Natal' THEN petrol_price END) AS kwazulu_natal,
    ROUND(AVG( petrol_price ), 2)                                     AS national_avg
FROM fuel_consumer_cleaned
GROUP BY month_year, price_date
ORDER BY price_date;

-- ── A3: Annual summary — petrol, diesel, basket, CPI ─────────

WITH yearly_stats AS (
    SELECT
        yr,
        AVG(petrol_price)        AS avg_petrol,
        AVG(diesel_price)        AS avg_diesel,
        AVG(basic_basket_zar)    AS avg_food_basket,
        AVG(cpi_index)           AS avg_cpi,
        AVG(unemployment_pct)    AS avg_unemployment_pct,
        MAX(petrol_price)        AS peak_petrol
    FROM fuel_consumer_cleaned
    GROUP BY yr
),
peak_dates AS (
    SELECT y.yr, MAX(f.price_date) AS peak_petrol_date
    FROM fuel_consumer_cleaned f
    JOIN yearly_stats y
        ON f.yr = y.yr
       AND f.petrol_price = y.peak_petrol
    GROUP BY y.yr
)
SELECT
    ys.yr                                     AS year,
    ROUND(ys.avg_petrol, 2)                   AS avg_petrol,
    ROUND(ys.avg_diesel, 2)                   AS avg_diesel,
    ROUND(ys.avg_food_basket, 2)              AS avg_food_basket,
    ROUND(ys.avg_cpi, 1)                      AS avg_cpi,
    ROUND(ys.avg_unemployment_pct, 1)         AS avg_unemployment_pct,
    ROUND(ys.peak_petrol, 2)                  AS peak_petrol,
    DATE_FORMAT(pd.peak_petrol_date, '%b-%Y') AS peak_petrol_month
FROM yearly_stats ys
JOIN peak_dates pd ON ys.yr = pd.yr
ORDER BY ys.yr;

-- ── A4: Provincial food basket cost comparison ────────────────
SELECT
    province,
    ROUND(AVG(bread_price),      2) AS avg_bread,
    ROUND(AVG(maize_meal_10kg),  2) AS avg_maize_10kg,
    ROUND(AVG(chicken_1kg),      2) AS avg_chicken,
    ROUND(AVG(milk_1l),          2) AS avg_milk,
    ROUND(AVG(eggs_6pack),       2) AS avg_eggs,
    ROUND(AVG(basic_basket_zar), 2) AS avg_full_basket,
    ROUND(AVG(transport_fare),   2) AS avg_transport
FROM fuel_consumer_cleaned
GROUP BY province
ORDER BY avg_full_basket DESC;

-- ── A5: Top 10 most expensive months (by avg petrol national) ─
SELECT
    month_year,
    price_date,
    ROUND(AVG(petrol_price), 2)      AS avg_petrol_national,
    ROUND(AVG(diesel_price), 2)      AS avg_diesel_national,
    ROUND(AVG(basic_basket_zar), 2)  AS avg_basket,
    ROUND(AVG(cpi_index), 1)         AS cpi,
    data_note
FROM fuel_consumer_cleaned
GROUP BY month_year, price_date, data_note
ORDER BY avg_petrol_national DESC
LIMIT 10;

-- ── A6: Cheapest months — best time to be a consumer ─────────
SELECT
    month_year,
    price_date,
    ROUND(AVG(petrol_price), 2)     AS avg_petrol,
    ROUND(AVG(basic_basket_zar), 2) AS avg_basket,
    ROUND(AVG(cpi_index), 1)        AS cpi
FROM fuel_consumer_cleaned
GROUP BY month_year, price_date
ORDER BY avg_petrol ASC
LIMIT 10;

-- ── A7: Diesel vs petrol price gap by province ───────────────
SELECT
    province,
    ROUND(AVG(petrol_price), 2)                            AS avg_petrol,
    ROUND(AVG(diesel_price), 2)                            AS avg_diesel,
    ROUND(AVG(petrol_price) - AVG(diesel_price), 2)        AS avg_gap,
    ROUND((AVG(petrol_price) - AVG(diesel_price))
          / AVG(diesel_price) * 100, 1)                    AS petrol_premium_pct,
    ROUND(MIN(petrol_price - diesel_price), 2)             AS min_gap,
    ROUND(MAX(petrol_price - diesel_price), 2)             AS max_gap
FROM fuel_consumer_cleaned
GROUP BY province
ORDER BY avg_gap DESC;

-- ── A8: Data quality issues summary ─────────────────────────
SELECT
    issue_number,
    issue_type,
    field_affected,
    records_affected,
    action_taken,
    LEFT(resolution, 80) AS resolution_summary
FROM data_quality_log
ORDER BY issue_number;


-- ============================================================
--  SECTION 5 — ADVANCED ANALYSIS (B1 – B8)
-- ============================================================

-- ── B1: Year-over-Year petrol price change by province ───────
WITH yearly AS (
    SELECT
        province,
        yr,
        ROUND(AVG(petrol_price), 2) AS avg_petrol
    FROM fuel_consumer_cleaned
    GROUP BY province, yr
)
SELECT
    curr.province,
    curr.yr                                                      AS year,
    curr.avg_petrol                                              AS avg_petrol,
    prev.avg_petrol                                              AS prev_year_petrol,
    ROUND(curr.avg_petrol - prev.avg_petrol, 2)                  AS yoy_change_zar,
    ROUND((curr.avg_petrol - prev.avg_petrol)
          / prev.avg_petrol * 100, 1)                            AS yoy_change_pct
FROM yearly curr
LEFT JOIN yearly prev
    ON curr.province = prev.province
    AND curr.yr = prev.yr + 1
WHERE prev.avg_petrol IS NOT NULL
ORDER BY curr.yr, yoy_change_pct DESC;

-- ── B2: Limpopo vs Gauteng petrol premium (inland tax) ───────
SELECT
    f1.month_year,
    f1.price_date,
    f1.petrol_price                              AS limpopo_petrol,
    f2.petrol_price                              AS gauteng_petrol,
    ROUND(f1.petrol_price - f2.petrol_price, 2) AS limpopo_premium,
    f1.diesel_price                              AS limpopo_diesel,
    f2.diesel_price                              AS gauteng_diesel,
    ROUND(f1.diesel_price - f2.diesel_price, 2) AS diesel_premium
FROM fuel_consumer_cleaned f1
JOIN fuel_consumer_cleaned f2
    ON f1.price_date = f2.price_date
    AND f2.province  = 'Gauteng'
WHERE f1.province = 'Limpopo'
ORDER BY f1.price_date;

-- ── B3: Petrol affordability index over time ─────────────────
-- (Petrol price as % of CPI — higher = less affordable)
SELECT
    month_year,
    price_date,
    ROUND(AVG(petrol_price), 2)          AS avg_petrol,
    ROUND(AVG(cpi_index), 1)             AS avg_cpi,
    ROUND(AVG(petrol_affordability), 4)  AS affordability_index,
    RANK() OVER (ORDER BY AVG(petrol_affordability) DESC) AS least_affordable_rank
FROM fuel_consumer_cleaned
GROUP BY month_year, price_date
ORDER BY price_date;

-- ── B4: Food basket vs petrol correlation ────────────────────
-- When fuel spikes, does food follow? Shows structural link.
WITH monthly_avg AS (
    SELECT
        price_date,
        ROUND(AVG(petrol_price), 2)      AS avg_petrol,
        ROUND(AVG(basic_basket_zar), 2)  AS avg_basket
    FROM fuel_consumer_cleaned
    GROUP BY price_date
)
SELECT
    price_date,
    avg_petrol,
    avg_basket,
    ROUND(avg_basket / avg_petrol, 2)                    AS basket_to_petrol_ratio,
    ROUND(avg_petrol - LAG(avg_petrol)
          OVER (ORDER BY price_date), 2)                 AS petrol_mom_change,
    ROUND(avg_basket - LAG(avg_basket)
          OVER (ORDER BY price_date), 2)                 AS basket_mom_change
FROM monthly_avg
ORDER BY price_date;

-- ── B5: Running total petrol spend (Gauteng, full tank = 50L) ─
WITH gauteng AS (
    SELECT
        price_date,
        month_year,
        petrol_price,
        ROUND(petrol_price * 50, 2) AS full_tank_50l
    FROM fuel_consumer_cleaned
    WHERE province = 'Gauteng'
    ORDER BY price_date
)
SELECT
    month_year,
    petrol_price                                       AS petrol_per_litre,
    full_tank_50l,
    ROUND(SUM(full_tank_50l) OVER (ORDER BY price_date
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2)
                                                       AS cumulative_spend_50l,
    ROUND(full_tank_50l - FIRST_VALUE(full_tank_50l)
          OVER (ORDER BY price_date), 2)               AS extra_vs_jan_2021
FROM gauteng;

-- ── B6: Quarterly analysis — petrol, basket, unemployment ────
WITH quarterly AS (
    SELECT
        yr,
        CAST(CEIL(mo / 3) AS SIGNED) AS quarter,
        petrol_price,
        diesel_price,
        basic_basket_zar,
        cpi_index,
        unemployment_pct
    FROM fuel_consumer_cleaned
)
SELECT
    yr                                        AS year,
    quarter,
    CONCAT('Q', quarter, ' ', yr)              AS period,
    ROUND(AVG(petrol_price),      2)           AS avg_petrol,
    ROUND(AVG(diesel_price),      2)           AS avg_diesel,
    ROUND(AVG(basic_basket_zar),  2)           AS avg_basket,
    ROUND(AVG(cpi_index),         1)           AS avg_cpi,
    ROUND(AVG(unemployment_pct),  1)           AS avg_unemployment
FROM quarterly
GROUP BY yr, quarter
ORDER BY yr, quarter;

-- ── B7: Province ranking per month (petrol price) ────────────
SELECT
    month_year,
    price_date,
    province,
    petrol_price,
    RANK()       OVER (PARTITION BY price_date ORDER BY petrol_price DESC) AS price_rank,
    ROUND(petrol_price - AVG(petrol_price) OVER (PARTITION BY price_date), 2)
                                                                           AS vs_national_avg,
    NTILE(4) OVER (PARTITION BY price_date ORDER BY petrol_price)          AS price_quartile
FROM fuel_consumer_cleaned
ORDER BY price_date, price_rank;

-- ── B8: 3-month rolling average petrol price (Gauteng) ───────
SELECT
    month_year,
    price_date,
    petrol_price,
    ROUND(AVG(petrol_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS rolling_3m_avg,
    ROUND(petrol_price - AVG(petrol_price) OVER (
        ORDER BY price_date
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS deviation_from_rolling_avg
FROM fuel_consumer_cleaned
WHERE province = 'Gauteng'
ORDER BY price_date;


-- ============================================================
--  SECTION 6 — ECONOMIC INSIGHTS (C1 – C6)
-- ============================================================

-- ── C1: Impact of Jun-2022 record fuel spike on food prices ──
-- Compare 6 months before vs 6 months after the peak
WITH before_peak AS (
    SELECT
        'Before Peak (Dec 2021–May 2022)' AS period,
        ROUND(AVG(petrol_price), 2)     AS avg_petrol,
        ROUND(AVG(basic_basket_zar), 2) AS avg_basket,
        ROUND(AVG(chicken_1kg), 2)      AS avg_chicken,
        ROUND(AVG(bread_price), 2)      AS avg_bread,
        ROUND(AVG(cpi_index), 1)        AS avg_cpi
    FROM fuel_consumer_cleaned
    WHERE price_date BETWEEN '2021-12-01' AND '2022-05-01'
),
after_peak AS (
    SELECT
        'After Peak (Jul 2022–Dec 2022)' AS period,
        ROUND(AVG(petrol_price), 2)     AS avg_petrol,
        ROUND(AVG(basic_basket_zar), 2) AS avg_basket,
        ROUND(AVG(chicken_1kg), 2)      AS avg_chicken,
        ROUND(AVG(bread_price), 2)      AS avg_bread,
        ROUND(AVG(cpi_index), 1)        AS avg_cpi
    FROM fuel_consumer_cleaned
    WHERE price_date BETWEEN '2022-07-01' AND '2022-12-01'
)
SELECT * FROM before_peak
UNION ALL
SELECT * FROM after_peak;

-- ── C2: Fuel price vs CPI correlation (Pearson) ─────────────
-- Higher correlation = fuel is a strong CPI driver

WITH stats AS (
    SELECT
        AVG(petrol_price)                         AS avg_p,
        AVG(cpi_index)                            AS avg_c,
        STDDEV_SAMP(petrol_price)                 AS std_p,
        STDDEV_SAMP(cpi_index)                    AS std_c,
        COUNT(*)                                  AS n
    FROM fuel_consumer_cleaned
    WHERE province = 'Gauteng'
),
corr AS (
    SELECT
        SUM((f.petrol_price - s.avg_p) * (f.cpi_index - s.avg_c))
        / (MAX(s.n) * MAX(s.std_p) * MAX(s.std_c)) AS pearson_r
    FROM fuel_consumer_cleaned f
    CROSS JOIN stats s
    WHERE f.province = 'Gauteng'
)
SELECT
    ROUND(CAST(pearson_r AS DECIMAL(10,4)), 4)    AS pearson_r,
    CASE
        WHEN ABS(pearson_r) > 0.9 THEN 'Very strong correlation'
        WHEN ABS(pearson_r) > 0.7 THEN 'Strong correlation'
        WHEN ABS(pearson_r) > 0.5 THEN 'Moderate correlation'
        ELSE 'Weak correlation'
    END                                           AS interpretation,
    'Petrol Price vs CPI Index (Gauteng)'         AS variables
FROM corr;

-- ── C3: Transport fare vs petrol price elasticity ─────────────
-- Does transport cost track petrol price?  (Gauteng)
WITH g AS (
    SELECT
        price_date,
        petrol_price,
        transport_fare,
        LAG(petrol_price)   OVER (ORDER BY price_date) AS prev_petrol,
        LAG(transport_fare) OVER (ORDER BY price_date) AS prev_fare
    FROM fuel_consumer_cleaned
    WHERE province = 'Gauteng'
)
SELECT
    price_date,
    petrol_price,
    transport_fare,
    ROUND((petrol_price - prev_petrol) / NULLIF(prev_petrol, 0) * 100, 2)
                                                AS petrol_pct_chg,
    ROUND((transport_fare - prev_fare) / NULLIF(prev_fare, 0) * 100, 2)
                                                AS fare_pct_chg,
    ROUND(
        ((transport_fare - prev_fare) / NULLIF(prev_fare, 0))
        / NULLIF((petrol_price - prev_petrol) / NULLIF(prev_petrol, 0), 0),
    2)                                          AS fare_elasticity_vs_petrol
FROM g
WHERE prev_petrol IS NOT NULL
ORDER BY price_date;

-- ── C4: Unemployment vs fuel price — economic stress index ───
SELECT
    yr                                                AS year,
    ROUND(AVG(petrol_price),     2)                   AS avg_petrol,
    ROUND(AVG(unemployment_pct), 1)                   AS avg_unemployment,
    ROUND(AVG(basic_basket_zar), 2)                   AS avg_basket,
    ROUND(AVG(petrol_price) * AVG(unemployment_pct)
          / AVG(cpi_index) * 10, 2)                   AS economic_stress_index,
    RANK() OVER (ORDER BY
        AVG(petrol_price) * AVG(unemployment_pct)
        / AVG(cpi_index) DESC)                        AS stress_rank
FROM fuel_consumer_cleaned
GROUP BY yr
ORDER BY yr;

-- ── C5: Western Cape premium — most expensive province ────────
WITH prov_monthly AS (
    SELECT
        price_date,
        province,
        petrol_price,
        basic_basket_zar
    FROM fuel_consumer_cleaned
),
wc AS (
    SELECT price_date,
           petrol_price  AS wc_petrol,
           basic_basket_zar AS wc_basket
    FROM prov_monthly
    WHERE province = 'Western Cape'
),
gp AS (
    SELECT price_date,
           petrol_price  AS gp_petrol,
           basic_basket_zar AS gp_basket
    FROM prov_monthly
    WHERE province = 'Gauteng'
)
SELECT
    wc.price_date,
    wc.wc_petrol,
    gp.gp_petrol,
    ROUND(wc.wc_petrol - gp.gp_petrol, 2)    AS petrol_premium,
    wc.wc_basket,
    gp.gp_basket,
    ROUND(wc.wc_basket - gp.gp_basket, 2)    AS basket_premium,
    ROUND((wc.wc_basket - gp.gp_basket)
          / gp.gp_basket * 100, 1)            AS basket_premium_pct
FROM wc
JOIN gp USING (price_date)
ORDER BY price_date;

-- ── C6: Identify periods of max economic pressure ────────────
-- Composite score: high fuel + high food + high unemployment
WITH monthly AS (
    SELECT
        month_year,
        price_date,
        AVG(petrol_price)      AS avg_petrol,
        AVG(basic_basket_zar)  AS avg_basket,
        AVG(unemployment_pct)  AS avg_unemployment,
        AVG(cpi_index)         AS avg_cpi
    FROM fuel_consumer_cleaned
    GROUP BY month_year, price_date
),
monthly_with_max AS (
    SELECT
        m.*,
        MAX(avg_petrol)     OVER () AS max_petrol,
        MAX(avg_basket)     OVER () AS max_basket,
        MAX(avg_unemployment) OVER () AS max_unemployment
    FROM monthly m
)
SELECT
    month_year,
    price_date,
    ROUND(avg_petrol, 2)       AS avg_petrol,
    ROUND(avg_basket, 2)       AS avg_basket,
    ROUND(avg_unemployment, 1) AS unemployment,
    ROUND(avg_cpi, 1)          AS cpi,
    ROUND(
        (avg_petrol      / max_petrol      * 0.35 +
         avg_basket      / max_basket      * 0.35 +
         avg_unemployment / max_unemployment * 0.30)
        * 100, 1)               AS pressure_score_pct,
    RANK() OVER (ORDER BY
        (avg_petrol      / max_petrol      * 0.35 +
         avg_basket      / max_basket      * 0.35 +
         avg_unemployment / max_unemployment * 0.30)
        DESC)                   AS pressure_rank
FROM monthly_with_max
ORDER BY pressure_rank
LIMIT 15;

