
SSH Key Deploy Script
=====================
Author: Mirko Kaiser, http://www.KaiserSoft.net   
Project URL: https://github.com/KaiserSoft/SSH-Key-Deploy-v2/    
Copyright (C) 2018 Mirko Kaiser    
First created in Germany on 2018-01-08    
License: New BSD License

Support the software with Bitcoins !thank you!: 	 19wNLGAGfBzSpWiqShBZdJ2FsEcMzvLVLt

Support the software with Bitcoin Cash !thank you!:  12B6uJgCmU73VTRRvtkfzB2zrXVjetcFt9


# About #
script collection to simplify management of the authorized_keys file. Keys are stored in an SQLite3 
database and may be grouped with a one to many relation ship. This allows you to create server groups 
and grant some keys access to certain groups (servers) while preventing access to other servers.
Keys may be disabled in the database which ensures that they are removed from authorized_keys the 
next time ssh-key-deploy.sh is executed.    
*Please note*, you must set keys to disabled or use the --force option to ensure old keys are removed 
from authorized_keys.

The idea is to host these files in a private git repository and have any servers pull from  
the repository using personal access tokens and update the authorized_keys file automatically.
Alternatively you may use a tool like Ansible to trigger updates on your servers manually (more secure).

An alternative version which does not use an SQlite3 database is available here: https://github.com/KaiserSoft/SSH-Key-Deploy/


# Requirements #
* Linux - tested on Debian 8 and 9
* bash shell
* sqlite3
* OpenSSH 6 and 7 but version 7 is recommended


# Example #
Example scenario (check ssh-key-deploy.sh --help for list of all options)
1) git clone https://<USER_NAME>:<PERSONAL_TOKEN>@git.YourServer.com/SSH-Key-Deploy-v2-PRIVATE.git

2) Create a crontab entry like this to update authorized_keys every 15 minutes    
	*/15 * * * *  cd /root/SSH-Key-Deploy-v2-PRIVATE && git pull origin && ./ssh-key-deploy.sh -g 'SomeGroup'

3) Use the supplied ssh-key-manage.sh script to add new keys to the database, commit and push


Or using a more manual / more secure approach. You could use a tool like Ansible to initiate a key update 
on all your servers by copying the latest database and ssh-key-deploy.sh to your systems. 
Then run ssh-key-deploy.sh to update the authorized_keys file.

    
    
# Command Examples #
* add key in id_rsa.pub file and add it to the WebServers and Firewall group    
./ssh-key-manage.sh -f id_rsa.pub -g 'WebServers,Firewall'

* display overview of all keys using sha256 fingerprints    
./ssh-key-manage.sh --overview

* display overview of all keys using md5 fingerprints   
./ssh-key-manage.sh --overview --md5

* disable the key in id_rsa.pub    
./ssh-key-manage.sh -f id_rsa.pub --disable

* disable key with ID 5 The ID is displayed with --overview    
./ssh-key-manage.sh --kid 5 --disable

* delete key with ID 4 The ID is displayed with --overview    
./ssh-key-manage.sh --kid 4 --delete

* remove key with ID 3 from the Firewall group    
./ssh-key-manage.sh --kid 3 -g '-Firewall'

* create a fresh database with default database name (SSHkeys.db)    
./ssh-key-manage.sh --new-db

* write keys in group 'Firewall' to current users authorized_keys file. Hide INFO messages (-q)    
./ssh-key-deploy.sh -g 'Firewall' -q

* write keys in group 'Firewall' to current users authorized_keys file. Delete file first to ensure it only contains keys from the database    
./ssh-key-deploy.sh -g 'Firewall' --force

* write all enabled keys to current users authorized_keys file    
./ssh-key-deploy.sh

* write all enabled keys to the file specified with -f    
./ssh-key-deploy.sh -f /etc/ssh/authorized_keys/root

   
   
   
# Database Format #
You may create a fresh database with ssh-key-manage.sh --new-db

 	CREATE TABLE sshkeys(
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		SSHKey TEXT UNIQUE,
		KeyName TEXT NULL,
		enabled INTEGER NOT NULL,
		added DATETIME DEFAULT CURRENT_TIMESTAMP );

 	CREATE TABLE sshgroups(
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		id_sshkey INTEGER NOT NULL,
		KeyGroup TEXT NOT NULL );


