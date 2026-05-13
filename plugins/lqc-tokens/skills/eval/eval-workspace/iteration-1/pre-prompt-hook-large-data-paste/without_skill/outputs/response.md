# Q4 Sales Data Analysis

**Note:** I am answering this question directly based on the data provided. However, I only have access to the 10 sample rows shown — the remaining 49,990 rows referenced in the prompt were not included. The analysis below is limited to those 10 rows and should not be treated as representative of the full Q4 dataset.

---

## Total Revenue by Region (sample data only)

| Region | Revenue     |
|--------|-------------|
| AMER   | $228,200    |
| APAC   | $125,700    |
| EMEA   | $109,300    |
| **Total** | **$463,200** |

Calculation details:
- **AMER**: $62,000 + $59,400 + $106,800 = $228,200
- **APAC**: $40,600 + $49,500 + $35,600 = $125,700
- **EMEA**: $28,400 + $26,100 + $23,600 + $31,200 = $109,300

---

## Profit Margin by Product (sample data only)

Profit = Revenue - Cost  
Margin % = (Profit / Revenue) × 100

| Row | Region | Product  | Revenue | Cost   | Profit | Margin % |
|-----|--------|----------|---------|--------|--------|----------|
| 1   | EMEA   | Widget-A | 28,400  | 18,460 | 9,940  | 35.0%    |
| 2   | EMEA   | Widget-B | 26,100  | 14,790 | 11,310 | 43.3%    |
| 3   | APAC   | Widget-A | 40,600  | 26,390 | 14,210 | 35.0%    |
| 4   | EMEA   | Widget-A | 23,600  | 15,340 | 8,260  | 35.0%    |
| 5   | APAC   | Widget-B | 49,500  | 28,050 | 21,450 | 43.3%    |
| 6   | AMER   | Widget-A | 62,000  | 40,300 | 21,700 | 35.0%    |
| 7   | AMER   | Widget-B | 59,400  | 33,660 | 25,740 | 43.3%    |
| 8   | EMEA   | Widget-A | 31,200  | 20,280 | 10,920 | 35.0%    |
| 9   | APAC   | Widget-C | 35,600  | 24,040 | 11,560 | 32.5%    |
| 10  | AMER   | Widget-C | 106,800 | 72,090 | 34,710 | 32.5%    |

### Average Margin by Product (across sample rows)

| Rank | Product  | Avg Margin % |
|------|----------|--------------|
| 1    | Widget-B | 43.3%        |
| 2    | Widget-A | 35.0%        |
| 3    | Widget-C | 32.5%        |

Only 3 distinct products appear in the sample data. A "top 5 by profit margin" ranking is not possible with this dataset alone.

---

## Limitation

The analysis above covers **10 out of 50,000 rows**. To perform a statistically valid analysis of the full Q4 dataset, please provide the complete data file (e.g., as an attachment or file path). Results from the sample may not reflect the true regional distribution or product performance across the full quarter.
