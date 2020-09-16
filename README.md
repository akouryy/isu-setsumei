# ISU-SETSUMEI

EXPLAIN queries in slow query log files.

```
Usage: setsumei [options] [slow_query_files]
    -n, --number NUM                 Set a replacement value for number placeholders
    -l, --limit NUM                  Specify a replacement value for LIMIT placeholders
    -o, --offset NUM                 Specify a replacement value for OFFSET placeholders
        --ub, --upper-bound NUM      Specify a replacement value for upper bound placeholders
        --lb, --lower-bound NUM      Specify a replacement value for lower bound placeholders
    -s, --string STR                 Set a replacement value for string placeholders
    -k, --like STR                   Specify a replacement value for LIKE placeholders
    -c, --color WHEN                 Specify when to highlight words; WHEN can be `auto` (default), `always`, or `never`
    -b, --ban REGEXP                 Set the pattern for highlighting results
    -q, --query                      Output EXPLAIN queries
    -a, --add-special ROW,COL,VAL    Specify a special replacement value for one placeholder
    -v, --verbose                    Output more debug messages
```
