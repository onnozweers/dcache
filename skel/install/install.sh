#!/bin/bash

# Set up the preset values before we get to the command line
# Note these values can be changed with the command line

# Default Log level
# Standard logging levels are
# ABORT ERROR WARNING INFO DEBUG
loglevel=14


# Default Log File

logfile=""


# Default dCache Home dirrectory.

ourHomeDir=/opt/d-cache



usage()
{
  echo "dCache install script"
  echo ""
  echo "-h --help             Show this help"
  echo "-p PATH  --prefix   PATH    Set install prefix (by default '/opt/dcache')"
  echo "-l LEVEL --loglevel LEVEL   Set loglevel (by default '15')"
  echo "                        debug level ABORT=45"
  echo "                        debug level ERROR=35"
  echo "                        debug level WARNING=25"
  echo "                        debug level INFO=15"
  echo "                        debug level DEBUG=5"
  
}



yaim_config_file_get_value_old()
{
# Returns 0 on success
# Returns 2 if key not found
local FILE
local Key
local cursor
local CursorLine
local MatchLine
local AllCursors
local foundPotentialCursors
local lineNumBefore
local PreviousLine
local MatchLine
local RawCursorLine
FILE=$1
Key=$2
if [ ! -f ${FILE} ] ; then
    echo yaim_config_file_get_value called with no file, file=$FILE
    exit 1
fi
AllCursors=`grep -n "^[	 ]*${Key}[	 ]*=" $FILE | cut -d: -f1 `
if [ "${AllCursors}X" == "X" ] ; then
  RET=""
  return 2
fi
# Now iterate through all our matches 
# check the line before is not terminated with \
foundPotentialCursors=""
for acursor in $AllCursors
do
  let lineNumBefore="${acursor}-1"
  if [ "${lineNumBefore}" == "0" ] ; then
    foundPotentialCursors="${acursor} ${foundPotentialCursors}"
  else
    # Following bash convention ignore all content after "#"
    # including lines terminating in "\"
    PreviousLine=`sed "${lineNumBefore}q;d" $FILE | sed 's/#.*$//'`
    MatchLine="${PreviousLine%%"\\"}"
    if [ "${PreviousLine}" == "${MatchLine}" ] ; then
      foundPotentialCursors="${acursor} ${foundPotentialCursors}"
    fi
  fi
done
if [ "${foundPotentialCursors}X" == "X" ] ; then
  RET=""
  return 2
fi
# Since we reversed the order of the cursors while validating them
# We can process only first valid cursor
cursor=`echo ${foundPotentialCursors} | sed 's/ .*//'`

RawCursorLine=`sed "${cursor}q;d" $FILE | cut -s -d= -f2- `
CursorLine=`echo "${RawCursorLine}" | sed 's/#.*//'`
if [ "${RawCursorLine}" == "${CursorLine}" ] ; then
  # No comments on this line so check for terminating '\'
  MatchLine="${CursorLine%%"\\"}\\"
  RET="${CursorLine%%"\\"}"
  while [ "${CursorLine}" == "${MatchLine}" ] 
  do
    # While last line character is "\"
    let cursor+=1
    RawCursorLine=`sed "${cursor}q;d" $FILE`
    CursorLine=`echo "${RawCursorLine}" | sed 's/#.*//'`
    if [ "${RawCursorLine}" != "${CursorLine}" ] ; then
      # No comments on this line
      RET="${RET} ${CursorLine}"
      break
    fi
    MatchLine="${CursorLine%%"\\"}\\"
    RET="$RET ${CursorLine%%"\\"}"
  done
else
  # Comments on this line so no need to process "\"
  RET=${CursorLine}
fi
# Now after all the processing remove starting and termianting white space
RET=`echo $RET | sed 's/^[ 	]*\"\([^"]*\)\"[ 	]*$/\1/'`
}



yaim_config_file_get_value()
{
  logmessage DEBUG "function yaim_config_file_get_value start"
  # Returns 0 on success
  # Returns 1 if file not found
  # Returns 2 if key not found
  local FILE
  local Key
  local RC
  local FoundLine
  FILE=$1
  Key=$2
  RET=""
  RC=0
  if [ -z "${FILE}" ] ; then
    logmessage ERROR "yaim_config_file_get_value_old called with no file parameter"
    exit 1
  fi
  if [ -f ${FILE} ] ; then
    COMMAND="unset \"${Key}\" ; . ${FILE} ;  if [ -z \"\$${Key}\" ] ; then echo notFound; else echo Found; fi ; echo \"\$${Key}\""
    CmdOut=`echo ${COMMAND} | sh`
    FoundLine=`echo "${CmdOut}" | sed "1q;d"`
    if [ "${FoundLine}" == "Found" ] ; then
      RET=`echo "${CmdOut}" | sed '1d'`
      RC=0
    else
      RC=2  
    fi
  else
    logmessage ERROR "yaim_config_file_get_value called with no valid file, file=$FILE"
    exit 1
  fi
  logmessage DEBUG "function yaim_config_file_get_value stop"
  return ${RC}
}



logmessage()
{ 
  local ThisLogLevel
  local ThisPrefix
  let ThisLogLevel=$1
  if [ "$1" == "NONE" ] ; then
    ThisLogLevel=55
  fi
  if [ "$1" == "ABORT" ] ; then
    ThisLogLevel=45
  fi
  if [ "$1" == "ERROR" ] ; then
    ThisLogLevel=35
  fi
  if [ "$1" == "WARNING" ] ; then
    ThisLogLevel=25
  fi
  if [ "$1" == "INFO" ] ; then
    ThisLogLevel=15
  fi
  if [ "$1" == "DEBUG" ] ; then
    ThisLogLevel=5
  fi
  if [ $ThisLogLevel -lt 60 ] ; then
    ThisPrefix="NONE:"
  fi
  if [ $ThisLogLevel -lt 50 ] ; then
    ThisPrefix="ABORT:"
  fi
  if [ $ThisLogLevel -lt 40 ] ; then
    ThisPrefix="ERROR:"
  fi
  if [ $ThisLogLevel -lt 30 ] ; then
    ThisPrefix="WARNING:"
  fi
  if [ $ThisLogLevel -lt 20 ] ; then
    ThisPrefix="INFO:"
  fi
  if [ $ThisLogLevel -lt 10 ] ; then
    ThisPrefix="DEBUG:"
  fi
  if [ $# -ge 1 ]
  then
    shift 1
    if [ ${ThisLogLevel} -gt ${loglevel} ]
    then
      if [ $# -eq 1 ]; then
        echo ${ThisPrefix}$*
        if [ "${logfile}" != "" ]
        then
          echo ${ThisPrefix}$* >> ${logfile}
        fi
      fi
      if [ $# -eq 0 ]; then
        while read logline
	do
	  echo ${ThisPrefix}${logline}
	  if [ "${logfile}" != "" ]
          then
            echo ${ThisPrefix}${logline} >> ${logfile}
          fi
	done
      fi
    fi
  fi
}


check_shell()
{
  if [ "$BASH_VERSION" = "" ] ; then
    logmessage ERROR "bash was not detected script exiting."  
    exit 1
  fi
}

check_os()
{  
  local osname
  RET="Unknown"
  osname=`uname`
  if [ "$osname" = "Linux" ] ; then
    RET=Linux
  fi
  if [ "$osname" = "SunOS" ] ; then
    RET=SunOS
  fi
}

os_absolutePathOf() 
{
    if [ "$1" == "" ]
    then
      logmessage ERROR "coding error os_absolutePathOf called with no parameter"  
      exit 1
    fi
    case `uname` in
        Linux)
            readlink -f $1
            ;;
        *)
            path=`absfpath $1`
            while true
            do
                /bin/test -L "${path}"
                if [ $? -ne 0 ]
                then
                   break;
                fi

                newpath=`ls -ld  ${path} | awk '{ print $11 }'`
                echo ${newpath} | egrep "^/"  > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    # absolute path
                    fullpath=${newpath}
                else
                    linkpath=`dirname ${path}`/${newpath}
                    fullpath=`absfpath ${linkpath}`
                fi
                path=${fullpath}
            done
            echo ${fullpath}
            ;;
    esac
}



check_install()
{
  local dCacheHomeDir
  dcacheInstallGetHome
  dCacheHomeDir=$RET
  if [ ! -r ${dCacheHomeDir}/etc/node_config ]; then
    logmessage ABORT "${dCacheHomeDir}/etc/node_config missing."
    logmessage INFO "Copy ${dCacheHomeDir}/etc/node_config.template to ${dCacheHomeDir}/etc/node_config and customize it before running the install script. Exiting."
    exit 4
  fi
}





shortname_os() {
    case `uname` in
        Linux)
            echo `hostname -s`
            ;;
        SunOS)
            echo `uname -n`
            ;;
    esac
}

domainname_os() {
    case `uname` in
        Linux)
            echo `hostname -d`
            ;;
        SunOS)
            echo `/usr/lib/mail//sh/check-hostname |cut -d" " -f7 | awk -F. '{ for( i=2; i <= NF; i++){ printf("%s",$i); if( i  <NF) printf("."); } } '`
            ;;
    esac
}


printConfig() {
    key=$1
    cat ${ourHomeDir}/etc/node_config \
        ${ourHomeDir}/etc/door_config 2>/dev/null |
    perl -e "
      while (<STDIN>) { 
         s/\#.*$// ;                        # Remove comments
         s/\s*$// ;                         # Remove trailing space
         if ( s/^\s*${key}\s*=*\s*//i ) {   # Remove key and equals
            print;                          # Print if key found
            last;                           # Only use first appearance
         }
      }
    "
}


fqdn_os() {
    case `uname` in
        Linux)
            echo `hostname --fqdn`
            ;;
        SunOS)
            echo `/usr/lib/mail/sh/check-hostname |cut -d" " -f7`
            ;;
    esac
}


dcacheInstallGetPnfsRoot()
{
  # To make shure to use the right dCache dir
  yaim_config_file_get_value ${ourHomeDir}/etc/node_config PNFS_ROOT 
}



dcacheInstallGetServerId()
{
  local SERVER_ID
  yaim_config_file_get_value ${ourHomeDir}/etc/node_config SERVER_ID
  SERVER_ID=${RET}
  if [ -z "${SERVER_ID}" ] ; then
    SERVER_ID=`domainname_os`
    if [ $? -ne 0 -o -z "${SERVER_ID}" ] ; then
        SERVER_ID="`cat /etc/resolv.conf | sed -e 's/#.*$//' | grep 'search' | awk '{ print($2) }'`"
        if [ -z "${SERVER_ID}" ]; then
            SERVER_ID="`cat /etc/resolv.conf | sed -e 's/#.*$//' | grep 'domain' | awk '{ print($2) }'`"
        fi
    fi
    echo ""
    echo "[INFO]  No 'SERVER_ID' set in 'node_config'. Using SERVER_ID=${SERVER_ID}."
  fi
  RET=${SERVER_ID}
}



dcacheInstallGetPnfsMountPoint()
{
  local serverId
  local PnfsRoot
  dcacheInstallGetPnfsRoot
  PnfsRoot=$RET
  dcacheInstallGetServerId
  serverId=$RET
  RET=${PnfsRoot}/${serverId}
}



dcacheInstallGetExportPoint()
{
  local exportPoint
  local pnfsMountPoint
  
  dcacheInstallGetPnfsMountPoint
  pnfsMountPoint=$RET
  
  exportPoint=`mount | grep ${pnfsMountPoint} | awk '{print $1}' | awk -F':' '{print $2}'`
  RET=${exportPoint}
}


absfpath () {
  CURDIR=`pwd`
  cd `dirname $1`
  ABSPATH=`pwd`/`basename $1`
  cd "$CURDIR"
  echo ${ABSPATH}
}

dcacheInstallGetNameSpaceType()
{
  local nameServerFormat
  yaim_config_file_get_value ${ourHomeDir}/etc/node_config NAMESPACE
  nameServerFormat="${RET}"
  if [ "${nameServerFormat}" != "pnfs" -a "${nameServerFormat}" != "chimera" ]
  then
    logmessage WARNING "node_config does not have NAMESPACE set to chimera or pnfs."
    logmessage INFO "NAMESPACE=${nameServerFormat}"
    nameServerFormat="pnfs"
    logmessage WARNING "Defaulting node_config to pnfs. This behaviour will change in future dCache releases."
  fi
  RET=$nameServerFormat
}


dcacheInstallGetNameSpaceServer()
{
  local namespaceServer
  
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NAMESPACE_NODE
  namespaceServer="${RET}"
  if [ -z "${namespaceServer}" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" ADMIN_NODE
    namespaceServer="${RET}"
    if [ -z "${namespaceServer}" ] ; then
      namespaceServer='invalid.host.example.org'
      logmessage WARNING "No 'NAMESPACE_NODE' or 'ADMIN_NODE' set in 'node_config' using '${namespaceServer}'"
    else
      logmessage WARNING "No 'NAMESPACE_NODE' set in 'node_config' using depricated 'ADMIN_NODE' value '${namespaceServer}'"
    fi
  fi
  RET=${namespaceServer}
}

dcacheNameServerIs()
{
  dcacheInstallGetNameSpaceServer
  pnfsHost="${RET}"
  if [ "${pnfsHost}" == "localhost" ]
  then
    return 1
  fi
  if [ "${pnfsHost}" == `fqdn_os` ]
  then
    return 1
  fi
  return 0
}



dcacheInstallGetHome()
{
  local DCACHE_HOME_Tmp
  RET=""
  # To make shure to use the right dCache dir
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" DCACHE_HOME
  DCACHE_HOME_Tmp="${RET}"
  if [ "x${DCACHE_HOME_Tmp}" == "x" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" DCACHE_BASE_DIR
    DCACHE_HOME_Tmp="${RET}"
    echo "WARNING: the variable DCACHE_HOME is not set."
    if [ "x${DCACHE_HOME_Tmp}" != "x" ] ; then
      echo "WARNING: Using deprecated value of DCACHE_BASE_DIR as DCACHE_HOME"
      RET=${DCACHE_HOME_Tmp}
    else
      echo "ERROR: Failed getting the value of DCACHE_HOME"
    fi
  else
    RET=${DCACHE_HOME_Tmp}
  fi
}

dcacheInstallGetUseGridFtp()
{
  # returns 1 if gridFTP is used 0 otherwise
  local UseGridFtp
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" DCACHE_HOME
  UseGridFtp=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${UseGridFtp}" == "yes" ] ; then
    return 1
  fi
  if [ "${UseGridFtp}" == "y" ] ; then
    return 1
  fi
  return 0
}

dcacheInstallGetUseSrm()
{
  # returns 1 if gridFTP is used 0 otherwise
  local UseSRM
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" SRM
  UseSRM=`echo "${RET}" | tr '[A-Z]' '[a-z]'` 
  if [ "${UseSRM}" == "yes" ] ; then
    return 1
  fi
  if [ "${UseSRM}" == "y" ] ; then
    return 1
  fi
  return 0
}

dcacheInstallGetIsAdminDoor()
{
  # returns 1 if is an adminDoor is used 0 otherwise
  local NodeType
  local adminDoor
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'` 
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" adminDoor
    adminDoor=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
    if [ "${adminDoor}" == "yes" ] ; then
      return 1
    fi
    if [ "${adminDoor}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}


dcacheInstallGetIsHttpDomain()
{
  # returns 1 if is an httpDomain is used 0 otherwise
  local NodeType
  local httpDomain
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" httpDomain
    httpDomain=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
    if [ "${httpDomain}" == "yes" ] ; then
      return 1
    fi
    if [ "${httpDomain}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}


dcacheInstallGetIsLmDomain()
{
  # returns 1 if is an lmDomain is used 0 otherwise
  local NodeType
  local lmDomain
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi  
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" lmDomain
    lmDomain=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
    if [ "${lmDomain}" == "yes" ] ; then
      return 1
    fi
    if [ "${lmDomain}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}

dcacheInstallGetIsPoolManager()
{
  # returns 1 if is an poolManager is used 0 otherwise
  local NodeType
  local poolManager
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" poolManager
    poolManager=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
    if [ "${poolManager}" == "yes" ] ; then
      return 1
    fi
    if [ "${poolManager}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}

dcacheInstallGetIsUtilityDomain()
{
  # returns 1 if is an utilityDomain is used 0 otherwise
  local NodeType
  local utilityDomain
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`  
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" utilityDomain
    utilityDomain=`echo "${RET}" | tr '[A-Z]' '[a-z]'`    
    if [ "${utilityDomain}" == "yes" ] ; then
      return 1
    fi
    if [ "${utilityDomain}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}

dcacheInstallGetIsPnfsManager()
{
  # returns 1 if is an pnfsManager is used 0 otherwise
  local NodeType
  local pnfsManager
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "node is admin so returns true"
    return 1
  fi
  if [ "${NodeType}" == "pool" ] ; then
    logmessage DEBUG "node is pool so returns false"
    return 0
  fi
  if [ "${NodeType}" == "door" ] ; then
    logmessage DEBUG "node is door so returns false"
    return 0
  fi
  if [ "${NodeType}" == "custom" ] ; then
    yaim_config_file_get_value "${ourHomeDir}/etc/node_config" pnfsManager
    pnfsManager=`echo "${RET}" | tr '[A-Z]' '[a-z]'`     
    if [ "${pnfsManager}" == "yes" ] ; then
      return 1
    fi
    if [ "${pnfsManager}" == "y" ] ; then
      return 1
    fi
  fi
  return 0
}


dcacheInstallGetIsAdmin()
{
  logmessage DEBUG "dcacheInstallGetIsAdmin.start"
  # returns 1 if is an admin node is used 0 otherwise
  local NodeType
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" NODE_TYPE
  NodeType=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${NodeType}" == "admin" ] ; then
    logmessage DEBUG "dcacheInstallGetIsAdmin.stop"
    return 1
  fi
  if [ "${NodeType}" == "custom" ] ; then
    local adminDoor
    local httpDomain
    local lmDomain
    local poolManager
    local utilityDomain
    # Get values
    dcacheInstallGetIsAdminDoor
    adminDoor=$?
    dcacheInstallGetIsHttpDomain
    httpDomain=$?
    dcacheInstallGetIsLmDomain
    lmDomain=$?
    dcacheInstallGetIsPoolManager
    poolManager=$?
    dcacheInstallGetIsUtilityDomain
    utilityDomain=$?
    if [ "${adminDoor}${httpDomain}${lmDomain}${poolManager}${utilityDomain}" == "11111" ] ; then
      logmessage DEBUG "dcacheInstallGetIsAdmin.stop"
      return 1	
    fi
  fi
  logmessage DEBUG "dcacheInstallGetIsAdmin.stop"
  return 0
}

dcacheInstallGetdCapPort()
{
  local DCACHE_HOME
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  yaim_config_file_get_value ${DCACHE_HOME}/config/dCacheSetup dCapPort
}

dcacheInstallPnfsMountPointClient()
{ 
  logmessage DEBUG "dcacheInstallPnfsMountPointClient.start"
  local PNFS_ROOT
  local SERVER_ID
  local DCACHE_HOME
  local pnfsMountPoint
  local NAMESPACE_NODE
  local exportPoint
  dcacheInstallGetServerId
  SERVER_ID=$RET
  dcacheInstallGetPnfsRoot
  PNFS_ROOT=$RET
  dcacheInstallGetHome
  DCACHE_HOME=$RET 
  dcacheInstallGetPnfsMountPoint
  pnfsMountPoint=${RET}
  dcacheInstallGetNameSpaceServer
  NAMESPACE_NODE=$RET
  logmessage INFO "Checking if ${pnfsMountPoint} mounted to the right export. ..."
  dcacheInstallGetExportPoint
  exportPoint=$RET
  if [ "${exportPoint}" = '/pnfsdoors' ] ; then
    logmessage INFO "OK"
  else
    if [ "${exportPoint}" != "" ] ; then
      logmessage WARNING "${pnfsMountPoint} mounted, however not to ${NAMESPACE_NODE}:/pnfsdoors."
      logmessage INFO "Unmounting it now:"
      umount ${pnfsMountPoint}
      
    fi
    if [ -L "${pnfsMountPoint}" ] ; then
      logmessage INFO "Trying to remove symbolic link ${pnfsMountPoint} :"
      rm -f ${pnfsMountPoint}
      if [ $? -eq 0 ] ; then
        logmessage INFO "'rm -f ${pnfsMountPoint}' went fine."
      else
        logmessage ABORT "'rm -f ${pnfsMountPoint}' failed. Please move it out of the way manually"
        logmessage ERROR "and run me again. Exiting."
        exit 1
      fi
    fi
    if [ ! -d "${pnfsMountPoint}" ]; then
      if [ -e "${pnfsMountPoint}" ] ; then
        logmessage ABORT "The file ${pnfsMountPoint} is in the way. Please move it out of the way"
        logmessage ERROR "and call me again. Exiting."
        exit 1
      else
        logmessage INFO "Creating pnfs mount point (${pnfsMountPoint})"
        mkdir -p ${pnfsMountPoint}
      fi
    fi
    dcacheInstallGetNameSpaceServer
    pnfsServer=$RET
    logmessage INFO "Will be mounted to ${pnfsServer}:/pnfsdoors by dcache-core start-up script."
  fi
  if [ ! -L "${PNFS_ROOT}/ftpBase" -a ! -e "${PNFS_ROOT}/ftpBase" ] ; then
    logmessage INFO "Creating link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} which is used by the GridFTP door."
    ln -s ${pnfsMountPoint} ${PNFS_ROOT}/ftpBase
  else
    local ftpBaseLinkedTo
    ftpBaseLinkedTo=`find ${PNFS_ROOT}/ftpBase -type l | xargs readlink`
    logmessage INFO "ftpBaseLinkedTo=$ftpBaseLinkedTo"
    logmessage INFO "pnfsMountPoint=${pnfsMountPoint}"
    if [ "${ftpBaseLinkedTo}" == "${pnfsMountPoint}" ] ; then
      logmessage INFO "Link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} already there."
    else
      logmessage ABORT "Link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} cannot be created. Needed by the GridFTP door."
      logmessage ERROR "Please move ${PNFS_ROOT}/ftpBase and run this script again. Exiting."
      exit 1
    fi
  fi
  if ! grep "^ftpBase=${PNFS_ROOT}/ftpBase" ${DCACHE_HOME}/config/dCacheSetup 2>/dev/null >/dev/null ; then
    logmessage WARNING "The file ${DCACHE_HOME}/config/dCacheSetup does not contain:"
    logmessage WARNING "   ftpBase=${PNFS_ROOT}/ftpBase"
    logmessage WARNING "Make shure it is set correctly before you start dCache."
  fi

  if mount | grep pnfs 2>/dev/null >/dev/null ; then
    logmessage WARNING "A pnfs export is already mounted. The GridFTP door will only use the"
    logmessage WARNING "mount at ${pnfsMountPoint} which will be mounted by the start-up script."
    logmessage WARNING "You might want to remove any mounts not needed anymore."
  fi
  logmessage DEBUG "dcacheInstallPnfsMountPointClient.stop"
  
}


dcacheInstallPnfsMountPointServer()
{
  logmessage DEBUG "dcacheInstallPnfsMountPointServer.start"
  local PNFS_ROOT
  local SERVER_ID
  local DCACHE_HOME
  local PNFS_INSTALL_DIR
  local pnfsMountPoint
  local serverIdLinkedTo
  local ftpBaseLinkedTo
  dcacheInstallGetServerId
  SERVER_ID=$RET
  dcacheInstallGetPnfsRoot
  PNFS_ROOT=$RET
  dcacheInstallGetHome
  DCACHE_HOME=${RET}
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" PNFS_INSTALL_DIR
  PNFS_INSTALL_DIR="${RET}"
  #    Checking and creating mountpoint and link
  #
  pnfsMountPoint=${PNFS_ROOT}/fs
  # if not a directory
  if [ ! -d "${pnfsMountPoint}" ]; then
    # if exists directory
    if [ -e "${pnfsMountPoint}" ] ; then
      logmessage ERROR "The file ${pnfsMountPoint} is in the way. Please move it out of the way"
      logmessage ERROR "and call me again. Exiting."
      exit 1
    else
      logmessage INFO "Creating pnfs mount point (${pnfsMountPoint})"
	mkdir -p ${pnfsMountPoint}
    fi
  fi
  dcacheInstallGetNameSpaceServer
  pnfsServer=$RET
  logmessage INFO "Will be mounted to ${pnfsServer}:/fs by dcache-core start-up script."

  cd ${PNFS_ROOT}
  # if file is not a symbolic link
  if [ ! -L "${SERVER_ID}" ]; then
    # if file exists
    if [ -e "${SERVER_ID}" ] ; then
      logmessage ERROR "The file/directory ${PNFS_ROOT}/${SERVER_ID} is in the way. Please move it out"
      logmessage ERROR "of the way and call me again. Exiting."
    else
      logmessage INFO "Creating link ${PNFS_ROOT}/${SERVER_ID} --> ${pnfsMountPoint}/usr/"
      ln -s fs/usr ${SERVER_ID}
      echo MADE THE SYMBOLIC LINK
    fi
  fi

  cd ${PNFS_ROOT}
  if [ ! -L "${SERVER_ID}" -a ! -e "${SERVER_ID}" ] ; then
    logmessage INFO "Creating link ${PNFS_ROOT}/${SERVER_ID} --> ${PNFS_ROOT}/fs/usr."
    ln -s fs/usr ${SERVER_ID}
  else
    serverIdLinkedTo=`find ${PNFS_ROOT}/${SERVER_ID} -type l | xargs readlink `
    if [ "${serverIdLinkedTo}" = "fs/usr" -o "${serverIdLinkedTo}" = "${PNFS_ROOT}/fs/usr" ] ; then
      logmessage INFO "Link ${PNFS_ROOT}/${SERVER_ID} --> ${PNFS_ROOT}/fs/usr already there."
    else
      logmessage ERROR "[ERROR] Link ${PNFS_ROOT}/${SERVER_ID} --> ${PNFS_ROOT}/fs/usr cannot be created."
      logmessage ERROR "Please move ${PNFS_ROOT}/${SERVER_ID} and run me again. Exiting."
      exit 1
    fi
  fi

  cd ${PNFS_ROOT}
  if [ ! -L ${PNFS_ROOT}/ftpBase -a ! -e ${PNFS_ROOT}/ftpBase ] ; then
    logmessage INFO "[INFO]  Creating link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} which is used by the GridFTP door."
    ln -s ${pnfsMountPoint} ${PNFS_ROOT}/ftpBase
  else
    ftpBaseLinkedTo=`ls -l ${PNFS_ROOT}/ftpBase | awk '{print $NF}'`
    if [ "${ftpBaseLinkedTo}" = "${pnfsMountPoint}" ] ; then
      logmessage INFO "Link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} already there."
    else
      logmessage ERROR "Link ${PNFS_ROOT}/ftpBase --> ${pnfsMountPoint} cannot be created. and is needed by the GridFTP door."
      logmessage ERROR "Please move ${PNFS_ROOT}/ftpBase and run me again. Exiting."
      exit 1
    fi
  fi

  # Checking for existance of rpcinfo
  #

  which rpcinfo 2>&1 > /dev/null
  RC=$?
  if [ ${RC} -ne 0 ] ; then 
    logmessage ERROR "rpcinfo is not on the path"
    exit 1
  fi

  #    Checking and maybe starting pnfs server
  #

  RETVAL=0
  rpcinfo -u localhost 100003 >/dev/null 2>&1
  RETVAL=$?
  if [ ${RETVAL} -eq 1 ]; then
    if [ ! -x ${PNFS_INSTALL_DIR}/tools/pnfs.server ]; then
      logmessage ERROR "PNFS not installed but needed for dCache admin node installation. Exiting."
      exit 1
    fi
    logmessage INFO "PNFS is not running. It is needed to prepare dCache. ... "
    yaim_config_file_get_value ${ourHomeDir}/etc/node_config PNFS_START
    yesno="${RET}"
    if [ \( "${yesno}" = "n" \) -o \( "${yesno}" = "no" \) ] ; then
      logmessage ERROR "Not allowed to start it. Set PNFS_START in etc/node_config to 'yes' or start by hand. Exiting."
      exit 1
    elif [ \( "${yesno}" = "y" \) -o \( "${yesno}" = "yes" \) ] ; then
      logmessage INFO "Trying to start it now:"
      ${PNFS_INSTALL_DIR}/tools/pnfs.server start
    fi
  fi

  #    Checking pnfs mount and possibly mounting
  #
  cp=`df ${pnfsMountPoint} 2>/dev/null | grep "${pnfsMountPoint}" | awk '{print $2}'`
  if [ -z ${cp} ]; then
    logmessage INFO "${pnfsMountPoint} mount point exists, but is not mounted - going to mount it now ..."
    mount -o intr,rw,noac,hard,nfsvers=2 ${pnfsServer}:/fs ${pnfsMountPoint}
  fi
  cp=`df ${pnfsMountPoint} 2>/dev/null | grep "${pnfsMountPoint}" | awk '{print $2}'`
  if [ -z $cp ]; then
    logmessage ERROR "Was not able to mount ${pnfsServer}:/fs to ${pnfsMountPoint}. Exiting."
    exit 1
  fi
  dcacheNameServerIs
  dcacheNameServerIsRc=$?
  if [ "${dcacheNameServerIsRc}" == "1" ]
  then
    dcacheInstallPnfsConfigCheck
  fi
  logmessage DEBUG "dcacheInstallPnfsMountPointServer.stop"
}

dcacheInstallPnfsMountPoints()
{
  logmessage DEBUG "dcacheInstallPnfsMountPoints.start"
  # Creating /pnfs/fs and Symbolic Link /pnfs/fs/usr to /pnfs/<domain> 
  # (e.g. /pnfs/fnal.gov) for GridFTP
  local dcacheNameServerIsRc
  local isGridFtp
  local isSrm
  local isPnfsManager

  dcacheInstallGetUseGridFtp
  isGridFtp=$?
  dcacheInstallGetUseSrm
  isSrm=$?
  dcacheNameServerIs
  dcacheNameServerIsRc=$?
  dcacheInstallGetIsPnfsManager
  isPnfsManager=$?
  if [ "${dcacheNameServerIsRc}" == "1" -o "${isPnfsManager}" == "1" ] ; then
    dcacheInstallPnfsMountPointServer
  else 
    if [ "${isPnfsManager}${isGridFtp}" == "01" -o "${isPnfsManager}${isSrm}" == "01" ] ; then
      dcacheInstallPnfsMountPointClient
    fi
  fi  
  logmessage DEBUG "dcacheInstallPnfsMountPoints.stop"
}



dcacheInstallChimeraMountPointServer()
{  
  local pnfsServer
  local PNFS_ROOT
  local localhostName
  local tryToMount
  local cmdline
  local counter
  local mountrc
  dcacheInstallGetPnfsRoot
  PNFS_ROOT=$RET
  if [ ! -d "${PNFS_ROOT}" ] ; then
    mkdir "${PNFS_ROOT}"
  fi
  dcacheInstallGetNameSpaceServer
  pnfsServer=$RET
  localhostName=`fqdn_os`
  tryToMount=1
  if [ "$pnfsServer" == "$localhostName" ] ; then
    pnfsServer="localhost"
  fi
  if [ -n "$(mount | grep "${pnfsServer}" )" ] ; then
    tryToMount=0
  fi
  if [ -n "$(mount | grep "/pnfs" )" ] ; then
    tryToMount=0
  fi
  if [ "${tryToMount}" == "0" ] ; then
    logmessage INFO "Already Mounted ${pnfsServer}"
  else
    cmdline="mount -o intr,rw,hard ${pnfsServer}:/pnfs /pnfs"
    counter=1
    logmessage INFO "Need to mount ${pnfsServer}"
    while [ "${tryToMount}" == "1" ] ; do
      $cmdline
      mountrc=$?
      if [ "${mountrc}" == "0" ] ; then
        logmessage INFO "Successflly mounted Chimera running $cmdline"
        tryToMount=0
      else
        let counter="$counter + 1"
        if [ "$counter" == "12" ] ; then
          logmessage ERROR "Failed running $cmdline and giving up"
          tryToMount=0
        else
          logmessage INFO "Trying to mount Chimera failed, will retry."
          logmessage DEBUG "Using command: $cmdline"
        fi
      fi
      sleep 1
    done
  fi
}



dcacheInstallChimeraMountPoints()
{
  logmessage DEBUG "dcacheInstallChimeraMountPoints.start"
  # Creating /pnfs/fs and Symbolic Link /pnfs/fs/usr to /pnfs/<domain> 
  # (e.g. /pnfs/fnal.gov) for GridFTP
  local isNameServer
  local isGridFtp
  local isSrm
  local isPnfsManager
  dcacheNameServerIs
  isNameServer=$?
  dcacheInstallGetUseGridFtp
  isGridFtp=$?
  dcacheInstallGetUseSrm
  isSrm=$?
  
  dcacheInstallGetIsPnfsManager
  isPnfsManager=$?
  if [ "${isNameServer}" == "1" -o "${isPnfsManager}" == "1" ] ; then
    /etc/init.d/portmap restart    
    dcacheInstallChimeraMountPointServer
  else
    if [ "${isPnfsManager}${isGridFtp}" == "01" -o "${isPnfsManager}${isSrm}" == "01" ] ; then   
      dcacheInstallChimeraMountPointServer
    fi
  fi
  logmessage DEBUG "dcacheInstallChimeraMountPoints.stop"
}

dcacheInstallMountPoints()
{
  logmessage DEBUG "dcacheInstallMountPoints.start"
  dcacheInstallGetNameSpaceType
  nameServerFormat=${RET}
  if [ "${nameServerFormat}" == "pnfs" ]
  then
    dcacheInstallPnfsMountPoints
  fi
  if [ "${nameServerFormat}" == "chimera" ]
  then
    dcacheInstallChimeraMountPoints
  fi
  logmessage DEBUG "dcacheInstallMountPoints.stop"
  
}


dcacheInstallPnfsConfigCheck()
{
  logmessage DEBUG "dcacheInstallPnfsConfigCheck.start"
  # Checking if pnfs config exists
  #
  local PNFS_ROOT
  local SERVER_ID
  local fqHostname
  local WRITING_PNFS
  local dCapPort
  local yesno
  local serverRoot
  fqHostname=`fqdn_os`
  dcacheInstallGetServerId
  SERVER_ID=$RET
  dcacheInstallGetPnfsRoot
  PNFS_ROOT=$RET
  dcacheInstallGetdCapPort
  dCapPort=$RET
  logmessage INFO "Checking on a possibly existing dCache/PNFS configuration ..."
  if [ -f ${PNFS_ROOT}/fs/admin/etc/config/serverRoot ]; then
    WRITING_PNFS=no
  else
    WRITING_PNFS=yes
  fi
  logmessage DEBUG "WRITING_PNFS=$WRITING_PNFS"
  yaim_config_file_get_value ${ourHomeDir}/etc/node_config PNFS_OVERWRITE
  yesno="${RET}"
  if [ \( "${yesno}" = "n" -o "${yesno}" = "no" \) -a "${WRITING_PNFS}" = "no" ] ; then
    logmessage INFO "Found an existing dCache/PNFS configuration!"
    logmessage INFO "Not allowed to overwrite existing PNFS configuration."
  elif [ \( "${yesno}" = "y" -o "${yesno}" = "yes" \) -a "${WRITING_PNFS}" = "no" ] ; then
    logmessage INFO "Found an existing dCache/PNFS configuration!"
    
    logmessage WARNING "Overwriting existing dCache/PNFS configuration..."
    
    WRITING_PNFS=yes
    
    sleep 5
  fi

  #     Writing new pnfs configuration
  #
  if [ "${WRITING_PNFS}" = "yes" ] ; then

    cd ${PNFS_ROOT}/fs
    serverRoot=`cat ".(id)(usr)"`
    logmessage DEBUG serverRoot=$serverRoot
    #     Writing Wormhole information
    #
    logmessage DEBUG "Changing directory to ${PNFS_ROOT}/fs/admin/etc/config"
    cd ${PNFS_ROOT}/fs/admin/etc/config
    
    echo "${fqHostname}" > ./serverName
    echo "${SERVER_ID}" >./serverId
    echo "$serverRoot ." > ./serverRoot

    touch ".(fset)(serverName)(io)(on)"
    touch ".(fset)(serverId)(io)(on)"
    touch ".(fset)(serverRoot)(io)(on)"

    echo "${fqHostname}" > ./serverName
    echo "${SERVER_ID}" >./serverId
    echo "$serverRoot ." > ./serverRoot

    mkdir -p dCache
    cd dCache
    echo "${fqHostname}:${dCapPort}" > ./dcache.conf
    touch ".(fset)(dcache.conf)(io)(on)"
    echo "${fqHostname}:${dCapPort}" > ./dcache.conf

    #     Configure directory tags
    #
    cd ${PNFS_ROOT}/fs/usr/data
    echo "StoreName myStore" > ".(tag)(OSMTemplate)"
    echo "STRING" > ".(tag)(sGroup)"
  fi
  dcacheInstallPnfsMount
  logmessage DEBUG "dcacheInstallPnfsConfigCheck.stop"
}


dcacheInstallPnfsMount()
{
  logmessage DEBUG "dcacheInstallPnfsMount.start"
  #  ----  Mount point for doors
  #    This is done, even if PNFS_OVERWRITE=no in order to
  #    cleanly upgrade
  #
  local PNFS_ROOT
  dcacheInstallGetPnfsRoot
  PNFS_ROOT=$RET
  cd ${PNFS_ROOT}/fs/admin/etc/exports
  if ! grep '^/pnfsdoors' * >/dev/null 2>/dev/null ; then
    logmessage INFO "Configuring pnfs export '/pnfsdoors' (needed from version 1.6.6 on)"
    logmessage INFO "mountable by world."
    echo '/pnfsdoors /0/root/fs/usr/ 30 nooptions' >> '0.0.0.0..0.0.0.0'
  else
    logmessage INFO "There already are pnfs exports '/pnfsdoors' in"
    logmessage INFO "        /pnfs/fs/admin/etc/exports. The GridFTP doors need access to it."
    if grep '^/pnfsdoors' * | grep -v ':/pnfsdoors[^[:graph:]]\+/0/root/fs/usr/[^[:graph:]]\+' >/dev/null 2>/dev/null ; then
      logmessage WARNING "  Make shure they all point to '/0/root/fs/usr/'! The GridFTP doors which"
      logmessage WARNING "        are not on the admin node will mount these from version 1.6.6 on."
    fi
  fi
  logmessage INFO "You may restrict access to this export to the GridFTP doors which"
  logmessage INFO "are not on the admin node. See the documentation." 
  logmessage DEBUG "dcacheInstallPnfsMount.stop"
}


dcacheInstallPnfs()
{
  dcacheInstallPnfsMountPoints
}


dcacheInstallSshKeys()
{
  # Install ssh keys for secure communication
  #
  logmessage DEBUG "dcacheInstallSshKeys.start"
  local DCACHE_HOME
  local nodeType
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  dcacheInstallGetIsAdmin
  nodeType=$?
  if [ "${nodeType}" = "1" ] ; then
    cd ${DCACHE_HOME}/config
    if [ -f ./server_key ]; then
      logmessage INFO "Skipping ssh key generation"
    else
      logmessage INFO "Generating ssh keys:"
      ssh-keygen -b 768 -t rsa1 -f ./server_key -N "" 2>&1 | logmessage INFO
      ln -s /etc/ssh/ssh_host_key ./host_key
    fi
  fi
  logmessage DEBUG "dcacheInstallSshKeys.stop"
}

#    Pool configuration
#
dcacheInstallCheckPool() 
{
  logmessage DEBUG "dcacheInstallCheckPool.start"
  local WRITING_POOL
  local rt
  local size
  local yesno
  local NUMBER_OF_MOVERS
  local DCACHE_HOME
  local shortHostname
  local pnl
  local x
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  rt=`echo ${rrt} | awk '{print $1}'`
  size=`echo ${rrt} | awk '{print $2}'`
    
  if [ -d "${rt}/pool" ]; then
    WRITING_POOL=no
  else
    WRITING_POOL=yes
  fi
    
  if [ "${WRITING_POOL}" = "no" ] ; then
    yesno=`echo ${rrt} | awk '{print $3}'`
    if [ \( "${yesno}" = "n" \) -o \( "${yesno}" = "no" \) ] ; then
      logmessage INFO "Not overwriting pool at ${rt}."	
    elif [ \( "${yesno}" = "y" \) -o \( "${yesno}" = "yes" \) ] ; then
      logmessage WARNING "Will overwrite pool at ${rt}."
      WRITING_POOL=yes
    else
      logmessage WARNING "Valid options for pool overwrite are y/yes or n/no. Assuming 'no'. "
    fi
  fi
    
  if [ "${WRITING_POOL}" = "yes" ] ; then	
    logmessage INFO "Creating Pool" ${pn}
    rm -rf ${rt}/pool
    mkdir -p ${rt}/pool
    mkdir -p ${rt}/pool/data
    mkdir -p ${rt}/pool/control
    cp ${DCACHE_HOME}/config/setup.temp  ${rt}/pool/setup.orig
    cd ${rt}/pool
    yaim_config_file_get_value ${ourHomeDir}/etc/node_config NUMBER_OF_MOVERS
    NUMBER_OF_MOVERS="${RET}"
    sed -e "s:set max diskspace 100:set max diskspace ${size}:g" setup.orig > setup.temp
    sed -e "s:mover set max active 10:mover set max active ${NUMBER_OF_MOVERS}:g" setup.temp > setup        
  fi
    
  cd ${rt}/pool
  ds=`eval df -k . | grep -v Filesystem | awk '{ print int($2/1048576) }'`
  let val=${ds}-${size}
  if [ ${val} -lt 0 ]; then
    logmessage ERROR "Pool size exceeds partition size "
  else
    shortHostname=`shortname_os`
    pnl=`grep "${pn}" ${DCACHE_HOME}/config/${shortHostname}.poollist | awk '{print $1}'`
    if [ -z "${pnl}" ]; then	   
      echo "${pn}  ${rt}/pool  sticky=allowed recover-space recover-control recover-anyway lfs=precious tag.hostname=${shortHostname}" \
        >> ${DCACHE_HOME}/config/${shortHostname}.poollist
    fi
  fi
  logmessage DEBUG "dcacheInstallCheckPool.stop"
}

dcacheInstallPool()
{  
  logmessage DEBUG "dcacheInstallPool.start" 
  local DCACHE_HOME
  local shortHostname
  local x
  local fileToProcess
  local linecount
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  shortHostname=`shortname_os`
  if [ ! -r "${DCACHE_HOME}/config/${shortHostname}.poollist" ]; then
    rm -f "${DCACHE_HOME}/config/${shortHostname}.poollist"
    touch "${DCACHE_HOME}/config/${shortHostname}.poollist"
  fi
  if [ -r ${DCACHE_HOME}/etc/pool_path ]; then
    logmessage WARNING "Defining pools in ${DCACHE_HOME}/etc/pool_path is deprecated."
    logmessage WARNING "Please use ${DCACHE_HOME}/bin/dcache pool create and"
    logmessage WARNING "${DCACHE_HOME}/bin/dcache pool add instead."

    # For all the static areas under rt make a pool
    fileToProcess=${DCACHE_HOME}/etc/pool_path
    let x=1
    linecount=`wc -l ${fileToProcess} | cut -d" " -f1`
    let linecount=${linecount}+1 
    while [ $x -lt $linecount ]
    do
      rrt=`sed "${x}q;d" ${fileToProcess}`
      pn=${shortHostname}"_"${x}
      dcacheInstallCheckPool
      let x=${x}+1
    done 
     
  fi
  
  logmessage DEBUG "dcacheInstallPool.stop" 
}


dcacheInstallSrm()
{
  logmessage DEBUG "dcacheInstallSrm.start"  
  local DCACHE_HOME
  local java
  local useSrm
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  yaim_config_file_get_value ${DCACHE_HOME}/config/dCacheSetup java
  java=$RET
  
  #
  # check java:
  #     jdk >= 1.5 , ( javac needed by tomcat/SRM )
  #

  if [ -z "${java}" ]; then
    logmessage ABORT "java variable in ${DCACHE_HOME}/config/dCacheSetup not defined"
    exit 6
  fi

  #
  # resove java path eg. /usr/bin/java = /usr/j2se_1.4.2/bin/java
  #
  java=`os_absolutePathOf ${java}`
  if [ -z "${java}" ]; then
    logmessage ABORT "java variable in ${DCACHE_HOME}/config/dCacheSetup do not point to existing binary"
    exit 7
  fi

  ${java} -version 2>&1 | grep version | egrep "1\.[56]\." >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    logmessage ABORT "java variable in ${DCACHE_HOME}/config/dCacheSetup do not point to java version 1.5.x or 1.6.x"
    exit 6
  fi
  # standard javac location $JAVA_HOME/bin/java
  # check for javac
  JAVA_HOME=${java%/bin/*}
  if [ ! -x ${JAVA_HOME}/bin/javac ]; then
    # on some system (e.g. Debian), $JAVA_HOME/bin/java points
    # to $JAVA_HOME/jre/bin/java. Try to go up another level.
    JAVA_HOME=${java%/jre/bin/*}
  fi
  # install SRM 
  #

  # put correct JAVA_HOME into srm_setup.env
  ( 
    grep -v JAVA_HOME ${DCACHE_HOME}/etc/srm_setup.env
    echo "JAVA_HOME=${JAVA_HOME}"
  ) > ${DCACHE_HOME}/etc/srm_setup.env.$$
  mv ${DCACHE_HOME}/etc/srm_setup.env.$$ ${DCACHE_HOME}/etc/srm_setup.env
  yaim_config_file_get_value "${ourHomeDir}/etc/node_config" SRM
  useSrm=`echo "${RET}" | tr '[A-Z]' '[a-z]'`
  if [ "${useSrm}" = yes ] ; then
    export loglevel logfile
    logmessage DEBUG "Running ${DCACHE_HOME}/install/deploy_srmv2.sh ${DCACHE_HOME}/etc/srm_setup.env"
    ${DCACHE_HOME}/install/deploy_srmv2.sh ${DCACHE_HOME}/etc/srm_setup.env 
  fi
  logmessage DEBUG "dcacheInstallSrm.stop"  
}

dcacheInstallCreateWrappers()
{
  logmessage DEBUG "dcacheInstallCreateWrappers.start"  
  local DCACHE_HOME
  dcacheInstallGetHome
  DCACHE_HOME=$RET
  #
  # init package ( create wrappers in jobs directory )
  #
  logmessage DEBUG "Running ${DCACHE_HOME}/jobs/initPackage.sh ${DCACHE_HOME} "
  ${DCACHE_HOME}/jobs/initPackage.sh ${DCACHE_HOME} 2>&1 
  if [ $? != 0 ]; then
    logmessage ABORT "Failed to initalize dCache installation, exiting."
    exit 2
  fi
  logmessage DEBUG "dcacheInstallCreateWrappers.stop"  
}


# Do the inistialtion checks


# Now start processing
check_shell
# Now check OS
check_os
if [ "$RET" == "Unknown" ] ; then
  echo "ERROR: OS is not found." 
  exit 1
fi

# now process the command line

while [ $# -ne 0 ]
do	
  # Default to shifting to next parameter
  shift_size=1		
  if [ $1 == "--prefix" -o $1 == "-p" ] 
  then
    # set dCache install location
    ourHomeDir=$2
    shift_size=2
  fi
  if [ $1 == "--help" -o $1 == "-h" ] 
  then
    # set dCache install location
    usage
    exit 0
  fi
  if [ $1 == "--loglevel" -o $1 == "-l"  ] 
  then
    # set dCache install location
    let loglevel=$2
    shift_size=2
  fi
  if [ $1 == "--logfile" ] 
  then
    # set dCache install location
    logfile=$2
    shift_size=2
  fi
  shift $shift_size
done

# Now check for missing files
check_install

dcacheInstallGetHome
dCacheInstallDir=`echo $RET | sed -e 's_//*_/_g' -e 's_/$__'`
dCacheHomeDir=`echo ${ourHomeDir} | sed -e 's_//*_/_g' -e 's_/$__'`

if [ "${dCacheInstallDir}" != "${dCacheHomeDir}" ] ; then
  logmessage ERROR "Dcache HOME is set incorrectly."
  logmessage INFO "${dCacheInstallDir} not equal to ${dCacheHomeDir}"
  exit 1
fi


dcacheNameServerIs
dcacheNameServerIsRc=$?
dcacheInstallGetIsAdmin
isAdmin=$?
dcacheInstallGetUseGridFtp
isGridFtp=$?
dcacheInstallGetUseSrm
isSrm=$?
nodetype=$(echo "${dcacheNameServerIsRc}${isAdmin}${isGridFtp}${isSrm}" | grep 1)

if [ "X${nodetype}" != "X" ]
then
  logmessage INFO "This node will need to mount the name server."
fi


dcacheInstallSshKeys
dcacheInstallCreateWrappers
dcacheInstallMountPoints
dcacheInstallSrm
dcacheInstallPool

exit 0
