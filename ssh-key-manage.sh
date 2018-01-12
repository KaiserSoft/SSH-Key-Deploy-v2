#!/bin/bash

# script to manage ssh keys in database
#
# Author: Mirko Kaiser, http://www.KaiserSoft.net
# Project URL: https://github.com/KaiserSoft/SSH-Key-Deploy-v2/
#
# Support the software with Bitcoins !thank you!: 	 19wNLGAGfBzSpWiqShBZdJ2FsEcMzvLVLt
#
# Support the software with Bitcoin Cash !thank you!:  12B6uJgCmU73VTRRvtkfzB2zrXVjetcFt9
#
# Copyright (C) 2015 Mirko Kaiser
# First created in Germany on 2015-09-20
# License: New BSD License

# Usage displayed with --help or more find more examples in README.md
#	./ssh-key-manage.sh --help
#

DB="SSHkeys.db"
ProcessReturn=0
KeyState=1 # 0 = add key disabled, 1 = add key enabled (default)
KeyStateChange=0 # used to detect a possible change from enabled to disabled or vice versa
SSHGroupOption="" # holds groups for the key
HasingAlgo="sha256" # only for OpenSSH 7 and maybe later
ShowSSHKeyOverview=0 # true if the overview should be build
GroupList="" # used to show groups after adding or for overview
KeyDelete=0 # 1 if key should be deleted from database
SelectedKeyID="" # will contain the database ID of the key which should be modified, if passed with --kid
CreateNewDB=0 # set to one if a new DB needs to be created
FingerPrint="" # will contain an SSH finger print
if [ $(ssh -V 2>&1 | cut -c9-9) -lt 7 ]; then SSHVersion=6; HasingAlgo=""; else SSHVersion=7; fi
sqlite3 --version > /dev/null 2>&1 || { printf "ERROR: SQlite3 is not installed or not in path!\n"; exit 1; }



function showHelp(){
	printf "\n"
	printf "Usage: ssh-key-manage.sh [OPTIONS]\n"
	printf "OPTIONS include:\n"
	printf "  -d FILENAME\t use custom database file '/some/path/foo.db'\n"
	printf "  -f FILENAME\t use custom authorized_keys file '/some/path/authorized_keys'\n"
	printf "  -g GROUP\t comma separated list of groups. Prepend with - to remove group membership 'foo,-bar'\n"
	printf "  --kid ID\t specify key in database by ID. Get ID with --overview \n"
	printf "  --delete\t delete key specified with -f or --kid\n"
	printf "  --disable\t disable key specified with -f or --kid\n"
	printf "  --enable\t enable key specified with -f or --kid\n"
	printf "  --new-db\t create a new SQlite3 database\n"
	printf "  --md5\t\t md5 finger prints\n"
	printf "  --sha256\t sha256 finger prints (default)\n"
	printf "  --help\t this help overview\n"
	printf "  --overview\t show overview of all tickets in database\n"
	printf "\t\t <key ID> | < + (enabled) / - (disabled)> | <key finger print>"
	printf "\n"
}


# creates a fingerprint from the SSH key
function fingerprintKey(){
	if [ "$HasingAlgo" = "" ]; then
		FingerPrint=$( ssh-keygen -l -f /dev/stdin <<< "$1" )
	else
		FingerPrint=$(ssh-keygen -E $HasingAlgo -l -f - <<< "$1" )
	fi
}

# creates a fresh database
function createNewDB(){
	if [ -f "$DB" ]; then
		printf "ERROR: a file with that name already exists - '$DB'\n"
		exit 99
	fi
	
	local TABL1="CREATE TABLE sshkeys( id INTEGER PRIMARY KEY AUTOINCREMENT, SSHKey TEXT NOT NULL UNIQUE, KeyName TEXT NULL, enabled INTEGER NOT NULL, added DATETIME DEFAULT CURRENT_TIMESTAMP );"
	local TABL2="CREATE TABLE sshgroups( id INTEGER PRIMARY KEY AUTOINCREMENT, id_sshkey INTEGER NOT NULL, KeyGroup TEXT NOT NULL )"

	sqlite3 $DB "$TABL1;$TABL2"
	if [ $? -ne 0 ]; then
		printf "ERROR: unable to create a new database\n";
		exit 99
	fi
	
	printf "INFO: empty database created\n"
	exit 0
}


# load SSH key into variables
function loadKeyFromFile(){
	if [ ! -f "$1" ]; then
		printf "ERROR: file not found - $1\n"
		exit 1
	fi

	# read and split content by space
	IFS=' ' read -ra FILECONTENT <<< $(cat "$1")
	SSHKey="${FILECONTENT[0]} ${FILECONTENT[1]}"
	SSHKeyName="${FILECONTENT[2]}"

}

# loads key string from database
function loadKeyFromDB(){
	local QUERY="SELECT SSHKey, KeyName FROM sshkeys WHERE id = $1"
	IFS='|'
	local SSHKeyFromDB=($(sqlite3 -separator '|' $DB "$QUERY"))
	
	SSHKey="${SSHKeyFromDB[0]}"
	SSHKeyName="${SSHKeyFromDB[1]}"
}

function addKeyToGroup(){
	if [ -z "$1" ]; then
		printf "ERROR: invalid key ID\n"
		exit 5
	fi

	IFS=',' read -ra SSHGroups <<< "$SSHGroupOption"
	for i in "${SSHGroups[@]}"; do
		if [ "${i:0:1}" = "-" ] ; then
			local QUERY="DELETE FROM sshgroups WHERE id_sshkey = $1 AND KeyGroup LIKE \"${i:1}\";"
			sqlite3 $DB "$QUERY"
		else
			DBKeyId=$1
			if [ $(checkKeyInGroup "$i") = 0 ]; then
				local QUERY="INSERT INTO sshgroups( id_sshkey, KeyGroup ) VALUES ( \"$1\", \"$i\");"
				sqlite3 $DB "$QUERY"
			fi
		fi
		
	done
	
}

function addKeyToDB(){
	local QUERY="INSERT INTO sshkeys( SSHKey, KeyName, enabled ) VALUES( \"$SSHKey\", \"$SSHKeyName\", $KeyState); select last_insert_rowid() from sshkeys;"
	local DBKeyId=$(sqlite3 $DB "$QUERY" 2> /dev/null)
	echo $?
}

function getKeyID(){
	local QUERY="SELECT id FROM sshkeys WHERE SSHKey LIKE \"$SSHKey\";"
	local DBKeyId=$(sqlite3 $DB "$QUERY")
	echo $DBKeyId
}

# checks if an SSH key is already in a group
# returns 1 if it is in the group or 0 if not
function checkKeyInGroup(){
	local QUERY="SELECT id FROM sshgroups WHERE id_sshkey = $DBKeyId AND KeyGroup LIKE \"$1\" LIMIT 1;"

	local GroupId=$(sqlite3 $DB "$QUERY")
	if [ -z $GroupId ]; then
		echo 0 #key not yet in group
	else
		echo 1 #key already in group
	fi
}

# builds the group list for --overview
function buildKeyGroupsOverview(){

	# get groups for each key
	for i in "${@}"; do
		if [ $i = "" ]; then return; fi

		GroupList=""
	
		IFS='|' read -ra SSHKeyInfo <<< "$i"
		if [ "${SSHKeyInfo[2]}" = "" ]; then return; fi
		
		local KeyID=${SSHKeyInfo[0]} #store key id
		buildSQLGroupList "$KeyID"
		fingerprintKey "${SSHKeyInfo[1]} ${SSHKeyInfo[2]}"
		printf "$KeyID | " ; if [ ${SSHKeyInfo[3]} -eq 1 ]; then printf "+" ; else printf "-" ; fi ; printf " | $FingerPrint\n"
		FingerPrint=""
		
		# try to line up back slash
		if   [ $KeyID -gt 9999 ]; then printf "    ";
		elif [ $KeyID -gt 999  ]; then printf "   ";
		elif [ $KeyID -gt 99   ]; then printf "  ";
		elif [ $KeyID -gt 9    ]; then printf " ";
		fi
		
		if [ ! -z $GroupList ]; then
			printf "       \ Groups: $GroupList\n\n"
		else
			printf "       \ Groups: NO GROUPS\n\n"
		fi
	done
}

# generates a visual overview of which key belongs to which group
function showKeyGroupOverview(){

	# get list of all active keys in DB
	if [ -z $1 ]; then
		printf "# Enabled Keys #\n"
		local QUERY="SELECT id, SSHKey, KeyName, enabled from sshkeys WHERE enabled = 1";
	else
		local QUERY="SELECT id, SSHKey, KeyName, enabled from sshkeys WHERE id = $1";
	fi
	IFS=$'\n'
	local SQLAllKeys=($(sqlite3 -separator '|' $DB "$QUERY"))

	buildKeyGroupsOverview ${SQLAllKeys[@]}
	
	
	# get list of all inactive keys in DB
	if [ -z $1 ]; then
		local QUERY="SELECT id, SSHKey, KeyName, enabled from sshkeys WHERE enabled = 0";
	else
		return; # request was for a single key only
	fi
	IFS=$'\n'
	local SQLAllKeys=($(sqlite3 -separator '|' $DB "$QUERY"))

	printf "# Disabled Keys #\n"
	buildKeyGroupsOverview ${SQLAllKeys[@]}

}

# build comma separated list of groups the SSH key belongs to
# list is stored in global variable GroupList
function buildSQLGroupList(){
	local QUERY="SELECT KeyGroup FROM sshgroups WHERE id_sshkey = $1"
	
	IFS=$'\n'
	local SSHKeyGroups=($(sqlite3 $DB "$QUERY"))
	# assemble to string
	for (( x=0; x<"${#SSHKeyGroups[@]}"; x++)); do
		GroupList="$GroupList${SSHKeyGroups[x]}"
		
		local NEXT=$((x+1))
		if [ $((x+1)) -lt "${#SSHKeyGroups[@]}" ] && [ ! -z "${#SSHKeyGroups[@]}" ]; then
			GroupList="$GroupList,"
		fi
	done
}

# checks if the state (enabled/disabled) of the key is still valid
function updateSSHKeyState(){
	local QUERY="SELECT id,enabled FROM sshkeys WHERE SSHKey LIKE \"$SSHKey\""
	IFS='|'
	local SSHKeyState=($(sqlite3 -separator '|' $DB "$QUERY"))
	
	if [ ${SSHKeyState[1]} -ne $KeyState ]; then
		local QUERY="UPDATE sshkeys SET enabled = $KeyState WHERE id = ${SSHKeyState[0]}"
		sqlite3 $DB "$QUERY"
	fi
}


# deletes the key and any group association from the database
function deleteSSHKeys(){
	local QUERY="SELECT id FROM sshkeys WHERE SSHKey LIKE \"$SSHKey\""
	local SSHKeyToDeleteID=($(sqlite3 $DB "$QUERY"))
	
	if [ ! -z $SSHKeyToDeleteID ]; then
		local QUERY="DELETE FROM sshgroups WHERE id_sshkey = $SSHKeyToDeleteID"
		sqlite3 $DB "$QUERY"
		if [ $? -ne 0 ]; then
			printf "ERROR: unable to delete key group membership!\n"
			exit 99
		fi
		
		local QUERY="DELETE FROM sshkeys WHERE id = $SSHKeyToDeleteID"
		sqlite3 $DB "$QUERY"
		if [ $? -ne 0 ]; then
			printf "ERROR: unable to delete key from database!\n"
			exit 99
		else
			fingerprintKey "$SSHKey"
			printf "key removed | $FingerPrint\n"
			FingerPrint=""
		fi
	fi
}


##################
# load arguments #
##################
# parse script options
if [ -z $1 ]; then showHelp ; exit 1; fi
TEMPOPTS=$(getopt -o f:g:q::d: --long kid:,delete,overview,disabled,enabled,md5,sha256,new-db,force,help -n 'test.sh' -- "$@")
if [ $? -ne 0 ]; then showHelp ; exit 1 ; fi

eval set -- "$TEMPOPTS"
while true ; do
	case "$1" in
		-d)
			# custom db file
			case "$2" in
				*) DB=$2 ; shift 2 ;;
			esac;;
		-f)
			# key file to add
			case "$2" in
				*) loadKeyFromFile "$2" ; shift 2 ;;
			esac ;;
		-g)
			# groups for key
			case "$2" in
				*) SSHGroupOption="$2" ; shift 2 ;;
			esac ;;
		--kid)
			# key id passed
			case "$2" in
				*) SelectedKeyID="$2" ; shift 2 ;;
			esac ;;
		--overview)
			ShowSSHKeyOverview=1 ; shift ;;
		--enabled)
			KeyState=1 ; KeyStateChange=1 ; shift;;
		--disabled)
			KeyState=0 ; KeyStateChange=1 ; shift ;;
		--delete)
			KeyDelete=1 ; shift ;;
		--new-db)
			CreateNewDB=1 ; shift ;;
		--md5)
			if [ $SSHVersion = 6 ]; then printf "WARN: --md5 requires OpenSSL version 7 or greater\n"; else HasingAlgo="md5"; fi ; shift ;;
		--sha256)
			if [ $SSHVersion = 6 ]; then printf "WARN: --sha256 requires OpenSSL version 7 or greater\n"; else HasingAlgo="sha256"; fi ; shift ;;
		--help)
			showHelp ; exit 0 ;;
		--) shift ; break ;;
		*) printf "ERROR: unable to process options $1 -- $2\n" ; exit 1 ;;
	esac
done

# create fresh database
if [ $CreateNewDB -eq 1 ]; then createNewDB; fi

# generate key and group overview
if [ $ShowSSHKeyOverview -eq 1 ]; then
	showKeyGroupOverview
	exit 0
fi

# hack for now since this was an after thought. everything in here works using the actual SSHKey string
# will now load the SSHKey from db to allow key modification with the key DB id, as shown by --overview
if [ ! -z $SelectedKeyID ]; then
	loadKeyFromDB $SelectedKeyID
fi


if [ $KeyDelete -eq 1 ]; then
	deleteSSHKeys
	exit 0
fi


#######################
# add key to database #
#######################
DBKeyId=$(getKeyID)
if [ -z $DBKeyId ]; then

	ProcessReturn=$(addKeyToDB)

	if [ $ProcessReturn -eq 0 ]; then
		if [ ! -z $SSHGroupOption ]; then
			# don't add if no group name was passed
			DBKeyId=$(getKeyID)
			addKeyToGroup $DBKeyId
			buildSQLGroupList "$DBKeyId"
		fi
		showKeyGroupOverview $DBKeyId
	else
		printf "ERROR: unable to insert key - SQlite3 returned $ProcessReturn\n"
		exit 4
	fi
	
else

	# key already in DB, check if enable/disable has changed
	if [ $KeyStateChange = 1 ]; then
		updateSSHKeyState
	fi

	if [ ! -z $SSHGroupOption ]; then
		addKeyToGroup $DBKeyId
		buildSQLGroupList "$DBKeyId"
		showKeyGroupOverview $DBKeyId
	else
		showKeyGroupOverview $DBKeyId
	fi


fi



exit 0