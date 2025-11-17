#!/bin/bash

# Script to fix ProxySQL routing for master-master setup
# Removes replication hostgroups and ensures weight-based routing

echo "Fixing ProxySQL routing configuration..."

# Connect to ProxySQL admin and remove replication hostgroups
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "
DELETE FROM mysql_replication_hostgroups;
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
"

# Verify servers are configured with weights
echo ""
echo "Current server configuration:"
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "
SELECT hostname, port, hostgroup_id, weight, status, comment 
FROM runtime_mysql_servers 
WHERE hostgroup_id = 0
ORDER BY weight DESC;
"

# Verify replication hostgroups are removed
echo ""
echo "Replication hostgroups (should be empty):"
docker exec proxysql mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "
SELECT * FROM mysql_replication_hostgroups;
"

echo ""
echo "Done! ProxySQL will now use weight-based routing."
echo "Master1 (weight 1000) will be preferred, Master2 (weight 999) is failover."

