# Distributed Database System - Master-Master-Slave Setup

This project demonstrates a homogeneous distributed database system with:
- **2 Master nodes** in master-master replication
- **1 Slave node** replicating from Master1
- **ProxySQL** for automatic failover and load balancing
- **Docker containers** for easy deployment

## Architecture

```
┌─────────────┐         ┌─────────────┐
│  Master 1   │◄───────►│  Master 2   │
│  (Write)    │         │  (Write)    │
└──────┬──────┘         └─────────────┘
       │
       │ (replicates)
       ▼
┌─────────────┐
│   Slave     │
│   (Read)    │
└─────────────┘
       ▲
       │
┌──────┴──────┐
│  ProxySQL   │ (Routes queries, handles failover)
│  Port 6033  │
└─────────────┘
```

## Prerequisites

**⚠️ IMPORTANT: Before starting, please review [DEPENDENCIES.md](DEPENDENCIES.md) for complete installation instructions and system requirements.**

Required software:
- **Docker Desktop for Windows** (with WSL 2 backend)
- **WSL 2** (Windows Subsystem for Linux)
- **MySQL client** (optional - can use Docker MySQL client instead)
- **Git Bash or WSL terminal** (for bash scripts, or use PowerShell manually)

See [DEPENDENCIES.md](DEPENDENCIES.md) for detailed installation steps, configuration tweaks, and troubleshooting.

## Quick Start

### 1. Start the Database Cluster

```bash
docker-compose up -d
```

This will start:
- `mysql-master1` on port 33061
- `mysql-master2` on port 33062
- `mysql-slave` on port 33063
- `proxysql` on ports 6033 (MySQL) and 6032 (Admin)

### 2. Wait for Containers to Initialize

Wait about 30-60 seconds for all MySQL instances to fully start:

```bash
docker-compose ps
```

Check logs to ensure all containers are ready:

```bash
docker-compose logs mysql-master1
docker-compose logs mysql-master2
docker-compose logs mysql-slave
```

### 3. Configure ProxySQL Monitor User

Before setting up replication, create the monitor user for ProxySQL health checks:

```bash
# Create monitor user on all nodes
docker exec mysql-master1 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"
docker exec mysql-slave mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"

# Configure ProxySQL to use monitor credentials
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SET mysql-monitor_username='monitor'; SET mysql-monitor_password='monitor'; SET mysql-monitor_ssl='false'; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"
```

Wait 10-15 seconds, then verify ProxySQL can see all servers:

```bash
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers;"
```

All servers should show `status = 'ONLINE'`.

### 4. Set Up Replication

**Important:** MySQL 8.0 uses `caching_sha2_password` by default, which requires SSL. We need to change the replicator user to use `mysql_native_password` for replication to work without SSL.

First, update the authentication method for the replicator user:

```bash
# Change replicator user to use mysql_native_password on all nodes
docker exec mysql-master1 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-slave mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
```

Then configure replication:

```bash
# Configure Master2 to replicate from Master1
docker exec mysql-master2 mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Configure Master1 to replicate from Master2
docker exec mysql-master1 mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master2', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Configure Slave to replicate from Master1
docker exec mysql-slave mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"
```

**Note:** If you see CREATE USER errors in the logs after starting replication, you may need to skip the initial GTID transaction that tries to replicate the user creation. See Troubleshooting section for details.

**Alternative:** Run the replication setup script (if using bash):

```bash
chmod +x setup-replication.sh
./setup-replication.sh
```

**Note for Windows:** If you're on Windows and can't run the bash script directly, use the manual commands above.

### 5. Verify Replication

Check replication status on each node:

```bash
# Master1 replicating from Master2
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Master_Host|Last_IO_Error|Last_SQL_Error"

# Master2 replicating from Master1
docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Master_Host|Last_IO_Error|Last_SQL_Error"

# Slave replicating from Master1
docker exec mysql-slave mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Master_Host|Last_IO_Error|Last_SQL_Error"
```

**Expected output:**
- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Master_Host: mysql-master1` (for Master2 and Slave)
- `Master_Host: mysql-master2` (for Master1)
- `Last_IO_Error:` (should be empty)
- `Last_SQL_Error:` (should be empty)

## Database Schema

The demo database includes two tables:

### Products Table
- `id` - Primary key
- `name` - Product name
- `description` - Product description
- `price` - Product price
- `stock_quantity` - Available stock
- `created_at` - Creation timestamp
- `updated_at` - Last update timestamp

### Orders Table
- `id` - Primary key
- `product_id` - Foreign key to products
- `quantity` - Order quantity
- `total_price` - Total order price
- `customer_name` - Customer name
- `order_date` - Order timestamp
- `status` - Order status (pending/completed/cancelled)

## Testing CRUD Operations

### Connect Through ProxySQL

ProxySQL automatically routes:
- **Write queries** (INSERT, UPDATE, DELETE) → Master nodes (hostgroup 0)
- **Read queries** (SELECT) → Slave node (hostgroup 1)

```bash
mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db
```

### Run CRUD Test Script

```bash
mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db < test-crud.sql
```

Or execute the SQL file interactively:

```bash
mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db
source test-crud.sql
```

### Manual CRUD Testing

```sql
-- CREATE
INSERT INTO products (name, description, price, stock_quantity) 
VALUES ('New Product', 'Description', 99.99, 50);

-- READ
SELECT * FROM products;

-- UPDATE
UPDATE products SET price = 89.99 WHERE name = 'New Product';

-- DELETE
DELETE FROM products WHERE name = 'New Product';
```

## Testing Failover

### Automatic Failover Test

Run the failover test script:

```bash
chmod +x test-failover.sh
./test-failover.sh
```

**Note for Windows:** Use Git Bash, WSL, or execute commands manually (see below).

### Manual Failover Test

1. **Check current state:**
   ```bash
   docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status, weight FROM runtime_mysql_servers WHERE hostgroup_id = 0;"
   ```

2. **Insert test data:**
   ```bash
   mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db -e "INSERT INTO products (name, description, price, stock_quantity) VALUES ('Failover Test', 'Testing', 99.99, 10);"
   ```

3. **Stop Master1:**
   ```bash
   docker stop mysql-master1
   ```

4. **Wait a few seconds** for ProxySQL to detect the failure (it checks every 2 seconds)

5. **Verify ProxySQL switched to Master2:**
   ```bash
   docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT hostname, port, hostgroup_id, status FROM runtime_mysql_servers WHERE hostgroup_id = 0;"
   ```

6. **Test CRUD operations** (should work through Master2):
   ```bash
   mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db -e "INSERT INTO products (name, description, price, stock_quantity) VALUES ('Post-Failover', 'Created after failover', 149.99, 20);"
   mysql -h 127.0.0.1 -P 6033 -u root -prootpassword demo_db -e "SELECT * FROM products WHERE name LIKE '%Failover%';"
   ```

7. **Restart Master1:**
   ```bash
   docker start mysql-master1
   ```

8. **Reconfigure Master1 to catch up:**
   ```bash
   docker exec mysql-master1 mysql -uroot -prootpassword -e "STOP SLAVE; CHANGE MASTER TO MASTER_HOST='mysql-master2', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"
   ```

## Manual Setup (Windows/Alternative)

If you can't run the bash scripts, execute these commands manually:

### Step 1: Create Monitor User (Required for ProxySQL)

```bash
# Create monitor user on all nodes
docker exec mysql-master1 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"
docker exec mysql-slave mysql -uroot -prootpassword -e "CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitor'; GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%'; FLUSH PRIVILEGES;"

# Configure ProxySQL
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SET mysql-monitor_username='monitor'; SET mysql-monitor_password='monitor'; SET mysql-monitor_ssl='false'; LOAD MYSQL VARIABLES TO RUNTIME; SAVE MYSQL VARIABLES TO DISK;"
```

### Step 2: Fix Replication Authentication

MySQL 8.0 requires changing the replicator user authentication method:

```bash
# Change replicator user to use mysql_native_password on all nodes
docker exec mysql-master1 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-master2 mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
docker exec mysql-slave mysql -uroot -prootpassword -e "ALTER USER 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'replicatorpass'; FLUSH PRIVILEGES;"
```

### Step 3: Set Up Master-Master Replication

```bash
# Configure Master2 to replicate from Master1
docker exec mysql-master2 mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Configure Master1 to replicate from Master2
docker exec mysql-master1 mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master2', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"

# Configure Slave to replicate from Master1
docker exec mysql-slave mysql -uroot -prootpassword -e "CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"
```

**Note:** If you encounter CREATE USER errors in the logs, see the Troubleshooting section for how to skip the problematic GTID transaction.

### Verify Replication

```bash
# Check Master1
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Slave_IO_Running Slave_SQL_Running"

# Check Master2
docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Slave_IO_Running Slave_SQL_Running"

# Check Slave
docker exec mysql-slave mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Slave_IO_Running Slave_SQL_Running"
```

## ProxySQL Admin Interface

Access ProxySQL admin interface:

```bash
mysql -h 127.0.0.1 -P 6032 -u admin -padmin
```

Useful commands:

```sql
-- View server status
SELECT hostname, port, hostgroup_id, status, weight, comment 
FROM runtime_mysql_servers;

-- View query statistics
SELECT hostgroup, digest_text, count_star, sum_time 
FROM stats_mysql_query_digest 
ORDER BY sum_time DESC 
LIMIT 10;

-- Reload configuration
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
```

## Monitoring

### Check Container Status

```bash
docker-compose ps
```

### View Logs

```bash
# All containers
docker-compose logs -f

# Specific container
docker-compose logs -f mysql-master1
docker-compose logs -f proxysql
```

### Check Replication Lag

```bash
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Seconds_Behind_Master"
docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Seconds_Behind_Master"
docker exec mysql-slave mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | findstr "Seconds_Behind_Master"
```

## Troubleshooting

### Replication Not Working

1. Check if replication user exists:
   ```bash
   docker exec mysql-master1 mysql -uroot -prootpassword -e "SELECT user, host FROM mysql.user WHERE user='replicator';"
   ```

2. Check firewall/network connectivity between containers:
   ```bash
   docker exec mysql-master1 ping -c 2 mysql-master2
   ```

3. Check MySQL error logs:
   ```bash
   docker-compose logs mysql-master1 | tail -50
   ```

### ProxySQL Not Routing Correctly

1. Check ProxySQL server status:
   ```bash
   docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT * FROM runtime_mysql_servers;"
   ```

2. Reload ProxySQL configuration:
   ```bash
   docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK;"
   ```

### Data Not Syncing

1. Check GTID status:
   ```bash
   docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW MASTER STATUS\G"
   ```

2. Reset replication if needed (be careful - this will lose data):
   ```bash
   docker exec mysql-slave mysql -uroot -prootpassword -e "STOP SLAVE; RESET SLAVE; CHANGE MASTER TO MASTER_HOST='mysql-master1', MASTER_USER='replicator', MASTER_PASSWORD='replicatorpass', MASTER_AUTO_POSITION=1; START SLAVE;"
   ```

## Cleanup

To stop and remove all containers and volumes:

```bash
docker-compose down -v
```

## Architecture Notes

- **Master-Master Replication**: Both masters can accept writes, with auto-increment offset to prevent ID conflicts
- **GTID-based Replication**: Uses Global Transaction Identifiers for reliable replication
- **ProxySQL Failover**: Automatically detects master failures and routes traffic to available master
- **Read-Write Splitting**: Reads go to slave, writes go to masters
- **Automatic Failover**: ProxySQL monitors servers and automatically removes failed nodes from the pool

## For Your Presentation

Key points to demonstrate:

1. **Synchronization**: Show data written to one master appearing on all nodes
2. **Failover**: Stop a master and show operations continuing automatically
3. **CRUD Operations**: Demonstrate Create, Read, Update, Delete through ProxySQL
4. **Data Consistency**: Verify data is identical across all nodes after operations

Good luck with your evaluation! 🚀

