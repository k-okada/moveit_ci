#!/bin/bash -x

# Software License Agreement - BSD License
#
# Inspired by MoveIt! travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

# Note: ROS_REPOSITORY_PATH is no longer a valid option, use ROS_REPO. See README.md

export CI_SOURCE_PATH=$(pwd) # The repository code in this pull request that we are testing
export CI_PARENT_DIR=.moveit_ci  # This is the folder name that is used in downstream repositories in order to point to this repo.
export HIT_ENDOFSCRIPT=false
export REPOSITORY_NAME=${PWD##*/}
export CATKIN_WS=/root/ws_moveit
echo "---"
echo "Testing branch '$TRAVIS_BRANCH' of '$REPOSITORY_NAME' on ROS '$ROS_DISTRO'"

# Helper functions
source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

# Run all CI in a Docker container
if ! [ "$IN_DOCKER" ]; then

    # Choose the correct CI container to use
    case "$ROS_REPO" in
        ros-shadow-fixed)
            export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci-shadow-fixed
            ;;
        *)
            export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci
            ;;
    esac
    echo "Starting Docker image: $DOCKER_IMAGE"

    # Pull first to allow us to hide console output
    docker pull $DOCKER_IMAGE > /dev/null

    # Start Docker container
    docker run \
        -e ROS_REPO \
        -e ROS_DISTRO \
        -e BEFORE_SCRIPT \
        -e CI_PARENT_DIR \
        -e CI_SOURCE_PATH \
        -e UPSTREAM_WORKSPACE \
        -e TRAVIS_BRANCH \
        -e TEST \
        -e TEST_BLACKLIST \
        -v $(pwd):/root/$REPOSITORY_NAME $DOCKER_IMAGE \
        /bin/bash -c "cd /root/$REPOSITORY_NAME; source .moveit_ci/travis.sh;"
    return_value=$?

    if [ $return_value -eq 0 ]; then
        echo "$DOCKER_IMAGE container finished successfully"
        HIT_ENDOFSCRIPT=true;
        exit 0
    fi
    echo "$DOCKER_IMAGE container finished with errors"
    exit 1 # error
fi

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

# Update the sources
travis_run apt-get -qq update

# Split for different tests
for t in $TEST; do
    case "$t" in
        "clang-format")
            source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/check_clang_format.sh || exit 1
            exit 0 # This runs as an independent job, do not run regular travis test
        ;;
    esac
done

# Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
travis_run rosdep update

# Create workspace
travis_run mkdir -p $CATKIN_WS/src
travis_run cd $CATKIN_WS/src

# Install dependencies necessary to run build using .rosinstall files
if [ ! "$UPSTREAM_WORKSPACE" ]; then
    export UPSTREAM_WORKSPACE="debian";
fi
case "$UPSTREAM_WORKSPACE" in
    debian)
        echo "Obtain deb binary for upstream packages."
        ;;
    http://* | https://*) # When UPSTREAM_WORKSPACE is an http url, use it directly
        travis_run wstool init .
        # Handle multiple rosintall entries.
        IFS=','  # Multiple URLs can be given separated by comma.
        for rosinstall in $UPSTREAM_WORKSPACE; do
            travis_run wstool merge -k $rosinstall
        done
        ;;
    *) # Otherwise assume UPSTREAM_WORKSPACE is a local file path
        travis_run wstool init .
        if [ -e $CI_SOURCE_PATH/$UPSTREAM_WORKSPACE ]; then
            # install (maybe unreleased version) dependencies from source
            travis_run wstool merge file://$CI_SOURCE_PATH/$UPSTREAM_WORKSPACE
        else
            echo "No rosinstall file found, aborting" && exit 1
        fi
        ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    # the exclamation mark means to ignore errors
    travis_run_true wstool rm $REPOSITORY_NAME
    travis_run cat .rosinstall
    travis_run wstool update
fi

# link in the repo we are testing
travis_run ln -s $CI_SOURCE_PATH .

# Debug: see the files in current folder
travis_run ls -a

# Run before script
if [ "${BEFORE_SCRIPT// }" != "" ]; then
    travis_run sh -c "${BEFORE_SCRIPT}";
fi

# Install source-based package dependencies
travis_run rosdep install -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run cd $CATKIN_WS

# Configure catkin
travis_run catkin config --extend /opt/ros/$ROS_DISTRO --install --cmake-args -DCMAKE_BUILD_TYPE=Release

# Console output fix for: "WARNING: Could not encode unicode characters"
export PYTHONIOENCODING=UTF-8

# For a command that doesn’t produce output for more than 10 minutes, prefix it with my_travis_wait
my_travis_wait 60 catkin build --no-status --summarize || exit 1

# Source the new built workspace
travis_run source install/setup.bash;

# Choose which packages to run tests on
function hoge() {
  local command=$@

  echo $command
for var in $command
do
    echo "  The length of argument '$var' is: ${#var}"
done
}
function fuga() {
  local command=$*

  echo $command
for var in $command
do
    echo "  The length of argument '$var' is: ${#var}"
done
}
function hoga() {
  local command="$@"

  echo $command
for var in $command
do
    echo "  The length of argument '$var' is: ${#var}"
done
}

echo -e "Test blacklist: $TEST_BLACKLIST"
echo "--------------"
export SOURCE_PKGS_=`catkin_topological_order "$CI_SOURCE_PATH" --only-names`
echo -e "Catkin packages in source repo: $SOURCE_PKGS_"
for var in $SOURCE_PKGS_
do
    echo " - The length of argument '$var' is: ${#var}"
done
hoge a b c $SOURCE_PKGS_
fuga a b c $SOURCE_PKGS_
hoga a b c $SOURCE_PKGS_
export SOURCE_PKGS_=`catkin_topological_order ${CI_SOURCE_PATH} --only-names`
echo -e "Catkin packages in source repo: $SOURCE_PKGS_"
for var in $SOURCE_PKGS_
do
    echo " - The length of argument '$var' is: ${#var}"
done
hoge a b c $SOURCE_PKGS_
fuga a b c $SOURCE_PKGS_
hoga a b c $SOURCE_PKGS_
SOURCE_PKGS=$(catkin_topological_order "$CI_SOURCE_PATH" --only-names)
echo -e "Catkin packages in source repo: $SOURCE_PKGS"
for var in $SOURCE_PKGS
do
    echo " - The length of argument '$var' is: ${#var}"
done
hoge a b c $SOURCE_PKGS
fuga a b c $SOURCE_PKGS
hoga a b c $SOURCE_PKGS

echo "--------------"
TEST_PKGS=$(catkin_topological_order "$CI_SOURCE_PATH" --only-names | grep -Fvxf <(echo "$TEST_BLACKLIST" | tr ' ;,' '\n') | tr '\n' ' ')
for var in $TEST_PKGS
do
    echo "The length of argument '$var' is: ${#var}"
done
if [ -n "$TEST_PKGS" ]; then
    TEST_PKGS="--no-deps $TEST_PKGS";
for var in $TEST_PKGS
do
    echo "The length of argument '$var' is: ${#var}"
done
    IFS=' ' read -r -a TEST_PKGS <<< "$TEST_PKGS"
fi
echo -e "Test packages: ${TEST_PKGS}"

# Re-build workspace with tests
travis_run catkin build --no-status --summarize --make-args tests -- ${TEST_PKGS[@]}

# Run tests
travis_run catkin build --catkin-make-args run_tests -- --no-status --summarize ${TEST_PKGS[@]}

# Show test results and throw error if necessary
travis_run catkin_test_results

echo "Travis script has finished successfully"
HIT_ENDOFSCRIPT=true
exit 0
