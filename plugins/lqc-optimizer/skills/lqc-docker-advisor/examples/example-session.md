# Example: Analyzing a CSV dataset with PostgreSQL

**User prompt:** "I have a sales CSV with 50,000 rows. I want to find total revenue by region and top 10 products."

## docker-advisor analysis

**Data shape:** tabular (CSV, fixed columns)
**Access patterns:** aggregation (SUM, GROUP BY), ranking (ORDER BY, LIMIT)
**Recommended DB:** PostgreSQL
**Longevity:** asked user → "just for today" → ephemeral

## Generated docker-compose.lqc.yml

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: lqc-a1b2c3d4
    ports:
      - "47832:5432"
    volumes:
      - lqc-a1b2c3d4-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: lqcdata
      POSTGRES_USER: lqc
      POSTGRES_PASSWORD: ${LQC_DB_PASSWORD}

volumes:
  lqc-a1b2c3d4-data:
```

## Data loading stub

```python
import pandas as pd
from sqlalchemy import create_engine

df = pd.read_csv('sales.csv')
engine = create_engine(f'postgresql://lqc:{os.environ["LQC_DB_PASSWORD"]}@localhost:47832/lqcdata')
df.to_sql('sales', engine, if_exists='replace', index=False)
print(f"Loaded {len(df)} rows")
```

## Claude now queries instead of loading context

```sql
-- Revenue by region
SELECT region, SUM(revenue) AS total_revenue
FROM sales
GROUP BY region
ORDER BY total_revenue DESC;

-- Top 10 products
SELECT product, SUM(revenue) AS total_revenue
FROM sales
GROUP BY product
ORDER BY total_revenue DESC
LIMIT 10;
```

**Context cost:** ~500 tokens (query results) vs ~40,000 tokens (full CSV in context) = 98% reduction
