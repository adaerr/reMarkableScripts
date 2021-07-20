#!/bin/sh
# Transfer PDF file(s) to a reMarkable
# Adrian Daerr 2017/2018 - public domain
#
# - The files will appear in reMarkable's top-level "My Files" directory,
# - After finishing all transfers, you have to restart the xochitl
#   service on the tablet in order to force a scan of its document
#   directory ${xochitldir} (so that you see the newly transferred
#   files), e.g. by sending the tablet the following command: 
#     ssh remarkable systemctl restart xochitl
#
# Disclaimer and liability limitation:
# [see also all-caps text borrowed from GPL below]
# - This is a dirty hack based on superficial reverse-engineering.
# - Expect this script to break at any time, especially upon a
#   reMarkable system upgrade
# - I am not responsible for any damage caused by this script,
#   including (but not limited to) bricking your reMarkable, erasing
#   your documents etc. YOU ARE USING THIS SOFTWARE ON YOUR OWN RISK.
#
# Disclaimer of Warranty.
#
# THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
# APPLICABLE LAW. EXCEPT WHEN OTHERWISE STATED IN WRITING THE
# COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM
# “AS IS” WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE
# RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.
# SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
# NECESSARY SERVICING, REPAIR OR CORRECTION.
#
# Limitation of Liability.
#
# IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN
# WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO
# MODIFIES AND/OR CONVEYS THE PROGRAM AS PERMITTED ABOVE, BE
# LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
# INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR
# INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
# DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY
# YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE
# WITH ANY OTHER PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS
# BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
#
# Prerequisites:
#
# * The ssh access has to be configured under the host alias 'remarkable',
# e.g. by putting the following in .ssh/config :
# | host remarkable
# |        Hostname 10.11.99.1
# |        User root
# |        ForwardX11 no
# |        ForwardAgent no
# See also the variable "xochitldir" below
#
# * Beyond core utilities (date, basename,...), the following software
#   has to be installed on the host computer:
# - uuidgen

# This is where ssh will try to copy the files associated with the document
REMARKABLE_HOST=${REMARKABLE_HOST:-remarkable}
REMARKABLE_XOCHITL_DIR=${REMARKABLE_XOCHITL_DIR:-.local/share/remarkable/xochitl/}
TARGET_DIR="${REMARKABLE_HOST}:${REMARKABLE_XOCHITL_DIR}"

# Check if we have something to do
if [ $# -lt 1 ]; then
    echo "Transfer PDF or Epub document to a reMarkable tablet"
    echo "usage: $(basename $0) [ -r ] path-to-pdf-file [path-to-pdf-file]..."
    exit 1
fi

RESTART_XOCHITL_DEFAULT=${RESTART_XOCHITL_DEFAULT:-0}
RESTART_XOCHITL=${RESTART_XOCHITL_DEFAULT}
if [ "$1" = "-r" ] ; then
    shift
    if [ $RESTART_XOCHITL_DEFAULT -eq 0 ] ; then
        echo Switching
        RESTART_XOCHITL=1
    else
        RESTART_XOCHITL=0
    fi
fi

# Create directory where we prepare the files as the reMarkable expects them
tmpdir=$(mktemp -d)

# Loop over the command line arguments,
# which we expect are paths to the PDF files to be transferred
for filename in "$@" ; do

    # reMarkable documents appear to be identified by universally unique IDs (UUID),
    # so we generate one for the document at hand
    uuid=$(uuidgen)

	extension="${filename##*.}"

    # Copy the file itself
    cp -- "$filename" "${tmpdir}/${uuid}.${extension}"

    # Add metadata
    # The lastModified item appears to contain the date in milliseconds since Epoch
    cat <<EOF >>${tmpdir}/${uuid}.metadata
{   
    "deleted": false,
    "lastModified": "$(date +%s)000",
    "metadatamodified": false,
    "modified": false,
    "parent": "",
    "pinned": false,
    "synced": false,
    "type": "DocumentType",
    "version": 1,
    "visibleName": "$(basename -- "$filename" ".$extension")"
}
EOF

	if [ "$extension" = "pdf" ]; then
		# Add content information
		cat <<EOF >${tmpdir}/${uuid}.content
{   
    "extraMetadata": {
    },
    "fileType": "pdf",
    "fontName": "",
    "lastOpenedPage": 0,
    "lineHeight": -1,
    "margins": 100,
    "pageCount": 1,
    "textScale": 1,
    "transform": {
        "m11": 1,
        "m12": 1,
        "m13": 1,
        "m21": 1,
        "m22": 1,
        "m23": 1,
        "m31": 1,
        "m32": 1,
        "m33": 1
    }
}
EOF
		# Add cache directory
		mkdir ${tmpdir}/${uuid}.cache

		# Add highlights directory
		mkdir ${tmpdir}/${uuid}.highlights

		# Add thumbnails directory
		mkdir ${tmpdir}/${uuid}.thumbnails

	elif [ "$extension" == "epub" ]; then

		# Add content information
		cat <<EOF >${tmpdir}/${uuid}.content
{
    "fileType": "epub"
}
EOF
	else
		echo "Unknown extension: $extension, skipping $filename"
    rm -rf ${tmpdir}/*
		continue
	fi

    # Transfer files
    echo "Transferring $filename as $uuid"
    scp -r ${tmpdir}/* "${TARGET_DIR}"
    rm -rf ${tmpdir}/*
done

rm -rf ${tmpdir}

if [ $RESTART_XOCHITL -eq 1 ] ; then
    echo "Restarting Xochitl..."
    ssh ${REMARKABLE_HOST} "systemctl restart xochitl"
    echo "Done."
fi
