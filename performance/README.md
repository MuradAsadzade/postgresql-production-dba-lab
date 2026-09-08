# PostgreSQL Query Performance Tuning

## Scenario

The `banking.transactions` table contains approximately **1,000,000 rows**.

A query filtering transactions by `transaction_date` was experiencing inefficient execution because no index existed on this column.

## Query

```sql
SELECT *
FROM banking.transactions
WHERE transaction_date >= '2026-09-07 15:48:50.54577';
```

## Before Optimization

No index existed on `transaction_date`.

Execution plan:

```text
Gather
  -> Parallel Seq Scan on transactions
```

Key metrics:

- **Execution Time:** 46.360 ms
- **Shared Buffers:** 9672
- **Rows Returned:** 107
- **Access Method:** Parallel Sequential Scan

The database had to scan almost the entire **1-million-row table** to return only 107 rows.

## Optimization

The following B-tree index was created:

```sql
CREATE INDEX CONCURRENTLY idx_transactions_date
ON banking.transactions(transaction_date);
```

Table statistics were then refreshed:

```sql
ANALYZE banking.transactions;
```

`CREATE INDEX CONCURRENTLY` was used to reduce blocking of write operations while the index was being created.

## After Optimization

Execution plan:

```text
Bitmap Heap Scan on transactions
  -> Bitmap Index Scan on idx_transactions_date
```

Key metrics:

- **Execution Time:** 0.184 ms
- **Shared Buffers:** 111
- **Rows Returned:** 107
- **Access Method:** Bitmap Index Scan

## Performance Improvement

| Metric | Before | After |
|---|---:|---:|
| Execution Time | 46.360 ms | 0.184 ms |
| Shared Buffers | 9672 | 111 |
| Rows Returned | 107 | 107 |
| Access Method | Parallel Seq Scan | Bitmap Index Scan |

Execution time improved by approximately **252x**.

Buffer usage was reduced by approximately **87x**.

## Conclusion

The query was highly selective but lacked an appropriate index.

Adding a B-tree index on `transaction_date` allowed PostgreSQL to avoid scanning the entire table and significantly reduced query execution time and buffer usage.

This demonstrates the importance of analyzing PostgreSQL query execution plans using:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM banking.transactions
WHERE transaction_date >= '2026-09-07 15:48:50.54577';
```

before making performance tuning decisions.
