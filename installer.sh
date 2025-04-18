#!/usr/bin/env bash

# Read variables from params.sh
# shellcheck source=/dev/null
if [[ -f ./params.sh ]]
then
    source ./params.sh
fi

# Set defaults
# Install directory without trailing slash
if [[ -z "${install_dir}" ]]
then
    install_dir="$(pwd)"
fi

# Name of the subdirectory (defaults to stable-diffusion-webui)
if [[ -z "${clone_dir}" ]]
then
    clone_dir="autolumelive_colab"
fi

# python3 executable
if [[ -z "${python_cmd}" ]]
then
    python_cmd="python3.10"
fi

# git executable
if [[ -z "${GIT}" ]]
then
    export GIT="git"
fi

# python3 venv without trailing slash (defaults to ${install_dir}/${clone_dir}/venv)
if [[ -z "${venv_dir}" ]]
then
    venv_dir="venv"
fi

if [[ -z "${LAUNCH_SCRIPT}" ]]
then
    LAUNCH_SCRIPT="main.py"
fi

# this script cannot be run as root by default
can_run_as_root=0

# Disable sentry logging
export ERROR_REPORTING=FALSE

# Do not reinstall existing pip packages on Debian/Ubuntu
export PIP_IGNORE_INSTALLED=0

# Pretty print
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "\e[1m\e[32mInstall script for Autolume-Live\n"
printf "\e[1m\e[34mTested on Endeavour OS \e[0m"
printf "\n%s\n" "${delimiter}"

# Do not run as root
#if [[ $(id -u) -eq 0 && can_run_as_root -eq 0 ]]
#then
 #   printf "\n%s\n" "${delimiter}"
  #  printf "\e[1m\e[31mERROR: This script must not be launched as root, aborting...\e[0m"
   # printf "\n%s\n" "${delimiter}"
   # exit 1
#else
 #   printf "\n%s\n" "${delimiter}"
  #  printf "Running on \e[1m\e[32m%s\e[0m user" "$(whoami)"
   # printf "\n%s\n" "${delimiter}"
#fi

if [[ $(getconf LONG_BIT) = 32 ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: Unsupported Running on a 32bit OS\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

if [[ -d .git ]]
then
    printf "\n%s\n" "${delimiter}"
    printf "Repo already cloned, using it as install directory"
    printf "\n%s\n" "${delimiter}"
    install_dir="${PWD}/../"
    clone_dir="${PWD##*/}"
fi

# Check prerequisites
gpu_info=$(lspci 2>/dev/null | grep VGA)
case "$gpu_info" in
    *"Navi 1"*|*"Navi 2"*) export HSA_OVERRIDE_GFX_VERSION=10.3.0
    ;;
    *"Renoir"*) export HSA_OVERRIDE_GFX_VERSION=9.0.0
        printf "\n%s\n" "${delimiter}"
        printf "Experimental support for Renoir: make sure to have at least 4GB of VRAM and 10GB of RAM or enable cpu mode: --use-cpu all --no-half"
        printf "\n%s\n" "${delimiter}"
    ;;
    *)
    ;;
esac
if echo "$gpu_info" | grep -q "AMD" && [[ -z "${TORCH_COMMAND}" ]]
then
    export TORCH_COMMAND="pip install torch==2.0.1+rocm5.4.2 torchvision==0.15.2+rocm5.4.2 --index-url https://download.pytorch.org/whl/rocm5.4.2"
fi

for preq in "${GIT}" "${python_cmd}"
do
    if ! hash "${preq}" &>/dev/null
    then
        printf "\n%s\n" "${delimiter}"
        printf "\e[1m\e[31mERROR: %s is not installed, aborting...\e[0m" "${preq}"
        printf "\n%s\n" "${delimiter}"
        exit 1
    fi
done

if ! "${python_cmd}" -c "import venv" &>/dev/null
then
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: python3-venv is not installed, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi

cd "${install_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/, aborting...\e[0m" "${install_dir}"; exit 1; }
if [[ -d "${clone_dir}" ]]
then
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
else
    printf "\n%s\n" "${delimiter}"
    printf "Clone stable-diffusion-webui"
    printf "\n%s\n" "${delimiter}"
    "${GIT}" clone https://github.com/Metacreation-Lab/autolume.git "${clone_dir}"
    cd "${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
fi

if [[ -z "${VIRTUAL_ENV}" ]];
then
    printf "\n%s\n" "${delimiter}"
    printf "Create and activate python venv"
    printf "\n%s\n" "${delimiter}"
    cd "${install_dir}"/"${clone_dir}"/ || { printf "\e[1m\e[31mERROR: Can't cd to %s/%s/, aborting...\e[0m" "${install_dir}" "${clone_dir}"; exit 1; }
    if [[ ! -d "${venv_dir}" ]]
    then
        "${python_cmd}" -m venv "${venv_dir}"
        first_launch=1
    fi
    # shellcheck source=/dev/null
    if [[ -f "${venv_dir}"/bin/activate ]]
    then
        source "${venv_dir}"/bin/activate
    else
        printf "\n%s\n" "${delimiter}"
        printf "\e[1m\e[31mERROR: Cannot activate python venv, aborting...\e[0m"
        printf "\n%s\n" "${delimiter}"
        exit 1
    fi
else
    printf "\n%s\n" "${delimiter}"
    printf "python venv already activated: ${VIRTUAL_ENV}"
    printf "\n%s\n" "${delimiter}"
fi

# Try using TCMalloc on Linux
prepare_tcmalloc() {
    if [[ "${OSTYPE}" == "linux"* ]] && [[ -z "${NO_TCMALLOC}" ]] && [[ -z "${LD_PRELOAD}" ]]; then
        TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
        if [[ ! -z "${TCMALLOC}" ]]; then
            echo "Using TCMalloc: ${TCMALLOC}"
            export LD_PRELOAD="${TCMALLOC}"
        else
            printf "\e[1m\e[31mCannot locate TCMalloc (improves CPU memory usage)\e[0m\n"
        fi
    fi
}

# Install python dependencies from requirements.txt

printf "\n%s\n" "${delimiter}"
printf "Install python dependencies"
printf "\n%s\n" "${delimiter}"
if [[ -f requirements.txt ]]
then
    "${python_cmd}" -m pip install numpy
    "${python_cmd}" -m pip install torch torchvision torchaudio
    "${python_cmd}" -m pip install -r requirements.txt
else
    printf "\n%s\n" "${delimiter}"
    printf "\e[1m\e[31mERROR: Cannot find requirements.txt, aborting...\e[0m"
    printf "\n%s\n" "${delimiter}"
    exit 1
fi


printf "\n%s\n" "${delimiter}"
    printf "Launching Autolume-Live..."
    printf "\n%s\n" "${delimiter}"
    prepare_tcmalloc
    exec "${python_cmd}" "${LAUNCH_SCRIPT}" "$@"
