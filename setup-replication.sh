#!/bin/bash

# Script to set up replication between MySQL nodes
# This should be run after all containers are up and running

echo "Setting up Master-Master replication..."

# Wait for MySQL servers to be ready
echo "Waiting for MySQL servers to be ready..."
sleep 10

# Get GTID position from master1
MASTER1_GTID=$(docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW MASTER STATUS\G" | grep "Executed_Gtid_Set" | awk '{print $2}')

# Configure master2 to replicate from master1
echo "Configuring master2 to replicate from master1..."
docker exec mysql-master2 mysql -uroot -prootpassword -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='mysql-master1',
  MASTER_USER='replicator',
  MASTER_PASSWORD='replicatorpass',
  MASTER_AUTO_POSITION=1;
START SLAVE;
"

# Get GTID position from master2
MASTER2_GTID=$(docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW MASTER STATUS\G" | grep "Executed_Gtid_Set" | awk '{print $2}')

# Configure master1 to replicate from master2
echo "Configuring master1 to replicate from master2..."
docker exec mysql-master1 mysql -uroot -prootpassword -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='mysql-master2',
  MASTER_USER='replicator',
  MASTER_PASSWORD='replicatorpass',
  MASTER_AUTO_POSITION=1;
START SLAVE;
"

# Configure slave to replicate from master1
echo "Configuring slave to replicate from master1..."
docker exec mysql-slave mysql -uroot -prootpassword -e "
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='mysql-master1',
  MASTER_USER='replicator',
  MASTER_PASSWORD='replicatorpass',
  MASTER_AUTO_POSITION=1;
START SLAVE;
"

echo "Replication setup complete!"
echo ""
echo "Checking replication status..."
echo ""
echo "Master1 Slave Status:"
docker exec mysql-master1 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
echo ""
echo "Master2 Slave Status:"
docker exec mysql-master2 mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"
echo ""
echo "Slave Status:"
docker exec mysql-slave mysql -uroot -prootpassword -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master"

