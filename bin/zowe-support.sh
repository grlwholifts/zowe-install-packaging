#!/bin/sh

################################################################################
# This program and the accompanying materials are made available under the terms of the
# Eclipse Public License v2.0 which accompanies this distribution, and is available at
# https://www.eclipse.org/legal/epl-v20.html
#
# SPDX-License-Identifier: EPL-2.0
#
# Copyright IBM Corporation 2019, 2020
################################################################################

. ${ROOT_DIR}/bin/internal/zowe-set-env.sh

INSTALL_LOG_DIRECTORY=${ROOT_DIR}/install_log/
LOGS_DIRECTORY=${INSTANCE_DIR}/logs

DATE=`date +%Y-%m-%d-%H-%M-%S`
SUPPORT_ARCHIVE_LOCATION=$LOGS_DIRECTORY
SUPPORT_ARCHIVE_NAME="zowe_support_${DATE}.pax"
SUPPORT_ARCHIVE=${SUPPORT_ARCHIVE_LOCATION}/${SUPPORT_ARCHIVE_NAME}
SUPPORT_ARCHIVE_LOG="${SUPPORT_ARCHIVE_LOCATION}/zowe_support_${DATE}.log"
PS_OUTPUT_FILE=${SUPPORT_ARCHIVE_LOCATION}"/ps_output"
VERSION_FILE=${SUPPORT_ARCHIVE_LOCATION}"/version_output"

ZOWE_STC=${ZOWE_PREFIX}${ZOWE_INSTANCE}SV

function psgrep {
    pattern=[^]]${1};
    # [^]] used to concatenate a static string to the pattern. Done to remove grep command from output
    ps -A -o pid,ppid,time,etime,user,jobname,args | grep -e "^[[:space:]]*PID" -e ${pattern}
}

function write_to_log {
    echo $1 | tee -a ${SUPPORT_ARCHIVE_LOG}
}

function add_to_pax {
    case $2 in
        process_info)
            SUBSTITUTION="-s#${SUPPORT_ARCHIVE_LOCATION}#PS_OUTPUT_FILE#"
        ;;
        version_file)
            SUBSTITUTION="-s#${SUPPORT_ARCHIVE_LOCATION}#VERSION_FILE#"
        ;;
        support_archive_log)
            SUBSTITUTION="-s#${SUPPORT_ARCHIVE_LOCATION}#SUPPORT_LOG#"
        ;;
        zlux_server_log)
            SUBSTITUTION="-s#${ZOWE_INSTALL_ZLUX_SERVER_LOG}#ZLUX_SERVER_LOG-#"
        ;;
        *)  # basic command (no substitution is applied)
            SUBSTITUTION=""
        ;;
    esac
    pax -wva -o saveext ${SUBSTITUTION} -s#${ROOT_DIR}#ROOT_DIR# -s#${INSTANCE_DIR}#INSTANCE_DIR# -s#${KEYSTORE_DIRECTORY}#KEYSTORE_DIRECTORY# -f ${SUPPORT_ARCHIVE}  $1 2>&1 | tee -a ${SUPPORT_ARCHIVE_LOG}
}

function add_file_to_pax_if_found {
    FILE_PATH=$1
    if [[ -f ${FILE_PATH} ]];then
        write_to_log "Collecting ${FILE_PATH}"
        add_to_pax ${FILE_PATH}
    else
        write_to_log "File ${FILE_PATH} was not found."
    fi
}

# Collecting software versions
write_to_log "Collecting version of z/OS, Java, NodeJS"
ZOS_VERSION=`${ROOT_DIR}/scripts/internal/opercmd "D IPLINFO" | grep -i release | xargs`
write_to_log "  - z/OS: $ZOS_VERSION"
JAVA_VERSION=`$JAVA_HOME/bin/java -version 2>&1 | head -n 1`
write_to_log "  - Java: $JAVA_VERSION"
NODE_VERSION=`$NODE_HOME/bin/node --version`
write_to_log "  - NodeJS: $NODE_VERSION"
echo "z/OS version: "$ZOS_VERSION > $VERSION_FILE
echo "Java version: "$JAVA_VERSION >> $VERSION_FILE
echo "NodeJS version: "$NODE_VERSION >> $VERSION_FILE
add_to_pax $VERSION_FILE version_file
rm $VERSION_FILE

# Collect process information
write_to_log "Collecting current process information based on the following prefix: ${ZOWE_PREFIX}$ZOWE_INSTANCE"
psgrep $ZOWE_PREFIX$ZOWE_INSTANCE > $PS_OUTPUT_FILE
write_to_log "Adding ${PS_OUTPUT_FILE}"
add_to_pax $PS_OUTPUT_FILE process_info
rm $PS_OUTPUT_FILE

# Collect STC output
STC_JOBS=`tsocmd "STATUS ${ZOWE_STC}" 2>/dev/null | grep -E 'OUTPUT' | cut -d' ' -f2`
for STC in ${STC_JOBS}
do
    write_to_log "Collecting output for Zowe started task ${STC}"
    STC_FILE=`echo ${STC} | tr '()' '-.'`log
    # TODO NOW - tsocmd output doesn't produce anything and purges job
    tsocmd "output ${STC}" > $STC_FILE
    add_to_pax $STC_FILE
    rm $STC_FILE
done

# Collect install logs
if [[ -d ${INSTALL_LOG_DIRECTORY} ]];then
    write_to_log "Collecting installation log files from ${INSTALL_LOG_DIRECTORY}:"
    add_to_pax ${INSTALL_LOG_DIRECTORY} installation_log *.log
else
    write_to_log "Directory ${INSTALL_LOG_DIRECTORY} was not found."
fi

# Collect rest of logs
if [[ -d ${LOGS_DIRECTORY} ]];then
    write_to_log "Collecting instance log files from ${LOGS_DIRECTORY}:"
    add_to_pax ${LOGS_DIRECTORY} instance_logs *.log
else
    write_to_log "Directory ${LOGS_DIRECTORY} was not found."
fi

# TODO - collect all the rest of workspace directory?
add_file_to_pax_if_found "${INSTANCE_DIR}/instance.env"
add_file_to_pax_if_found "${KEYSTORE_DIRECTORY}/zowe-certificates.env"
add_file_to_pax_if_found "$ROOT_DIR/manifest.json"

# Collect api-definitions
API_DEFS_DIRECTORY="${INSTANCE_DIR}/workspace/api-mediation/api-defs"
if [[ -d ${API_DEFS_DIRECTORY} ]];then
    write_to_log "Collecting instance log files from ${API_DEFS_DIRECTORY}:"
    add_to_pax ${API_DEFS_DIRECTORY} api-defs *.yml
else
    write_to_log "Directory ${API_DEFS_DIRECTORY} was not found."
fi

# Add support log file to pax
write_to_log "Adding ${SUPPORT_ARCHIVE_LOG}"
add_to_pax ${SUPPORT_ARCHIVE_LOG} support_archive_log
rm ${SUPPORT_ARCHIVE_LOG}

# Compress pax file
compress ${SUPPORT_ARCHIVE}

# Print final message
echo "The support file was created, pass it to support guys. Thanks."
echo ${SUPPORT_ARCHIVE}.Z

# done
