#!/bin/bash

THIS=`readlink -f "${BASH_SOURCE[0]}" 2>/dev/null||echo $0`
DIR=`dirname "${THIS}"`

checkinstall () {
	if (( $(dpkg -l $1 | wc -l | cut -d " " -f1) == 0 )); then
		echo "You need to have $1 installed to use this script."
		read -p "Do you want to install it now? (y/n)" -n 1 -r
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			sudo apt install $1
		else
			echo "Stopping script. You cannot use netchecker without $1."
			exit
		fi
	fi
}

checkinstall_all () {
	checkinstall nmap
	checkinstall testssl.sh
	checkinstall ssh-audit
	checkinstall xsltproc
}


help () {
	cat $DIR/help
	exit 1
}

defaultvalues () {
	directory="output"
	verbose=false
	ports="-p-"
	flags=""
}

#Method to check that first argument starts with -
checkcommandformat () {
	if [[ $1 != -* ]]; then
		echo "Please check argument \"$1\", it is not a command option."
		help
	fi
	if [[ $2 == -* ]]; then
		echo "Please check argument \"$2\", it should not be a command option."
		help
	fi
}

#Interpreter for arguments an corresponding action
getcommand () {
	#include everything from createargs/code

if [[ $1 == -f || $1 == -F ]]; then file=$2; fi
if [[ $1 == -u || $1 == -U ]]; then hostname=$2; fi
if [[ $1 == -o || $1 == -O ]]; then output=$2; fi
if [[ $1 == -d || $1 == -D ]]; then directory=$2; fi

}


#Method to parse the commands with arguments
argparse () {
	if [ -z $# ]; then echo "something went wrong at argparse"; exit 1; fi
	checkcommandformat $1 $2
	getcommand $1 $2
}

addflag () {
	if [[ -z $flags ]]; then
		flags="$1";
	else
		flags="$flags $1"
	fi
}

#Method to parse the flags
flagparse () {
	if [ -z $# ]; then echo "something went wrong at flagparse"; exit 1; fi

if [[ $1 == -q || $1 == -Q ]]; then ports="-p1-9999"; fi
if [[ $1 == -qq ]]; then ports="--top-ports 100"; fi
if [[ $1 == -v ]]; then verbose=true; fi
if [[ $1 == --install ]]; then checkinstall_all && echo "You now have all dependencies." && exit; fi
if [[ $1 == -Pn ]]; then addflag "-Pn"; fi
if [[ $1 == -A ]]; then addflag "-A"; fi

}

looparg () {
	#Loop through all arguments.
	while (( "$#" >= 1 )); do
		if [[ "$#" == 1 ]]; then
			flagparse $1
			shift
		else
			if [[ $1 == -* && $2 == -* ]]; then
				if [[ $1 == -n ]]; then
					shift 1
					nmapoption=$@
					shift $#
				else
					flagparse $1
					shift 1
				fi
			else
				argparse $1 $2
				shift 2
			fi
		fi
	done
}

dirformat () {
	#Check that the directory is well formatted with a / at the end.	
	if [[ -n $directory ]]; then
		if [[ $directory == *// ]]; then
			directory=$(echo $directory | rev | cut -d "/" -f2- | rev)
		elif [[ $directory != */ ]]; then
			directory="$directory/"
		fi
		if [[ ! -s $directory ]]; then
			mkdir -p $directory
		fi
	else
		directory="./"
	fi
}

#Module to change path used for saving files
changepath () {
	path=$directory$1
	if [[ $path != */ ]]; then path+="/"; fi
	mkdir -p $path
}


#Then call nmap with given arguments
callnmap () {
	changepath nmap
	
	if [[ $verbose != true ]]; then
		echo "Reminder: that can take a long time. If you want to see nmap status, use verbose mode (flag -v)."
	fi
	
	# userchanged options for nmap
	if [ -z "$nmapoption" ]; then
		#default value
		nmapoption="$ports $flags"
	#else user changed, which is saved in nmapoption
	fi
	echo "Nmap calling with following parameters: $nmapoption -sV -oA $path$output"
	
	if [[ $verbose = true ]]; then
		nmap $nmapoption $1 -sV -oA "$path$output"
	else
		nmap $nmapoption $1 -sV -oA "$path$output" 1>/dev/null
	fi
}

parsenmap () {
	if [[ -n $file ]]; then
		if [[ -s $file ]]; then
			if [[ -z $output ]]; then output=$(echo $file | rev | cut -d "/" -f1 | rev); fi
			callnmap "-iL $file"
		else
			echo "File \"$file\" not found."
		fi
	elif [[ -n $hostname ]]; then
		if [[ -z $output ]]; then output=$hostname; fi
		callnmap $hostname
	else
		echo "No file or hostname was given."
		help
	fi
}



resetfile () {
	rm -f $1
	touch $1
}


#Parse the xml-file to get lists of interesting ports
parsexml () {
	if [[ -s "$path$output.xml" ]]; then
	#todo: remove extra curls on duplicates
		#generate lists for http, https and tls
		$DIR/nmap-parse-output/nmap-parse-output "$path$output.xml" tls-hostnames-ports > $directory$output.tls.hostnames.ports
		$DIR/nmap-parse-output/nmap-parse-output "$path$output.xml" http-hostname-ports > $directory$output.http.hostnames.ports
		$DIR/nmap-parse-output/nmap-parse-output "$path$output.xml" http-ports > $directory$output.http.ips.ports
		$DIR/nmap-parse-output/nmap-parse-output "$path$output.xml" ssh-ports > $directory$output.ssh.ips.ports
		
		comm -12 $directory$output.http.hostnames.ports $directory$output.tls.hostnames.ports > $directory$output.https.hostnames.ports
	fi
}

#Now check for xml output and use the parser to get testssl started
calltestssl () {
	if [[ -s "$directory$output.tls.hostnames.ports" ]]; then
		changepath testssl
		
		maxlines=$(wc -l "$directory$output.tls.hostnames.ports" | cut -d " " -f1)
		currentline=1
		
		for ele in $(cat "$directory$output.tls.hostnames.ports"); do
			echo "Using testssl on elment $currentline out of $maxlines elements."
			currentline=$(expr $currentline + 1)
			testssl -oL $path $ele 1>/dev/null
		done
	fi
}

callsshaudit () {
	if [[ -s "$directory$output.ssh.ips.ports" ]]; then
		changepath ssh
	
		maxlines=$(wc -l "$directory$output.ssh.ips.ports" | cut -d " " -f1)
		currentline=1
	
	        for ele in $(cat "$directory$output.ssh.ips.ports"); do
			echo "Using ssh-audit on elment $currentline out of $maxlines elements."
	                currentline=$(expr $currentline + 1)
	
			sship=$(echo $ele | cut -d ":" -f1)
			sshport=$(echo $ele | cut -d ":" -f2)
	                ssh-audit $ele 1> ${path}ssh.$sship.$sshport
		done
	fi
}


tidyup () {
	mkdir -p $directory$output'-hostnames'
	mkdir -p $directory$output'-ips'
	mv $directory$output*.hostnames.* $directory$output'-hostnames'
	mv $directory$output*.ips.* $directory$output'-ips'
}

main () {
	#todo in one function with shift
	checkinstall_all
	
	defaultvalues
	looparg $@
	dirformat

	parsenmap
	parsexml

	if [[ -s "$path$output.xml" ]]; then
		calltestssl
		callsshaudit
	fi

	tidyup
}
main $@

























