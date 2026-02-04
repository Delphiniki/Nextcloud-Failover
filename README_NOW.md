# Key considerations:
- Assume that we have 3 servers ,one primary and two backup.Let's say
  node1 is primary and node2 ,node3 - backup serversI am using Tailscale and every server is in same tailnet.
```
  node1 - ip address: 100.xxx.xxx.xxx
  node2 - ip address: 100.yyy.yyy.yyy
  node3 - ip address: 100.zzz.zzz.zzz 
```
- Data directory "nextcloud_data" shared between nodes with Syncthing.
  In syncthing GUI just set directory "/data1" on every node and share it across all nodes with same Folder Label and Folder ID.
- Use same  "config" settings .Just add all public ip addresses of the 3 nodes in 'trusted_domains'.It is better to use same secret,passwordsalt and instanceid across all configurations.
- Add or change these variables in config/config.php file:
```php
  'overwriteprotocol' => 'https',
  'overwrite.cli.url' => 'https://node1_ip_address',
  'trusted_domains' =>
  array (
    0 => '127.0.0.1',
    1 => 'node1_public_ip_address',
    2 => 'node2_public_ip_address',
    3 => 'node3_public_ip_address',
    4 => 'localhost',
    5 => 'app.example.com', // cloudflare domain name 
  ),
```
- Make sure the 'config' and 'nextcloud_data' directory has the right permissions - owner:  www-data and permissions 755 .Especially after edit the config.php.Use these commands :
```bash
chown -R www-data:www-data config nextcloud_data
chmod -R 755 config nextcloud_data
```
- Create cronjobs : use 'sudo crontab -e' and add lines:
```bash
# Nextcloud maintenance (on all nodes): 
*/5 * * * *     docker exec -u www-data nextcloud php -f /var/www/html/cron.php
*/5 * * * *     docker exec -u www-data nextcloud php /var/www/html/occ files:scan --all
# Nextcloud failover (only on node2 and node3):
* * * * *       /bin/bash       /opt/scripts/failover.sh
```

Create database manually before starting the nextcloud service:
```bash
mysql -h127.0.0.1 -uroot -p   ### use root password set in docker compose file. 

CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'nextcloud'@'%' IDENTIFIED BY 'nextcloud';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'%';
FLUSH PRIVILEGES;
QUIT;
```
## Creating a Cloudflare certificate for nginx server:
1. Generate the Certificate
Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and select your specific domain.
Navigate to SSL/TLS in the left-hand sidebar and select Origin Server.
Click the Create Certificate button.
Choose your configuration:
Generate private key and CSR with Cloudflare: The easiest option, where Cloudflare handles the Certificate Signing Request (CSR) for you.
Hostnames: Ensure your apex domain (e.g., example.com) and wildcard (e.g., *.example.com) are listed.
Validity: Select a duration (default is 15 years).
Click Create. 
2. Save Your Credentials
Copy the Origin Certificate: This is the public part of the certificate.
Copy the Private Key: This is critical. You will only see the private key once during this step. If you lose it, you must revoke the certificate and start over.
Save both as separate files on your computer (e.g., cert.pem and key.pem).
Add both files : cert.pem and key.pem in folder "certs"
Change files permissions :
```bash
chmod 600 cert/cert.pem cert/key.pem
```
- Only on first start stack on node1 (primary server) with uncommented "command: --wsrep-new-cluster" .This way the node1 mariadb will bootstrap the galera cluster.Wait 15s then start node2 and node3 stacks to join the cluster.After that you can comment out that option on node1 - "#command: --wsrep-new-cluster"
  - The folders structure looks like this way:
```
  .

└── nextcloud    
    ├── certs
    ├── config
    ├── docker-compose.yaml
    ├── galera.cnf
    ├── haproxy.cfg
    ├── mysql-data
    ├── nextcloud_data
    ├── nginx.conf
    └── syncthing_config
```
- The first failover script on backup server1 (node2) monitor primary server,and if primary is down ,then script switch the target ip address for A record app.example.com to the ip of node2 (itself).When primary server (node1) is up again,script revert the ip address of primary server in A record again.
- The second failover script on backup server2 (node3) ,monitors primary server and backup server1 (node2).If primary is down AND node2 is down ,then script switch the A record ip address to ip of itself (node3).If primary is up switch the A record ip to primary .And if node2 is up - hand over control to node2.