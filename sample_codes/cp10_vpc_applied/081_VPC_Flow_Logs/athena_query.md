### データテーブルの作成

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
  version int,
  account_id string,
  interface_id string,
  srcaddr string,
  dstaddr string,
  srcport int,
  dstport int,
  protocol bigint,
  packets bigint,
  bytes bigint,
  start bigint,
  `end` bigint,
  action string,
  log_status string,
  vpc_id string,
  subnet_id string,
  instance_id string,
  tcp_flags int,
  type string,
  pkt_srcaddr string,
  pkt_dstaddr string,
  az_id string,
  sublocation_type string,
  sublocation_id string,
  pkt_src_aws_service string,
  pkt_dst_aws_service string,
  flow_direction string,
  traffic_path int
)
PARTITIONED BY (accid string, region string, day string)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ' '
LOCATION 's3://<your-flow-logs-bucket>/AWSLogs/'
TBLPROPERTIES (
  "skip.header.line.count"="1",

  "projection.enabled" = "true",
  "projection.accid.type"   = "enum",
  "projection.accid.values" = "<your-account-id>",
  "projection.region.type"  = "enum",
  "projection.region.values"= "ap-northeast-1",

  "projection.day.type"   = "date",
  "projection.day.range"  = "<start-date>,NOW",
  "projection.day.format" = "yyyy/MM/dd",

  "storage.location.template" = "s3://<your-flow-logs-bucket>/AWSLogs/${accid}/vpcflowlogs/${region}/${day}"
);
```

### ログを100件取得する

```sql
SELECT * 
FROM vpc_flow_logs 
WHERE day BETWEEN '2025/09/07' AND '2025/09/08'
LIMIT 100;
```

### NATインスタンスに対するアクセス統計を見る

```sql
-- actionごと（ACCEPT/REJECT）に集計
WITH params AS (
  SELECT
    '<nat-instance-private-ip>'                         AS target_ip,
    from_iso8601_timestamp('<start-date>T00:00:00Z')    AS from_ts,
    from_iso8601_timestamp('<end-date>T00:00:00Z')      AS to_ts
)
SELECT
  l.action,                               -- 'ACCEPT' / 'REJECT'
  COUNT(*)          AS flow_count,        -- 行数（≒フロー数）
  SUM(l.packets)    AS total_packets,
  SUM(l.bytes)      AS total_bytes
FROM vpc_flow_logs l
CROSS JOIN params p
WHERE l.dstaddr = p.target_ip             -- 指定IP「への」トラフィック
  AND l.log_status = 'OK'                 -- NODATA/SKIPDATA除外
  AND l.day BETWEEN date_format(p.from_ts, '%Y/%m/%d')
                 AND date_format(date_add('day', -1, p.to_ts), '%Y/%m/%d')
  AND l.start >= to_unixtime(p.from_ts)
  AND l.start <  to_unixtime(p.to_ts)
GROUP BY l.action
ORDER BY l.action;
```

### 拒絶されたトラフィックの送信元のIPアドレスを列挙

```sql
WITH params AS (
  SELECT
    '<nat-instance-private-ip>'                         AS target_ip,
    from_iso8601_timestamp('<start-date>T00:00:00Z')    AS from_ts,
    from_iso8601_timestamp('<end-date>T00:00:00Z')      AS to_ts
)
SELECT
  l.srcaddr                       AS src_ip,
  COUNT(*)                        AS reject_rows
  -- , SUM(l.packets)             AS total_packets   -- 追加で見たければコメント解除
  -- , SUM(l.bytes)               AS total_bytes
FROM vpc_flow_logs l
CROSS JOIN params p
WHERE l.dstaddr = p.target_ip
  AND l.action = 'REJECT'
  AND l.log_status = 'OK'
  -- パーティション（day）で絞る
  AND l.day BETWEEN date_format(p.from_ts, '%Y/%m/%d')
                 AND date_format(date_add('day', -1, p.to_ts), '%Y/%m/%d')
  -- 時刻（epoch秒）で厳密に絞る
  AND l.start >= to_unixtime(p.from_ts)
  AND l.start <  to_unixtime(p.to_ts)
GROUP BY l.srcaddr
ORDER BY reject_rows DESC, src_ip;
```

### データテーブルの破棄

```sql
DROP TABLE vpc_flow_logs;
```