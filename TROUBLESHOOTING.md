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

4. **Add health check verification**: Include verification steps in setup scripts to confirm all servers are ONLINE before proceeding

---

## Additional Resources

- ProxySQL Documentation: https://proxysql.com/documentation/
- MySQL Replication: https://dev.mysql.com/doc/refman/8.0/en/replication.html
- Docker Compose: https://docs.docker.com/compose/

---

**Last Updated:** 2025-11-14  
**Setup Environment:** Windows 10/11 with Docker Desktop, WSL 2, MySQL 8.0, ProxySQL

