
Dataset Overview
================

Files:
1. companies.csv
   - Master list of companies.

2. products.csv
   - Products created by companies.
   - Each company owns 2-6 products.

3. bill_of_materials.csv
   - Relationship table representing product composition / supplier chains.
   - parent_product_id uses component_product_id as a part.

4. product_analytics.csv
   - Precomputed analytics to simplify querying.

This dataset supports answering:
- Products with a production chain longer than 3 suppliers.
- Most profitable products by margin %.
- Products with the highest accumulated number of parts.

Suggested joins:
products.product_id <-> bill_of_materials.parent_product_id
products.product_id <-> bill_of_materials.component_product_id
products.company_id <-> companies.company_id
