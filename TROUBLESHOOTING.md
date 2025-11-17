# Troubleshooting Guide - Distributed Database Setup

This document records the troubleshooting process and solutions encountered during the initial setup of the distributed database system.

## Initial Setup Status

### What Was Working ✅
- All Docker containers started successfully (mysql-master1, mysql-master2, mysql-slave, proxysql)
- MySQL servers initialized with correct server IDs (1, 2, 3)
- GTID mode enabled on all nodes
- Binary logging enabled
- Databases and tables created on all nodes
- Replication user (`replicator`) exists on both masters

### Initial Issues Identified ⚠️

1. **Config File Permissions Warning**
   - Error: `World-writable config file '/etc/mysql/conf.d/replication.cnf' is ignored`
   - Impact: None (replication settings are in command line, so functionality not affected)
   - Status: Non-critical, can be ignored

2. **ProxySQL Servers SHUNNED**
   - All servers showing as SHUNNED in ProxySQL
   - Impact: ProxySQL cannot route queries or handle failover
   - Status: **CRITICAL - Required Fix**

---

## Issue 1: ProxySQL Servers SHUNNED

### Symptoms
```sql
SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers;
-- All servers showing status = 'SHUNNED'
```

### Root Cause
ProxySQL requires a `monitor` user on each MySQL server to perform health checks. This user was missing, causing connection failures.

### Diagnostic Commands Used

```bash
# Check ProxySQL logs for errors
docker-compose logs proxysql | grep -i error

# Check monitor connection logs
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 10;"

# Check if monitor user exists
docker exec mysql-master1 mysql -uroot -prootpassword -e "SELECT user, host FROM mysql.user WHERE user='monitor';"
```

### Error Messages Found
```
Access denied for user 'monitor'@'172.18.0.5' (using password: YES)
```

### Solution

**Step 1: Create monitor user on all MySQL nodes**

```bash
# Master1
docker exec mysql-master1 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"

# Master2
docker exec mysql-master2 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"

# Slave
docker exec mysql-slave mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"
```

**Step 2: Configure ProxySQL to use monitor credentials**

```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SET mysql-monitor_username='monitor'; SET mysql-monitor_password='monitor'; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"
```

**Step 3: Verify fix**

```bash
# Wait 10-15 seconds for health checks to run
sleep 10

# Check server status
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers;"
```

**Result:** Masters showed as ONLINE, but slave remained SHUNNED.

---

## Issue 2: Slave Remaining SHUNNED

### Symptoms
- Master1 and Master2: ONLINE ✅
- Slave: SHUNNED ❌
- Connection logs showed SSL/TLS errors

### Root Cause
ProxySQL was attempting SSL connections to MySQL servers, but MySQL 8.0 uses self-signed certificates that ProxySQL doesn't trust by default.

### Diagnostic Commands Used

```bash
# Test direct connection from ProxySQL to slave
docker exec proxysql mysql -h mysql-slave -P 3306 -u monitor -pmonitor -e "SELECT 1;"
# Result: ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain

# Check SSL-related variables
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM global_variables WHERE variable_name LIKE '%ssl%' OR variable_name LIKE '%SSL%';"

# Check monitor connection logs
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM monitor.mysql_server_connect_log WHERE hostname='mysql-slave' ORDER BY time_start_us DESC LIMIT 5;"
```

### Solution

**Step 1: Disable SSL for ProxySQL monitoring**

```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SET mysql-monitor_ssl='false'; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"
```

**Step 2: Explicitly disable SSL for slave server**

```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "UPDATE mysql_servers SET use_ssl=0 WHERE hostname='mysql-slave'; LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"
```

**Step 3: Force ProxySQL to re-check slave (if still SHUNNED)**

```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "UPDATE mysql_servers SET status='ONLINE' WHERE hostname='mysql-slave'; LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"

# Wait 10 seconds for health checks
sleep 10

# Verify
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers WHERE hostname='mysql-slave';"
```

**Result:** Slave eventually showed as ONLINE ✅

---

## Issue 3: Replication Authentication Failure

### Symptoms
- Replication shows `Slave_IO_Running: Connecting` (never becomes `Yes`)
- Error logs show: `Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection`
- Error code: `MY-002061`

### Root Cause
MySQL 8.0 uses `caching_sha2_password` as the default authentication plugin. This plugin requires SSL/TLS for remote connections, but our replication setup doesn't use SSL. The replication IO thread cannot authenticate without SSL.

### Diagnostic Commands Used

```bash
# Check slave status
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Last_IO_Error"

# Check MySQL error logs
docker-compose logs mysql-master1 | grep -i "authentication\|caching_sha2"

# Check replicator user authentication plugin
docker exec mysql-master1 mysql -uroot -prootpassword -e "SELECT user, host, plugin FROM mysql.user WHERE user='replicator';"
```

### Error Messages Found
```
[ERROR] [MY-010584] [Repl] Replica I/O for channel '': Error connecting to source 'replicator@mysql-master2:3306'. 
This was attempt 7/86400, with a delay of 60 seconds between attempts. 
Message: Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection. 
Error_code: MY-002061
```

### Solution

**Step 1: Change replicator user authentication method**

Change the replicator user from `caching_sha2_password` to `mysql_native_password` on all nodes:

```bash
# Master1
docker exec mysql-master1 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"

# Master2
docker exec mysql-master2 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"

# Slave
docker exec mysql-slave mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
```

**Expected output:**
```
mysql: [Warning] Using a password on the command line interface can be insecure.
(No error message - command succeeded)
```

**Step 2: Restart replication with new authentication**

```bash
# Master1 - stop, reconfigure, restart
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='mysql-master2', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Master2 - stop, reconfigure, restart
docker exec mysql-master2 mysql -uroot -prootpassword -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Slave - stop, reconfigure, restart
docker exec mysql-slave mysql -uroot -prootpassword -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"
```

**Step 3: Verify replication status**

Wait 5-10 seconds, then check:

```bash
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Master_Host|Last_IO_Error"
```

**Expected output:**
```
Master_Host: mysql-master2
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Error: 
```

**Result:** Replication IO thread successfully connects and replication works ✅

---

## Issue 4: CREATE USER Replication Error

### Symptoms
- Replication shows `Slave_SQL_Running: No` or errors in logs
- Error: `Operation CREATE USER failed for 'replicator'@'%'`
- Error code: `MY-001396`
- Error occurs when replication tries to replicate the CREATE USER statement from initialization scripts

### Root Cause
The initialization scripts create the `replicator` user. When replication starts, it tries to replicate this CREATE USER statement, but the user already exists on the replica, causing a conflict.

### Diagnostic Commands Used

```bash
# Check slave SQL status and errors
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_SQL_Running|Last_SQL_Error"

# Check MySQL error logs
docker-compose logs mysql-master1 | grep -i "CREATE USER\|replicator"
```

### Error Messages Found
```
[ERROR] [MY-010584] [Repl] Replica SQL for channel '': Worker 1 failed executing transaction 
'7e6ececb-c185-11f0-9733-a629fd2330b3:7' at source log mysql-bin.000002, end_log_pos 2985090; 
Error 'Operation CREATE USER failed for 'replicator'@'%'' on query. 
Default database: 'mysql'. Query: 'CREATE USER 'replicator'@'%' IDENTIFIED WITH 'caching_sha2_password'...', 
Error_code: MY-001396
```

### Solution

**Option 1: Skip the problematic GTID transaction**

If you see a specific GTID in the error (e.g., `7e6ececb-c185-11f0-9733-a629fd2330b3:7`), skip it:

```bash
# Replace the GTID with the one from your error message
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; SET GTID_NEXT='7e6ececb-c185-11f0-9733-a629fd2330b3:7'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC'; START SLAVE;"
```

**Expected output:**
```
mysql: [Warning] Using a password on the command line interface can be insecure.
(No error message - command succeeded)
```

**Option 2: Skip one transaction (if GTID not available)**

```bash
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; SET GLOBAL sql_slave_skip_counter = 1; START SLAVE;"
```

**Step 3: Verify replication resumes**

```bash
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Last_SQL_Error"
```

**Expected output:**
```
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_SQL_Error: 
```

**Result:** Replication SQL thread resumes and replication works normally ✅

**Note:** This error typically only occurs during initial replication setup. Once replication is established, it shouldn't recur.

---

## Final Working Configuration

### ProxySQL Server Status
```sql
SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers;
```

Expected output:
- `mysql-master1` - hostgroup 0 (writes) - ONLINE
- `mysql-master2` - hostgroup 0 (writes) - ONLINE  
- `mysql-master1` - hostgroup 1 (reads) - ONLINE
- `mysql-master2` - hostgroup 1 (reads) - ONLINE
- `mysql-slave` - hostgroup 1 (reads) - ONLINE

### MySQL Server Configuration
- All servers have `monitor` user with `REPLICATION CLIENT` privilege
- ProxySQL configured with `mysql-monitor_username='monitor'` and `mysql-monitor_password='monitor'`
- SSL disabled for monitoring: `mysql-monitor_ssl='false'`
- Replicator user uses `mysql_native_password` authentication (not `caching_sha2_password`)
- Replication configured and running on all nodes:
  - Master1 replicating from Master2
  - Master2 replicating from Master1
  - Slave replicating from Master1

---

## Common Issues and Quick Fixes

### Issue: ProxySQL shows servers as SHUNNED

**Quick Check:**
```bash
# Check if monitor user exists
docker exec mysql-master1 mysql -uroot -prootpassword -e "SELECT user, host FROM mysql.user WHERE user='monitor';"

# Check ProxySQL monitor settings
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM global_variables WHERE variable_name LIKE 'mysql-monitor%';"
```

**Quick Fix:**
1. Create monitor user on affected node(s)
2. Verify ProxySQL monitor credentials are set
3. Disable SSL if needed: `SET mysql-monitor_ssl='false'`

### Issue: SSL/TLS Connection Errors

**Quick Fix:**
```bash
# Disable SSL for monitoring
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SET mysql-monitor_ssl='false'; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"

# Disable SSL for specific server
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "UPDATE mysql_servers SET use_ssl=0 WHERE hostname='<hostname>'; LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"
```

### Issue: Replication Authentication Failure

**Symptoms:**
- `Slave_IO_Running: Connecting` (never becomes `Yes`)
- Error: `Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection`

**Quick Fix:**
```bash
# Change replicator user to use mysql_native_password on all nodes
docker exec mysql-master1 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-slave mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"

# Restart replication
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; START SLAVE;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "STOP SLAVE; START SLAVE;"
docker exec mysql-slave mysql -uroot -prootpassword -e "STOP SLAVE; START SLAVE;"
```

### Issue: CREATE USER Replication Error

**Symptoms:**
- `Slave_SQL_Running: No`
- Error: `Operation CREATE USER failed for 'replicator'@'%'`

**Quick Fix:**
```bash
# Skip the problematic GTID (replace with actual GTID from error)
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; SET GTID_NEXT='<GTID_FROM_ERROR>'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC'; START SLAVE;"

# Or skip one transaction
docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; SET GLOBAL sql_slave_skip_counter = 1; START SLAVE;"
```

### Issue: ProxySQL Configuration Not Loading

**Quick Check:**
```bash
# Check if init script exists
docker exec proxysql ls -la /docker-entrypoint-initdb.d/

# Check current configuration
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM mysql_servers;"
```

**Quick Fix:**
```bash
# Restart ProxySQL to reload configuration
docker-compose restart proxysql

# Or manually load configuration
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"
```

---

## Useful Diagnostic Commands

### Check Container Status
```bash
docker-compose ps
```

### Check MySQL Server Configuration
```bash
docker exec mysql-master1 mysql -uroot -prootpassword -e "SELECT VERSION(), @@server_id, @@log_bin, @@gtid_mode;"
```

### Check ProxySQL Server Status
```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status, weight FROM runtime_mysql_servers;"
```

### Check ProxySQL Monitor Logs
```bash
# Connection attempts
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM monitor.mysql_server_connect_log ORDER BY time_start_us DESC LIMIT 10;"

# Ping attempts
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM monitor.mysql_server_ping_log ORDER BY time_start_us DESC LIMIT 10;"

# Read-only checks
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM monitor.mysql_server_read_only_log ORDER BY time_start_us DESC LIMIT 10;"
```

### Check ProxySQL Logs
```bash
docker-compose logs proxysql | tail -50
docker-compose logs proxysql | grep -i error
```

### Test Direct MySQL Connections
```bash
# From host machine
mysql -h 127.0.0.1 -P 33061 -u root -prootpassword

# From ProxySQL container
docker exec proxysql mysql -h mysql-master1 -P 3306 -u root -prootpassword -e "SELECT 1;"
```

---

## Lessons Learned

1. **ProxySQL requires monitor user**: Always create a `monitor` user with `REPLICATION CLIENT` privilege on all MySQL servers before configuring ProxySQL.

2. **SSL in containerized environments**: MySQL 8.0 defaults to SSL, but self-signed certificates can cause issues. Disable SSL for monitoring in demo/test environments.

3. **Health check timing**: ProxySQL performs health checks periodically. Wait 10-15 seconds after configuration changes before checking status.

4. **Configuration persistence**: Always use `LOAD ... TO RUNTIME` followed by `SAVE ... TO DISK` when making ProxySQL configuration changes.

5. **Server status can be forced**: If a server is incorrectly marked as SHUNNED, you can manually set it to ONLINE, but this should only be done after fixing the underlying issue.

---

## Prevention for Future Setups

To avoid these issues in future deployments:

1. **Create monitor user in initialization scripts**: Add monitor user creation to `init-master1.sql`, `init-master2.sql`, and `init-slave.sql`

2. **Configure ProxySQL SSL settings**: Set `mysql-monitor_ssl='false'` in ProxySQL configuration file or init script

3. **Set use_ssl=0 in server definitions**: Configure servers with `use_ssl=0` in ProxySQL configuration

4. **Fix replicator authentication in initialization**: Add `ALTER USER` command to change replicator to `mysql_native_password` in initialization scripts, or create the replicator user with `mysql_native_password` from the start:
   ```sql
   CREATE USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass';
   ```

5. **Filter system tables from replication**: Consider filtering `mysql.*` database from replication to avoid CREATE USER conflicts, or use `CREATE USER IF NOT EXISTS` in initialization scripts

6. **Add health check verification**: Include verification steps in setup scripts to confirm all servers are ONLINE before proceeding

---

## Additional Resources

- ProxySQL Documentation: https://proxysql.com/documentation/
- MySQL Replication: https://dev.mysql.com/doc/refman/8.0/en/replication.html
- Docker Compose: https://docs.docker.com/compose/

---

**Last Updated:** 2025-11-14  
**Setup Environment:** Windows 10/11 with Docker Desktop, WSL 2, MySQL 8.0, ProxySQL

