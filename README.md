# ISU-SETSUMEI

EXPLAIN queries in slow query log files.

Based on reflection on [ISUCON 10 Qualification](https://akouryy.hatenablog.jp/entry/2020/09/13/130415).

```
Usage: setsumei [options] [slow_query_files]

parameters:
    [slow_query_files]      If specified, read logs from them. Otherwise, use STDIN instead.
environment variables:
    MYSQL_HOST              MySQL host
    MYSQL_PORT              MySQL port
    MYSQL_USER              MySQL user name
    MYSQL_PASS              MySQL password
    MYSQL_DBNAME            MySQL database name
options:
    -n, --number NUM                 Set a replacement value for number placeholders
    -l, --limit NUM                  Specify a replacement value for LIMIT placeholders
    -o, --offset NUM                 Specify a replacement value for OFFSET placeholders
    -U, --upper-bound NUM            Specify a replacement value for upper bound placeholders
    -L, --lower-bound NUM            Specify a replacement value for lower bound placeholders
    -s, --string STR                 Set a replacement value for string placeholders
    -k, --like STR                   Specify a replacement value for LIKE placeholders
    -c, --color WHEN                 Specify when to highlight words; WHEN can be `auto` (default), `always`, or `never`
    -b, --ban REGEXP                 Set the pattern for highlighting results
    -q, --query                      Output EXPLAIN queries
    -a, --add-special ROW,COL,VAL    Specify a special replacement value for one placeholder
    -z, --zip                        Output compactly
    -v, --verbose                    Output more debug messages
```
