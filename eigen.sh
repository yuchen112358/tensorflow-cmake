#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"

################################### Functions ###################################

# Prints an error message and exits with an error code of 1
fail () {
    echo "Command failed; script terminated"
    exit 1
}

# Prints usage information concerning this script
print_usage () {
    echo "|
| Usage: ${0} generate|install [args]
|
| --> ${0} generate installed|external <tensorflow-source-dir> [<cmake-dir> <install-dir>]:
|
|     Generates the cmake files for the given installation of tensorflow
|     and writes them to <cmake-dir>.  If 'generate installed' is executed,
|     <install-dir> corresponds to the directory Eigen was installed to; 
|     defaults to /usr/local.
|
| --> ${0} install <tensorflow-source-dir> [<install-dir> <download-dir>]
|
|     Downloads Eigen to <donload-dir> (defaults to the current directory),
|     and installs it to <instal-dir> (defaults to /usr/local).
|"
}

# Tries to find eigen using the given method
# Methods begin at 0 and increase as integers.
# If this function is called with a method that
# does not exist, it will print an error message
# and exit the program.
find_eigen () {
    # Check for argument
    if [ -z "${1}" ]; then
	fail
    fi
    # locate eigen archive in tensorflow directory
    ANY="[^\)]*"
    ANY_NO_QUOTES="[^\)\\\"]*"
    ANY_HEX="[a-fA-F0-9]*"
    ARCHIVE_HEADER="native.new_http_archive\(\s*"
    NAME_START="name\s*=\s*\\\""
    QUOTE_START="\s*=\s*\\\""
    QUOTE_END="\\\"\s*,\s*"
    FOOTER="\)"
    EIGEN_NAME="${NAME_START}eigen_archive${QUOTE_END}"
    EIGEN_REGEX="${ARCHIVE_HEADER}${ANY}${EIGEN_NAME}${ANY}${FOOTER}"
    
    echo "Finding Eigen version in ${TF_DIR} using method ${1}..."
    # check specified format
    if [ ${1} -eq 0 ]; then
	EIGEN_VERSION_LABEL="eigen_version"
	EIGEN_ARCHIVE_HASH_REGEX="${EIGEN_VERSION_LABEL}\s*=\s*\\\"${ANY_HEX}\\\"\s*"
	EIGEN_HASH_REGEX="eigen_sha256\s*=\s*\\\"${ANY_HEX}\\\"\s*"
	HASH_SED="s/\s*eigen_sha256${QUOTE_START}\(${ANY_HEX}\)\\\"\s*/\1/p"
	ARCHIVE_HASH_SED="s/\s*${EIGEN_VERSION_LABEL}${QUOTE_START}\(${ANY_HEX}\)\\\"\s*/\1/p"
	
	
	EIGEN_TEXT=$(grep -Pzo ${EIGEN_REGEX} ${TF_DIR}/tensorflow/workspace.bzl) || fail
	EIGEN_ARCHIVE_TEXT=$(grep -Pzo ${EIGEN_ARCHIVE_HASH_REGEX} ${TF_DIR}/tensorflow/workspace.bzl)
	EIGEN_HASH_TEXT=$(grep -Pzo ${EIGEN_HASH_REGEX} ${TF_DIR}/tensorflow/workspace.bzl)

	# note that we must determine the eigen archive hash before we determine the URL
	EIGEN_HASH=$(echo "${EIGEN_HASH_TEXT}" | sed -n ${HASH_SED})
	EIGEN_ARCHIVE_HASH=$(echo "${EIGEN_ARCHIVE_TEXT}" | sed -n ${ARCHIVE_HASH_SED})

	URL_SED="s/\s*url${QUOTE_START}\(${ANY_NO_QUOTES}\)\\\"\s*+\s*${EIGEN_VERSION_LABEL}\s*+\s*\\\"\(${ANY_NO_QUOTES}\)${QUOTE_END}/\1${EIGEN_ARCHIVE_HASH}\2/p"
	EIGEN_URL=$(echo "${EIGEN_TEXT}" | sed -n ${URL_SED})
    elif [ ${1} -eq 1 ]; then
	# find eigen without 'eigen_version' or 'eigen_sha256'
	URL_SED="s/\s*url${QUOTE_START}\(${ANY_NO_QUOTES}\)${QUOTE_END}/\1/p"
	HASH_SED="s/\s*sha256${QUOTE_START}\(${ANY_HEX}\)${QUOTE_END}/\1/p"
	ARCHIVE_HASH_SED="s=.*/\(${ANY_HEX}\)\\.tar\\.gz=\1=p"
	
	EIGEN_TEXT=$(grep -Pzo ${EIGEN_REGEX} ${TF_DIR}/tensorflow/workspace.bzl)
	EIGEN_URL=$(echo "${EIGEN_TEXT}" | sed -n ${URL_SED})
	EIGEN_HASH=$(echo "${EIGEN_TEXT}" | sed -n ${HASH_SED})
	EIGEN_ARCHIVE_HASH=$(echo "${EIGEN_URL}" | sed -n ${ARCHIVE_HASH_SED})
    else
	# no methods left to try
	echo "Failure: could not find Eigen version in ${TF_DIR}"
	exit 1
    fi
    # check if all variables were defined and are unempty
    if [ -z "${EIGEN_URL}" ] || [ -z "${EIGEN_HASH}" ] || [ -z "${EIGEN_ARCHIVE_HASH}" ]; then
	# unset varibales and return 1 (not found)
	unset EIGEN_URL
	unset EIGEN_HASH
	unset EIGEN_ARCHIVE_HASH
	return 1
    fi
    # return found
    return 0 
}

################################### Script ###################################

# validate and assign input
if [ "$#" -lt 2 ]; then
    print_usage
    exit 1
fi
# Determine mode
if [ "${1}" == "install" ]; then
    MODE="install"
elif [ "${1}" == "generate" ]; then
    MODE="generate"
else
    print_usage
    exit 1
fi

# get arguments
if [ "${MODE}" == "install" ]; then
    TF_DIR="${2}"
    INSTALL_DIR="/usr/local"
    DOWNLOAD_DIR="."
    if [ "$#" -gt 2 ]; then
       INSTALL_DIR="${3}"
    fi
    if [ "$#" -gt 3 ]; then
	DOWNLOAD_DIR="${4}"
    fi
elif [ "${MODE}" == "generate" ]; then
    GENERATE_MODE="${2}"
    if [ "${GENERATE_MODE}" != "installed" ] && [ "${GENERATE_MODE}" != "external" ]; then
	print_usage
	exit 1
    fi
    TF_DIR="${3}"
    CMAKE_DIR="."
    if [ "$#" -gt 3 ]; then
	CMAKE_DIR="${4}"
    fi
    INSTALL_DIR="/usr/local"
    if [ "${GENERATE_MODE}" == "installed" ] && [ "$#" -gt 4 ]; then
	INSTALL_DIR="${5}"
    fi
fi

# try to find eigen information
N=0
find_eigen ${N}
while [ $? -eq 1 ]; do
    N=$((N+1))
    find_eigen $N
done

# print information
echo
echo "Eigen URL:           ${EIGEN_URL}"
echo "Eigen URL Hash:      ${EIGEN_HASH}"
echo "Eigen Archive Hash:  ${EIGEN_ARCHIVE_HASH}"
echo

# perform requested action
if [ "${MODE}" == "install" ]; then
    # donwload eigen and extract to download directory
    echo "Downlaoding Eigen to ${DOWNLOAD_DIR}"
    cd ${DOWNLOAD_DIR} || fail
    rm -rf eigen-eigen-${EIGEN_ARCHIVE_HASH} || fail
    rm -f ${EIGEN_ARCHIVE_HASH}.tar.gz* || fail
    wget ${EIGEN_URL} || fail
    tar -zxvf ${EIGEN_ARCHIVE_HASH}.tar.gz || fail
    cd eigen-eigen-${EIGEN_ARCHIVE_HASH} || fail
    # create build directory and build
    mkdir build || fail
    cd build
    cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} -DINCLUDE_INSTALL_DIR=${INSTALL_DIR}/include/eigen/eigen-eigen-${EIGEN_ARCHIVE_HASH} .. || fail
    make || fail
    make install || fail
    echo "Installation complete"
    echo "Cleaning up..."
    # clean up
    cd ../..
    rm -rf eigen-eigen-${EIGEN_ARCHIVE_HASH} || fail
    rm -f ${EIGEN_ARCHIVE_HASH}.tar.gz* || fail
elif [ "${MODE}" == "generate" ]; then
     # locate eigen in INSTALL_DIR
    if [ -d "${INSTALL_DIR}/include/eigen/eigen-eigen-${EIGEN_ARCHIVE_HASH}" ]; then
       echo "Found Eigen in ${INSTALL_DIR}"
    else
	echo "Failure: Could not find Eigen in ${INSTALL_DIR}"
	exit 1
    fi
    # output Eigen information to file
    EIGEN_OUT="${CMAKE_DIR}/Eigen_VERSION.cmake"
    echo "set(Eigen_URL ${EIGEN_URL})" > ${EIGEN_OUT} || fail
    echo "set(Eigen_ARCHIVE_HASH ${EIGEN_ARCHIVE_HASH})" >> ${EIGEN_OUT} || fail
    echo "set(Eigen_HASH SHA256=${EIGEN_HASH})" >> ${EIGEN_OUT} || fail
    echo "set(Eigen_DIR eigen-eigen-${EIGEN_ARCHIVE_HASH})" >> ${EIGEN_OUT} || fail
    echo "set(Eigen_INSTALL_DIR ${INSTALL_DIR})" >> ${EIGEN_OUT} || fail
    echo "Eigen_VERSION.cmake written to ${CMAKE_DIR}"
    # perform specific operations regarding installation
    if [ "${GENERATE_MODE}" == "external" ]; then
	cp ${SCRIPT_DIR}/Eigen.cmake ${CMAKE_DIR} || fail
	echo "Wrote Eigen_VERSION.cmake and Eigen.cmake to ${CMAKE_DIR}"
    elif [ "${GENERATE_MODE}" == "installed" ]; then
	cp ${SCRIPT_DIR}/FindEigen.cmake ${CMAKE_DIR} || fail
	echo "FindEigen.cmake copied to ${CMAKE_DIR}"
    fi
fi

echo "Done"
exit 0
