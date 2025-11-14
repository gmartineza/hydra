-- ProxySQL initialization script
-- This will be loaded after ProxySQL starts

-- Set up server groups
INSERT INTO mysql_servers (hostname, port, hostgroup_id, weight, comment) VALUES
('mysql-master1', 3306, 0, 1000, 'Master 1 - Primary Writer'),
('mysql-master2', 3306, 0, 999, 'Master 2 - Secondary Writer'),
('mysql-slave', 3306, 1, 100, 'Slave - Reader')
ON DUPLICATE KEY UPDATE hostname=VALUES(hostname);

-- Configure replication hostgroups
INSERT INTO mysql_replication_hostgroups (writer_hostgroup, reader_hostgroup, comment) VALUES
(0, 1, 'Master-Slave replication group')
ON DUPLICATE KEY UPDATE writer_hostgroup=VALUES(writer_hostgroup);

-- Set up user
INSERT INTO mysql_users (username, password, default_hostgroup, max_connections, default_schema) VALUES
('root', 'rootpassword', 0, 200, 'demo_db')
ON DUPLICATE KEY UPDATE username=VALUES(username);

-- Configure query rules
INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
(1, 1, '^SELECT.*FOR UPDATE', 0, 1),
(2, 1, '^SELECT', 1, 1),
(3, 1, '.*', 0, 1)
ON DUPLICATE KEY UPDATE rule_id=VALUES(rule_id);

-- Load configuration to runtime
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL USERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
LOAD MYSQL VARIABLES TO RUNTIME;
LOAD SCHEDULER TO RUNTIME;

-- Save configuration to disk
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL USERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
SAVE MYSQL VARIABLES TO DISK;
SAVE SCHEDULER TO DISK;

