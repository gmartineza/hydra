#!/bin/bash

# Failover Test Script
# This script demonstrates automatic failover when a master node fails

PROXYSQL_HOST="127.0.0.1"
PROXYSQL_PORT="6033"
MYSQL_USER="root"
MYSQL_PASS="rootpassword"
DB_NAME="demo_db"

echo "=========================================="
echo "Distributed Database Failover Test"
echo "=========================================="
echo ""

# Function to execute SQL through ProxySQL
execute_sql() {
    mysql -h $PROXYSQL_HOST -P $PROXYSQL_PORT -u $MYSQL_USER -p$MYSQL_PASS $DB_NAME -e "$1"
}

# Function to check which node is handling writes
check_writer() {
    echo "Checking current writer node..."
    docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "
    SELECT hostname, port, hostgroup_id, status, weight, comment 
    FROM runtime_mysql_servers 
    WHERE hostgroup_id = 0 
    ORDER BY weight DESC;
    " 2>/dev/null
}

echo "Step 1: Initial State - All nodes running"
echo "----------------------------------------"
check_writer
echo ""

echo "Step 2: Inserting test data through ProxySQL"
echo "----------------------------------------"
execute_sql "INSERT INTO products (name, description, price, stock_quantity) VALUES 
('Test Product', 'Failover test product', 99.99, 10);"
execute_sql "SELECT id, name, price FROM products WHERE name = 'Test Product';"
echo ""

echo "Step 3: Checking data replication"
echo "----------------------------------------"
echo "Data on Master1:"
docker exec mysql-master1 mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name = 'Test Product';" 2>/dev/null
echo ""
echo "Data on Master2:"
docker exec mysql-master2 mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name = 'Test Product';" 2>/dev/null
echo ""
echo "Data on Slave:"
docker exec mysql-slave mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name = 'Test Product';" 2>/dev/null
echo ""

echo "Step 4: Stopping Master1 to trigger failover"
echo "----------------------------------------"
echo "Stopping mysql-master1 container..."
docker stop mysql-master1
sleep 5

echo "ProxySQL should automatically detect the failure and route to Master2"
check_writer
echo ""

echo "Step 5: Testing CRUD operations through ProxySQL (should use Master2 now)"
echo "----------------------------------------"
execute_sql "INSERT INTO products (name, description, price, stock_quantity) VALUES 
('Post-Failover Product', 'Created after master1 failure', 149.99, 20);"
execute_sql "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;"
echo ""

echo "Step 6: Verifying data on remaining nodes"
echo "----------------------------------------"
echo "Data on Master2:"
docker exec mysql-master2 mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;" 2>/dev/null
echo ""
echo "Data on Slave:"
docker exec mysql-slave mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;" 2>/dev/null
echo ""

echo "Step 7: Restarting Master1"
echo "----------------------------------------"
docker start mysql-master1
sleep 10

echo "Reconfiguring Master1 to catch up with Master2..."
docker exec mysql-master1 mysql -uroot -prootpassword -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='mysql-master2',
  MASTER_USER='replicator',
  MASTER_PASSWORD='replicatorpass',
  MASTER_AUTO_POSITION=1;
START SLAVE;
" 2>/dev/null

sleep 5
echo "Master1 should now be synced with Master2"
echo ""

echo "Step 8: Final verification - All nodes should have same data"
echo "----------------------------------------"
echo "Data on Master1:"
docker exec mysql-master1 mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;" 2>/dev/null
echo ""
echo "Data on Master2:"
docker exec mysql-master2 mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;" 2>/dev/null
echo ""
echo "Data on Slave:"
docker exec mysql-slave mysql -uroot -prootpassword $DB_NAME -e "SELECT id, name, price FROM products WHERE name LIKE '%Failover%' ORDER BY id;" 2>/dev/null
echo ""

echo "=========================================="
echo "Failover Test Complete!"
echo "=========================================="
