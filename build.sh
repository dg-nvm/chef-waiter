#!/bin/bash

# Set version
VERSION_MAJOR=1
VERSION_MINOR=0
VERSION_PATCH=1
VERSION_SPECIAL=
VERSION=""

# Setup defaults
export GO_ARCH=amd64
export CGO_ENABLED=0

BUILD_WINDOWS=0
BUILD_LINUX=0
BIN_NAME="chef-waiter"
OUT_DIR=./artifacts
SCRIPT_PATH=$0

# Triggers
SHOW_VERSION_LONG=0
SHOW_VERSION_SHORT=0
UPDATE_VERSION=0
TAR_FILES=0

while test $# -gt 0; do
  case $1 in
    -h|--help)
      # Show help message
      echo "-w: Builds the windows binary."
      echo "-l: Builds the Linux binary."
      echo "-t: Tar and gzip files that are compiled."
      echo "-x86: Sets the builds to be 32bit."
      echo "--output-name=<bin name>: Sets the output binary to be what is supplied. Windows binarys will have a .exe suffix add to it."
      echo "--output-dir=</path/to/dir>: Sets the output directory for built binaries."
      echo "--version-major=*: Update the Major part of the version number."
      echo "--version-minor=*: Update the Minor part of the version number."
      echo "--version-patch=*: Update the Patch part of the version number."
      echo "--version-special=*: Update the Special part of the version number."
      echo "-n|--next-minor: Increments the version numer to the next patch."
      echo "-u|--update-version: Updates the buidl script with the new version number. Commits it to git."
      exit 0
      shift
      ;;
    -w)
      BUILD_WINDOWS=1
      shift
      ;;
    -l)
      BUILD_LINUX=1
      shift
      ;;
    -t)
      TAR_FILES=1
      shift
      ;;
    -v)
      SHOW_VERSION_SHORT=1
      shift
      ;;
    --version)
      SHOW_VERSION_LONG=1
      shift
      ;;
    -x86)
      export GO_ARCH=386
      shift
      ;;
    --output-name=*)
      BIN_NAME=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --output-dir=*)
      OUT_DIR=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --version-major=*)
      VERSION_MAJOR=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --version-minor=*)
      VERSION_MINOR=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --version-patch=*)
      VERSION_PATCH=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    --version-special=*)
      VERSION_SPECIAL=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    -n|--next-minor)
      let VERSION_PATCH+=1
      echo "Setting Patch number to: ${VERSION_PATCH}"
      shift
      ;;
    -u|--update-version)
      UPDATE_VERSION=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

# We need to set the version after all the flag are read.
VERSION=$VERSION_MAJOR.$VERSION_MINOR.$VERSION_PATCH
if [ "$SPECIAL" != "" ]; then
  VERSION=$VERSION-$VERSION_SPECIAL;
fi

# Setup functions
ensure_artifact_dir(){
  if [ ! -d $1 ]; then
    mkdir -p $1
    if [ $? -ne 0 ]; then
      echo "Failed to create the output directory: ${OUT_DIR}"
    fi
  fi
}

build_bin() {
  # Set GOOS
  goos=$1
  
  # Set the binary name
  bin_name=$BIN_NAME
  if [ $1 == "windows" ]; then
    bin_name="$BIN_NAME.exe"
  fi

  # Setup where it should go
  outdir=$OUT_DIR/$BIN_NAME-$goos-$GO_ARCH-v$VERSION
  output=$outdir/$bin_name

  # Ensure the artifact directory is there
  ensure_artifact_dir $outdir

  # Start the build
  GOOS=$goos \
  go build \
  -ldflags "-X main.VERSION=$VERSION" \
  -a \
  -installsuffix cgo \
  -o $output

  # Check if it worked
  if [ $? -eq 0 ]; then
    echo "Binary built and store as: $output"
  else
    echo "Binary for $goos failed to build!"
    exit 1
  fi
}

# Show version
if [ $SHOW_VERSION_LONG -eq 1 ]; then
  echo "Current version number in build script: ${VERSION}"
  exit 0
fi

if [ $SHOW_VERSION_SHORT -eq 1 ]; then
  echo "v$VERSION"
  exit 0
fi

# Update the version in this file
if [ $UPDATE_VERSION -eq 1 ]; then
  echo "Updating the build script with new version numbers."
  sed -i -r 's/^VERSION_MAJOR=[0-9]+$/VERSION_MAJOR='"$VERSION_MAJOR"'/' $SCRIPT_PATH \
  && sed -i -r 's/^VERSION_MINOR=[0-9]+$/VERSION_MINOR='"$VERSION_MINOR"'/' $SCRIPT_PATH \
  && sed -i -r 's/^VERSION_PATCH=[0-9]+$/VERSION_PATCH='"$VERSION_PATCH"'/' $SCRIPT_PATH \
  && sed -i -r 's/^VERSION_SPECIAL=*$/VERSION_SPECIAL='"$VERSION_SPECIAL"'/' $SCRIPT_PATH

  if [ $? -eq 0 ]; then
    echo "Committing updated build script to git."
    echo "WARNING: This commit will be skipped by CI."
    if ! git remote remove origin && git remote add origin https://${GH_TOKEN}@github.com/${TRAVIS_REPO_SLUG}.git; then
      echo "Failed to add a new origin for  git."
      exit 1
    fi
    git add $SCRIPT_PATH \
    && git commit -m "[skip ci] BUILD_SCRIPT: Changing version number for build script to ${VERSION}." \
    && git push HEAD:master origin

    if [ $? -ne 0 ]; then
      echo "Something went wrong while pushing the new version numbers. Exiting."
      exit 1
    fi
  fi
fi

if [ $BUILD_LINUX -eq 1 ]; then
  build_bin "linux"
fi

if [ $BUILD_WINDOWS -eq 1 ]; then
  build_bin "windows"
fi

if [ $TAR_FILES -eq 1 ]; then
  echo "Starting compression of binaries"
  cd $OUT_DIR
  for d in $(ls); do
    echo "starting tar and gzip on $d"
    tar -czvf $d.tar.gz $d
  done
fi

echo "Finished."
