#!/bin/bash
#
# This script sends the files to remote systems (CIPS / SYNERGIE)
# 
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                                                                             #
#   AUTHOR: REMI MONTROTY                                   Dec, 14  2011     #
#                                                                             #
#   VERSION :								      #
#	* v2.1 : 20120223						      # 
#		- synready for HRM					      #
#		- cleanup synready files after but leave link		      #
#		- use DWDDATE instead of range for cleaning		      #
#	* v2.0 : 20120221						      # 
#		- Completely rewritten with functions			      #
#		- ALL for both CIPS & SYNERGIE as targets		      #
#		- Add set_default_filename()				      #
#	* v1.7 : 20120220						      # 
#		- Switch to MODEL2SYN.sh 				      #
#		- Debug GB of -datapolicy.grb				      #
#		- clean-up -synready.grb				      #
#		- use $NCFTPPUT						      #
#	* v1.6 : 20120217						      # 
#		- Clarifiy SEND_ALL usage				      #
#		- Clean up claude's trace				      #
#	* v1.5 : 20120215						      # 
#		- Add calls to WRF2Synergie.sh prior to sending		      #
#		- Cleanup
#	* v1.4 : 20120116						      # 
#		- Change cleaning of .GB to nada			      #
#		- added "ALL" target
#	* v1.3 : 20120105						      # 
#		- Change cleaning of .GB to only current GBLIST to prevent    #
#		  UNIPOST from erasing another unipost file		      #
#	* v1.2 : 20111221						      # 
#		- add SEND_ALL option					      #
#		- switch to .GB extension files for Synergie		      #
#	* v1.1								      # 
#		- ncftpput error codes summed up (instead of exiting on       #
#		  first failure to xfer files				      #
#	* v1.0								      # 
#		- Take MODEL / GRID arguments to send files		      #
#		- for COSMO/HRM : DEFAULT_FILENAME must be in ENV	      #
#		as given from user_model_post				      #
#									      #
#   Possible Evolutions :					  	      #
#                                                                             #
#                                                                             #
#   Example:                                                                  #
#                                                                             #
#  send_models.sh WRF KNEW0070 CIPS 20111219000000                    	      #
#  send_models.sh HRM KNEW0140 SYNERGIE 20111219000000                 	      #
#  send_models.sh HRM KNEW0140 SYNERGIE 20111221000000 SEND_ALL      	      #
#       (will send all files to SYNERGIE)			      	      #
#  send_models.sh HRM KNEW0140 ALL 20111221000000			      # 
#       (will send all files to both CIPS & SYNERGIE)		      	      #
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

MODEL2SYN=/share/common/bin/MODEL2SYN.sh
NCFTPPUT=/share/common/bin/ncftpput
SENDMODELS_LOG=/home/sms/journal/cips_send/cips_send.log
PRODUCTIONCONFIG=/share/apps/DWDSCHED/ProductionConfigFiles/ProductionConfig

MODEL=$1
GRID=$2
RANGE_LIST_TYPE=$3
TARGET=$RANGE_LIST_TYPE
DATE=$4
SEND_ALL=$5

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#  Functions

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
usage() {
  echo "Call : $0 MODEL GRID CIPS|SYNERGIE DATE"
  echo "To send all files at once:  $0 WRF KNEW0070 CIPS 20120101000000 SEND_ALL"
  exit 1
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
FR3digits() {
 awk '{printf("%.3d\n",$1)}'
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
FR2DWD() {
range=$1
DAY=`echo $range | awk '{printf("%.2d\n", int($1/24) ) }'`
HOUR=`echo $range | awk '{printf("%.2d\n", int($1%24) ) }'`
echo ${DAY}${HOUR}0000
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
DWD2FR4digits() {
file=$1
DAYHOURS=`echo $file |cut -c5-6|awk '{print $1*24}'`
RESTHOURS=`echo $file |cut -c7-8`
let FR=DAYHOURS+RESTHOURS
range1=`echo $FR | awk '{ printf("%.4d\n",$1) }'`
echo $range1
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
anysendall() {
 if [ "${SEND_ALL}" == "SENDALL" ]; then
	SEND_ALL="SEND_ALL"
	echo "Setting SEND_ALL properly. Do not use SENDALL; use SEND_ALL"
 fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
define_frlist() {

	case $TARGET in 
		FULL) 
			FRLIST=`seq 0 $OUTPUT_INTERVAL $MAX_FORECAST_RANGE | FR3digits ` ;;
		CIPS) 
			## For FTP
			HOSTLIST="192.168.1.101 192.168.1.102" ;
			USER=cips_in
			PASS=cips_in
			FTPDIR="moddb/"

			## For files
			FRLIST=`seq 0 $OUTPUT_INTERVAL 36 | FR3digits ` ; 
			FRLIST="$FRLIST `seq 39 3 $MAX_FORECAST_RANGE | FR3digits `" ;;
		SYNERGIE) 
			## For FTP
			HOSTLIST="192.168.1.15 192.168.1.16" ;
			#HOSTLIST="192.168.1.16" ;
			USER=retim2000
			PASS=retim2000
			FTPDIR="./"

			## For files
			FRLIST=`seq 0 $OUTPUT_INTERVAL 36 | FR3digits ` ; 
			FRLIST="$FRLIST `seq 39 3 96 | FR3digits `" ;
			FRLIST="$FRLIST `seq 102 6 120 | FR3digits `" ;;
		ALL)
			/share/common/bin/send_models.sh $MODEL $GRID CIPS $DATE SEND_ALL  ;
			/share/common/bin/send_models.sh $MODEL $GRID SYNERGIE $DATE SEND_ALL  ;;
		*) 
			echo "Type of Forecast range list unknown.. ##$RANGE_LIST_TYPE##.. Aborting" ;
			exit 1 ;;
	esac 
} #~~ define_frlist()

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
sourcing_productionconfig() {

	if [ -z "$TASK_RUN" ]; then
		export	TASK_RUN=/tmp
	fi
 		
	echo "Sourcing $PRODUCTIONCONFIG"
	. $PRODUCTIONCONFIG
	if [ -z "$DEFAULT_FILENAME" ] ; then
		echo "DEFAULT_FILENAME not set.. aborting"
		exit 1
	fi
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
set_echeance() {
	if [ -z "$DMT_ECHEANCE" ]; then
		echo "Specify DMT_ECHEANCE (format: HHHHMM)"
		read DMT_ECHEANCE
		export DMT_ECHEANCE
	fi
	range=`echo $DMT_ECHEANCE | cut -c1-4`
	echo "Setting range=$range"
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
set_default_filename() {

  DWDDATE=`FR2DWD $range` 
  echo "Setting DWDDATE=$DWDDATE"

  case $MODEL in 
	COSMO) 
 		case $range in 
			0000) 	DEFAULT_FILENAME=lfff${DWDDATE} ;;
			*) 	DEFAULT_FILENAME=lfff${DWDDATE} ;;
		esac ;;
	HRM) 
 		case $range in 
			0000) 	DEFAULT_FILENAME=hiff${DWDDATE} ;;
			*) 	DEFAULT_FILENAME=hfff${DWDDATE} ;;
		esac ;;
	*)	echo "No DEFAULT_FILENaME for model ##$MODEL##" ;;

  esac
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
define_model_variables() {
case $MODEL in 
	## Note that for HRM & COSMO, $DEFAULT_FILENAME is set in .ProductionConfig file & holds
	## the lfff or h[if]ff value for the prefix
	COSMO) 
		if [ -z "$DEFAULT_FILENAME" ] && [ "$SEND_ALL" != "SEND_ALL" ]; then

			#~~
			set_echeance

			#~~
			set_default_filename
		fi
		if [ "$SEND_ALL" == "SEND_ALL" ]; then
			echo "Processing all adapted ranges";
		else

			range=`DWD2FR4digits $DEFAULT_FILENAME | FR3digits` ;

			echo "Processing range $range";
		fi
		prefix_COSMO=$DEFAULT_FILENAME ;
		prefix_COSMO_ALL="lfff"
		suffix_COSMO_CIPS=".grb" 	
		suffix_COSMO_SYNERGIE="-synready.grb" ;;	
	HRM) 
		if [ -z "$DEFAULT_FILENAME" ] && [ "$SEND_ALL" != "SEND_ALL" ]; then

			#~~
			set_echeance

			#~~
			set_default_filename
		fi
		if [ "$SEND_ALL" == "SEND_ALL" ]; then
			echo "Processing all adapted ranges";
		else

			range=`DWD2FR4digits $DEFAULT_FILENAME | FR3digits` ;

			echo "Processing range $range";
		fi
		prefix_HRM=$DEFAULT_FILENAME
		prefix_HRMALL="h?ff"
		suffix_HRM_CIPS="-synergie_supported.grb" 
		suffix_HRM_SYNERGIE="-synready.grb" ;;	
	WRF)
		range=`echo $DMT_ECHEANCE | cut -c1-4 | FR3digits`   ;

		if [ "$SEND_ALL" == "SEND_ALL" ]; then
			echo "Processing all adapted ranges";
		else
			echo "Processing range $range";
		fi
		prefix_WRF="wrfprs_d02." ;	
		prefix_WRFALL="wrfprs_d02.";
		suffix_WRF_CIPS="-datapolicy.grb" 
		suffix_WRF_SYNERGIE="-synready.grb";;
	*) 
		echo "Unknown MODEL=##$MODEL##. Aborting" 
		exit 1 ;;
esac
}  #~~ define_model_variables


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
set_prefix_and_suffix() {

	echo "case MODEL_TARGET= ${MODEL}_${TARGET}"
	#sleep 5

	case ${MODEL}_${TARGET} in 
		COSMO_CIPS) 
			prefixALL=$prefix_COSMOALL
			prefix=$prefix_COSMO
			suffix=$suffix_COSMO_CIPS ;;
		COSMO_SYNERGIE) 
			prefixALL=$prefix_COSMOALL
			prefix=$prefix_COSMO
			suffix=$suffix_COSMO_SYNERGIE ;;
		HRM_CIPS) 
			prefixALL=$prefix_HRMALL
			prefix=$prefix_HRM
			suffix=$suffix_HRM_CIPS ;;
		HRM_SYNERGIE) 
			prefixALL=$prefix_HRMALL
			prefix=$prefix_HRM
			suffix=$suffix_HRM_SYNERGIE ;;
		WRF_CIPS) 
			prefixALL=$prefix_WRFALL
			prefix=$prefix_WRF
			suffix=$suffix_WRF_CIPS ;;
		WRF_SYNERGIE) 
			prefixALL=$prefix_WRFALL
			prefix=$prefix_WRF
			suffix=$suffix_WRF_SYNERGIE ;;
		*) 
			echo "Couple ${MODEL}_$TARGET unknown... please double check"
			exit 1;;
	esac
	echo "prefix=$prefix"
	echo "suffix=$suffix"
	echo ""
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
loginfo() {
 echo "$*" >> $SENDMODELS_LOG
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
convert2syn() {

  echo "Converting to Synergie-ready format"

  ## Find out Postprocessed suffix for this model 
  #  (to be used as input for conversion)
  case $MODEL in 
  	COSMO) 	suffix_POSTPROC="$suffix_COSMO_CIPS" ;;
  	HRM) 	suffix_POSTPROC="$suffix_HRM_CIPS" ;;
  	WRF) 	suffix_POSTPROC="$suffix_WRF_CIPS" ;;
  	*)	echo "Cannot figure expected suffix (suffix_POSTPROC) for this model $MODEL."; 
		exit 1;;
  esac
  
  FILES2CONVERT=`ls $FILESDIR/${prefix}*${suffix_POSTPROC}`
  
  ## Process files for Synergie
  for f in $FILES2CONVERT ; do
  	nf=${f%%-*}${suffix}
  	echo "Calling $MODEL2SYN $f $nf"
  
  	#@@@
  	$MODEL2SYN $f $nf	
  done
  echo "Files $FILES2CONVERT processed for Synergie... "
  
} # convert2syn

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
get_all_files() {
	echo "Going to $FILESDIR"
	echo "through get_all_files()"
	cd $FILESDIR
	FILES2XFER=""
	for range in $FRLIST ; do
		case $MODEL in 
			HRM | COSMO) 
				## DWD models encode the files with DDhhmm format where hh is 
				#  the hour of the numeral forecast day DD
				DATE=`FR2DWD $range`;
				FILES2XFER="$FILES2XFER `ls ${prefixALL}${DATE}*${suffix}`" ;;
				#FILES2XFER="$FILES2XFER `ls *${DATE}*.grb`" ;;
			WRF) 
				FILES2XFER="$FILES2XFER `ls ${prefixALL}${range}*${suffix}`";;
			*)
				echo "MODEL $MODEL UNKNOWN"; exit 1;;
		esac
	done
} #~~ get_all_files

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
get_one_fr() {
	set -x
	echo "Going to $FILESDIR"
	echo "through get_one_fr()"
	cd $FILESDIR
	## here prefix must include the range &/or date
	FILES2XFER=`ls ${prefix}*${suffix}`
} #~~ get_one_fr

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
getfilelist() {
  case $SEND_ALL in 
	SEND_ALL)
		get_all_files ;;
	*) 
		get_one_fr ;;	
  esac

  echo "FILES2XFER = $FILES2XFER"
  #echo "is it ok? Y/N"
  #read answer 
  #if [ "$answer" != "Y" ]; then
 #	echo "Some issue with FILES2XFER...? Aborting"
 #	exit 1
 # fi
} #~~ getfilelist

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
link_GB() {
  ## For Synergie, use another extension (.GB)	
  if [ "$TARGET" == "SYNERGIE" ]; then
  	GBFILES=""
  	for f in $FILES2XFER; do
  		nf=$f.GB
  		ln -sf $f $nf
  		GBFILES="$GBFILES $nf"
  	done
  else	
  	GBFILES=$FILES2XFER
  fi
}



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
send_files() {

	## Send to all ips defined in define_frlist() ...
	for ip in $HOSTLIST; do
		echo ""
		RETRIES=5
		TIME_OUT=20

		loginfo "SEND_MODELS : sending $GBFILES to $TARGET on ip $ip"
		loginfo "$NCFTPPUT -S .tmp -u $USER -p $PASS $ip $FTPDIR $GBFILES"
		$NCFTPPUT -S .tmp -u $USER -p $PASS $ip $FTPDIR $GBFILES | tee -a $SENDMODELS_LOG
		r=$?
		if  [ $r -ne 0 ]; then
			echo "$RETRIES retries later, connection still failed. Aborting"
		fi
	done

}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
send_or_not() {
	## Grep the current range from $FRLIST	
	isGrepped=`echo $FRLIST | grep $range`
	
	## Alternatively, if SEND_ALL is set, set the variable to non null string
	if [ "$SEND_ALL" == "SEND_ALL" ]; then
		## set isGrepped so that it is sent
		isGrepped="SEND_ALL"
	fi

	if [ ! -z "$isGrepped" ]; then

		#~~
		send_files 
	else
		echo "Current forecast range : $range"
		echo "Skipped since not part of RANGE_LIST_TYPE $RANGE_LIST_TYPE!"
		echo $FRLIST
	fi
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
cleanup() {

	## Find out suffix to be erased
	case $MODEL in 
		COSMO) 	
  			DWDDATE=`FR2DWD $range` 
			FRDATE=$DWDDATE ; suffix_ERASE="$suffix_COSMO_SYNERGIE" ;;
		HRM) 	
  			DWDDATE=`FR2DWD $range` 
			FRDATE=$DWDDATE ; suffix_ERASE="$suffix_HRM_SYNERGIE" ;;
		WRF) 	
			FRDATE=$range ; suffix_ERASE="$suffix_WRF_SYNERGIE" ;;
		*)	echo "Cannot figure expected suffix (suffix_ERASE) for this model $MODEL."; 
			exit 1;;
	esac
	
	if [ "$SEND_ALL" == "SEND_ALL" ]; then
		echo "rm -f *${suffix_ERASE}"
	else
		rm -f *${FRDATE}*${suffix_ERASE}
		echo "rm -f *${FRDATE}*${suffix_ERASE}"
	fi
}
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

######################################################################
#######################    MAIN     ##################################

if [ -z "$*" ]; then
	usage
else
	echo "COMMAND : $0 $*" 
	loginfo "COMMAND : $0 $*" 
fi
export NHOSTS=1
export NSLOTS=1

#~~
anysendall

## Module load
model=`echo $MODEL | tr "[A-Z]" "[a-z]"`
MODULE="nwp/$MODEL/$GRID/${model}_${GRID}"

#@@@
. /etc/profile.d/modules.sh

module load taskcenter/sms
module load $MODULE
echo "Loading module $MODULE"

FILESDIR=$HOLDSPACE/$MODEL/$GRID/$DATE/out

#~~ Define specific file ranges (FRLIST) to be sent, based on TARGET
define_frlist

#~~ Define MODEL variables
define_model_variables

#~~ Set prefix & suffix for the file listing
set_prefix_and_suffix 

set -x 

#~~ If TARGET=SYNERGIE, we need to convert files before sending them
#	using MODEL2SYN
case $TARGET in
	SYNERGIE) 
		convert2syn ;;
	*)
		echo "Not converting input files ";;
 esac 

#~~ get filelist to be sent
getfilelist

#~~ link GB for Synergie : in any TARGET, the file list is now $GBFILES
link_GB

#~~ Decide whether to send current $range or not (send_files() called within)
send_or_not

#~~ Cleanup
cleanup

exit $r
