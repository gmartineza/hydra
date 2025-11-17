#!/bin/bash

# CRUD and Replication Test Script
# Tests CRUD operations through ProxySQL and verifies replication across all nodes

PROXYSQL_HOST="127.0.0.1"
PROXYSQL_PORT="6033"
PROXYSQL_ADMIN_PORT="6032"
MYSQL_USER="root"
MYSQL_PASS="rootpassword"
DB_NAME="demo_db"

# Function to execute SQL through ProxySQL
execute_sql() {
    docker exec proxysql mysql -h $PROXYSQL_HOST -P $PROXYSQL_PORT -u $MYSQL_USER -p$MYSQL_PASS $DB_NAME -e "$1" 2>&1
}

# Function to execute SQL directly on a node
execute_sql_node() {
    local node=$1
    local sql=$2
    docker exec $node mysql -uroot -prootpassword $DB_NAME -e "$sql" 2>&1
}

echo "=========================================="
echo "CRUD and Replication Test"
echo "=========================================="
echo ""

# Check statuses
echo "Checking ProxySQL server status:"
docker exec proxysql mysql -h 127.0.0.1 -P $PROXYSQL_ADMIN_PORT -u admin -padmin -e "
SELECT hostname, port, hostgroup_id, status, weight 
FROM runtime_mysql_servers 
ORDER BY hostgroup_id, weight DESC;
" 2>/dev/null
echo ""

echo "Checking replication status:"
echo "Master1:"
execute_sql_node mysql-master1 "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master" || echo "  No replication"
echo ""
echo "Master2:"
execute_sql_node mysql-master2 "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master" || echo "  No replication"
echo ""
echo "Slave:"
execute_sql_node mysql-slave "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master" || echo "  No replication"
echo ""

# Wait for replication
sleep 3

# CREATE
echo "=========================================="
echo "CREATE - Inserting product through ProxySQL"
echo "INSERT INTO products (name, description, price, stock_quantity) VALUES ('CRUD Test Product', 'Product for CRUD testing', 199.99, 100);"
echo "=========================================="
execute_sql "INSERT INTO products (name, description, price, stock_quantity) VALUES 
('CRUD Test Product', 'Product for CRUD testing', 199.99, 100);"
echo ""

PRODUCT_ID=$(execute_sql "SELECT id FROM products WHERE name = 'CRUD Test Product' ORDER BY id DESC LIMIT 1;" | grep -v id | tr -d '[:space:]')
echo "Created product ID: $PRODUCT_ID"
echo ""

sleep 3

echo "Checking replication - SELECT from each node:"
echo "ProxySQL:"
execute_sql "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master1:"
execute_sql_node mysql-master1 "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master2:"
execute_sql_node mysql-master2 "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Slave:"
execute_sql_node mysql-slave "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""

# # READ
# echo "=========================================="
# echo "READ - Reading through ProxySQL"
# echo "=========================================="
# execute_sql "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
# echo ""

# sleep 2

# echo "Checking replication - SELECT from each node:"
# echo "ProxySQL:"
# execute_sql "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
# echo ""
# echo "Master1:"
# execute_sql_node mysql-master1 "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
# echo ""
# echo "Master2:"
# execute_sql_node mysql-master2 "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
# echo ""
# echo "Slave:"
# execute_sql_node mysql-slave "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
# echo ""

# UPDATE
echo "=========================================="
echo "UPDATE - Updating product through ProxySQL"
echo "UPDATE products SET price = 249.99 WHERE name = 'CRUD Test Product';"
echo "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo "=========================================="
execute_sql "UPDATE products SET price = 249.99 WHERE name = 'CRUD Test Product';"
echo ""

sleep 3

echo "Checking replication - SELECT from each node:"
echo "ProxySQL:"
execute_sql "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master1:"
execute_sql_node mysql-master1 "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master2:"
execute_sql_node mysql-master2 "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Slave:"
execute_sql_node mysql-slave "SELECT id, name, price, stock_quantity FROM products WHERE name = 'CRUD Test Product';"
echo ""

# DELETE
echo "=========================================="
echo "DELETE - Deleting product through ProxySQL"
echo "DELETE FROM products WHERE name = 'CRUD Test Product';"
echo "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
echo "=========================================="
execute_sql "DELETE FROM products WHERE name = 'CRUD Test Product';"
echo ""

sleep 3

echo "Checking replication - SELECT from each node:"
echo "ProxySQL:"
execute_sql "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master1:"
execute_sql_node mysql-master1 "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Master2:"
execute_sql_node mysql-master2 "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
echo ""
echo "Slave:"
execute_sql_node mysql-slave "SELECT id, name, price FROM products WHERE name = 'CRUD Test Product';"
echo ""

echo "=========================================="
echo "Test Complete"
echo "=========================================="
