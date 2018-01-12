#!/bin/bash

# script to simplify management of the authorized_keys file
# using keys stored in an SQlite3 database.
#
# Run script with --help to get list of options
#	  ./ssh-key-deploy.sh --help
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
#
#
# See README.md for database format or use ssh-key-manage.sh to create a new one





DB="SSHkeys.db"
AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
AUTHORIZED_KEYS_FORCE=0
AUTHORIZED_KEYS_CUSTOM="" #stores custom file if passed
GroupOptions=""
KeysAddedCnt=0
KeysRemovedCnt=0
MsgVerbose=0 # 0=print everything, 1=only error and file changes, 2=only errors
HasingAlgo="sha256"
FingerPrint="" # will contain an SSH finger print
if [ $(ssh -V 2>&1 | cut -c9-9) -lt 7 ]; then SSHVersion=6; HasingAlgo=""; else SSHVersion=7; fi
sqlite3 --version > /dev/null 2>&1 || { printf "ERROR: SQlite3 is not installed or not in path!\n"; exit 1; }


function showHelp(){
	printf "\n"
	printf "Usage: ssh-key-deploy.sh [OPTIONS]\n"
	printf "OPTIONS include:\n"
	printf "  -d FILENAME\t use custom database file '/some/path/foo.db'\n"
	printf "  -f FILENAME\t use custom authorized_keys file '/some/path/authorized_keys'\n"
	printf "  -g GROUP\t comma separated list of groups 'foo,bar'\n"
	printf "  -q\t\t only show file changes and error messages\n"
	printf "  -qq\t\t only show error messages\n"
	printf "  --force\t delete authorized keys file before adding keys\n"
	printf "  --md5\t\t md5 finger prints\n"
	printf "  --sha256\t sha256 finger prints (default)\n"
	printf "  --help\t this help overview\n"
	printf "\n"
	printf "Writes all enabled keys to authorized_keys if no groups are supplied.\n"
	printf "\n"
	exit 0
}


# creates a fingerprint from the SSH key
function fingerprintKey(){
	if [ "$HasingAlgo" = "" ]; then
		echo "$1" > "/tmp/ssh-key-deploy.tmp"
		FingerPrint=$( ssh-keygen -l -f /dev/stdin <<< "$1" )
	else
		FingerPrint=$(ssh-keygen -E $HasingAlgo -l -f - <<< "$1" )
	fi
}

# build OR for SELECT
function buildGroups(){
	IFS=',' read -ra GroupsDB <<< "$1"
	for (( i=0; i<"${#GroupsDB[@]}"; i++)); do
	
		# exclude groups
		local WHERE="$WHERE sshgroups.KeyGroup LIKE \"${GroupsDB[i]}\""
		
		local NEXT=$((i+1))
		if [ $NEXT -lt "${#GroupsDB[@]}" ] && [ ! -z "${#GroupsDB[@]}" ]; then
			local WHERE="$WHERE OR"
		fi
	done
	
	echo "$WHERE"
}

# remove key from file passed via $1
function removeKeyFromFile(){
	local SEDOPTS=""
	local CONTENT="$1"
	local RET=$(grep -n "$CONTENT" "$AUTHORIZED_KEYS" 2> /dev/null)
	local ItemSrc=$(echo "$RET" |  awk -F":" '{print $1}')

	if [ $? -eq 0 ]; then

		# prepare lines numbers for sed operation
		for item in ${ItemSrc[@]}
		do
			SEDOPTS="$SEDOPTS${item}d;"
		done

		if [ -n "$SEDOPTS" ]; then
			local RETSED=$(sed ${SEDOPTS} < "$AUTHORIZED_KEYS" 2> /dev/null)
			if [ $? -ne 0 ]; then
				printf "ERROR: reading file to find keys for removal\n\n"
				exit 99
			else

				echo "$RETSED" > "$AUTHORIZED_KEYS"
				if [ $? -ne 0 ]; then
					fingerprintKey "$CONTENT"
					printf "ERROR: unable to remove key $FingerPrint\n\n"
					FingerPrint=""
					exit 99
				else
					if [ $MsgVerbose -ne 2 ]; then
						if [ "$CONTENT" = " " ] || [ "$CONTENT" = "" ]; then return; fi
						fingerprintKey "$CONTENT"
						printf "  - removed $FingerPrint\n"
						FingerPrint=""
					fi
					((KeysRemovedCnt++))
				fi
			fi
		fi


	fi
}

# retrieve list of SSH keys which do not belong to the groups passed with -g
function getSSHKeysToRemoveGroups(){

	local SQLGroupsQuery=$(buildGroups $1)
	local QUERY="SELECT DISTINCT sshkeys.SSHKey, sshkeys.KeyName FROM sshkeys WHERE sshkeys.enabled = 1 AND NOT EXISTS( SELECT * FROM sshgroups WHERE sshgroups.id_sshkey = sshkeys.id"
	local QUERY="$QUERY AND $SQLGroupsQuery)"

	IFS=$'\n'
	SQLAllKeys=($(sqlite3 -separator ' ' $DB "$QUERY"))
}

# retrieve list of disabled keys
function getSSHKeysToRemoveDisabled(){

	local QUERY="SELECT DISTINCT sshkeys.SSHKey, sshkeys.KeyName FROM sshkeys WHERE sshkeys.enabled = 0"

	IFS=$'\n'
	SQLAllKeys=($(sqlite3 -separator ' ' $DB "$QUERY"))
}

# remove any disabled keys - always run this check last
function removeKeysDisabled(){
	getSSHKeysToRemoveDisabled
	
	for i in "${SQLAllKeys[@]}"; do
		#echo "$i"
		removeKeyFromFile "$i"
	done
	
	if [ $KeysRemovedCnt -eq 0 ] && [ $MsgVerbose -eq 0 ]; then
		printf "INFO: no disabled keys need to be removed from authorized_keys.\n"
	fi
}

# checks database for any keys which are not in the group but may be in the file
# this happens if a key used to be in a group but has been removed
function removeKeysNotInGroup(){
	getSSHKeysToRemoveGroups "$1"
	
	for i in "${SQLAllKeys[@]}"; do
		#echo "$i"
		removeKeyFromFile "$i"
	done
	
	if [ $KeysRemovedCnt -eq 0 ] && [ $MsgVerbose -eq 0 ]; then
		printf "INFO: no keys need to be removed from authorized_keys.\n"
	fi
}

# retrieve the SSH keys to be added
function getSSHKeysToAdd(){

	local QUERY="SELECT DISTINCT sshkeys.SSHKey, sshkeys.KeyName FROM sshkeys,sshgroups WHERE sshkeys.id = sshgroups.id_sshkey AND sshkeys.enabled = 1"
	if [ ! -z "$1" ]; then
		# inject group query
		local SQLGroupsQuery=$(buildGroups $1)
		local QUERY="$QUERY AND ( $SQLGroupsQuery )"
	fi

	IFS=$'\n'
	SQLAllKeys=($(sqlite3 -separator ' ' $DB "$QUERY"))
}

# writes key to file if it does not exist yet
function addKeyToFile(){
	local CONTENT="$1"

	GREPRES=$(grep -c "$CONTENT" "$AUTHORIZED_KEYS")
	if [ $GREPRES -eq 0 ]; then
		#key not in authorized key file, add it
		printf "$CONTENT\n" 2> /dev/null >> "$AUTHORIZED_KEYS"
		
		if [ $? -ne 0 ]; then
			fingerprintKey "$CONTENT"
			printf "  * ERROR writing to file $FingerPrint\n\n"
			FingerPrint=""
			exit 99
		else
			fingerprintKey "$CONTENT"
			if [ $MsgVerbose -ne 2 ]; then
				printf "  + added $FingerPrint\n"
				FingerPrint=""
			fi
			((KeysAddedCnt++))
		fi
	fi
}

# build authorized_keys using all keys in DB
function buildAllKeys(){
	getSSHKeysToAdd
	
	for i in "${SQLAllKeys[@]}"; do
		#echo "$i"
		addKeyToFile "$i"
	done
	
	if [ $KeysAddedCnt -eq 0 ] && [ $MsgVerbose -eq 0 ]; then
		printf "INFO: no new keys for authorized_keys.\n"
	fi
}

function buildKeysGroup(){
	getSSHKeysToAdd $1
	
	for i in "${SQLAllKeys[@]}"; do
		#echo "$i"
		addKeyToFile "$i"
	done
	
	if [ $KeysAddedCnt -eq 0 ] && [ $MsgVerbose -eq 0 ]; then
		printf "INFO: no new keys for authorized_keys.\n"
	fi
}


# determins file paths after AUTHORIZED_KEYS has been set
function determinePaths(){
	# determine path as it may be passed to the script 
	AUTH_LEN=$(printf "$AUTHORIZED_KEYS" |  awk -F"/" '{ print $NF }' | wc -m)
	STR_LEN=$(printf "$AUTHORIZED_KEYS" | wc -m)
	let "STR_CUT=$STR_LEN - $AUTH_LEN"
	STR_PATH=$(printf "$AUTHORIZED_KEYS" | cut -c-$STR_CUT)
}


# creates path to authorized keys file if it does not exist
function validateAuthFilePath(){
	determinePaths
	
	if [ ! -d "$STR_PATH" ]; then
			mkdir "$STR_PATH"
		if [ $? -ne 0 ]; then
			printf "ERROR: unable to create $STR_PATH\n\n"
			exit 99
		fi
		chmod 0700 "$STR_PATH"
	fi
}


function deleteAuthFile(){
	if [ ! -f $AUTHORIZED_KEYS ]; then
		return 0
	fi
	
	RET=$(rm $AUTHORIZED_KEYS 2>&1)
	if [ $? -ne 0 ]; then
		printf "ERROR: clearing file: $RET\n\n"
		exit 1
	fi
}

function createAuthFile(){
	if [ -f $AUTHORIZED_KEYS ]; then
		# file already exists
		return 0
	fi

	RET=$(touch $AUTHORIZED_KEYS 2>&1)
	if [ $? -ne 0 ]; then
		printf "ERROR: creating empty file: $RET\n\n"
		exit 1
	fi
	
	chmod 0600 "$AUTHORIZED_KEYS"
	if [ $? -ne 0 ]; then
		printf "ERROR: unable to set file permissions\n\n"
		exit 1
	fi
}


# parse script options
TEMPOPTS=$(getopt -o f:g:q::d: --long md5,sha256,force,help -n 'ssh-key-deploy.sh' -- "$@")
if [ $? -ne 0 ]; then showHelp ; exit 1 ; fi

eval set -- "$TEMPOPTS"
while true ; do
	case "$1" in
		-f)
			# custom AUTHORIZED_KEYS file
			case "$2" in
				*) AUTHORIZED_KEYS_CUSTOM=$(readlink -f "$2") ; shift 2 ;;
			esac ;;
		-g)
			# limit to specific groups
			case "$2" in
				*) GroupOptions=$2 ; shift 2 ;;
			esac ;;
		-d)
			# custom db file
			case "$2" in
				*) DB=$2 ; shift 2 ;;
			esac ;;
		-q)
			# only print errors and file changes
			case "$2" in
				"") MsgVerbose=1 ; shift 2 ;;
				*) MsgVerbose=2 ; shift 2 ;;
			esac ;;
		--md5)
			if [ $SSHVersion = 6 ]; then printf "WARN: --md5 requires OpenSSL version 7 or greater\n"; else HasingAlgo="md5"; fi ; shift ;;
		--sha256)
			if [ $SSHVersion = 6 ]; then printf "WARN: --sha256 requires OpenSSL version 7 or greater\n"; else HasingAlgo="sha256"; fi ; shift ;;
		--force)
			# force use fresh AUTHORIZED_KEYS file
			AUTHORIZED_KEYS_FORCE=1 ; shift ;;
		--help)
			showHelp ; exit 0 ;;
		--) shift ; break ;;
		*) printf "ERROR: unable to process options\n" ; exit 1 ;;
	esac
done


# use custom authorized_keys file or default
if [ ! -z "$AUTHORIZED_KEYS_CUSTOM" ]; then
	AUTHORIZED_KEYS=$AUTHORIZED_KEYS_CUSTOM
	if [ $MsgVerbose -eq 0 ]; then 
		printf "INFO: using $AUTHORIZED_KEYS\n"
	fi
fi


# ensure path for authorized keys file exist
validateAuthFilePath


# handle --force parameter
if [ $AUTHORIZED_KEYS_FORCE = 1 ]; then
	deleteAuthFile
	createAuthFile
else
	#ensure authorized file exists
	createAuthFile
fi


# create backup
if [ $(du "$AUTHORIZED_KEYS" | cut -f1) -gt 0 ] && [ "$AUTHORIZED_KEYS_FORCE" = 0 ] && [ -f "$AUTHORIZED_KEYS" ]; then
		
	KEY_BACK=$AUTHORIZED_KEYS".deploy"
	cp "$AUTHORIZED_KEYS" "$KEY_BACK"
	if [ $? -ne 0 ]; then
		printf "ERROR: Unable to create backup of authorized keys file\n"
		exit 99
	fi
	if [ $MsgVerbose -eq 0 ]; then
		printf "INFO: backup created $KEY_BACK\n"
	fi
fi


# process parameters
if [ -z $GroupOptions ]; then
	if [ $MsgVerbose -eq 0 ]; then
		printf "INFO: adding all keys to $AUTHORIZED_KEYS\n"
	fi
	buildAllKeys
	removeKeysDisabled # should not be required since build only adds enabled keys but run anyways
	
else
	if [ $MsgVerbose -eq 0 ]; then
		printf "INFO: building $AUTHORIZED_KEYS using groups\n"
	fi
	buildKeysGroup "$GroupOptions"
	removeKeysNotInGroup "$GroupOptions"
	removeKeysDisabled
fi


exit 0