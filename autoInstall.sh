#! /bin/sh

# Functions that will be reused during the script
afterDownloadExistanceCheck()
{
    if [ $1 -eq "0" ]; then
        printf "$2 was installed succesfully \xE2\x9C\x94\n"
    else
        printf "[Error] there was an issue on the installation of the $2, please follow the error/errors carefully !\n"
    fi
}

basicInstallation()
{
    for currentIter in "$@"
    do
        if command -v $currentIter >/dev/null; then
            printf "$currentIter already exists \xE2\x9C\x94\n"
        else
            printf "$currentIter installation is in progress ...\n"
            sudo apt-get -y install $currentIter > /dev/null
            afterDownloadExistanceCheck $? $currentIter
        fi
    done
}

userCreationCheck()
{
    id $1 >/dev/null
    if [ $? -eq "0" ]; then
        printf "User with username: $1 was created succesfully! \xE2\x9C\x94\n"
    else
        printf "User with username: $1 was not created due to an error, please check the issue!\n"
    fi
}

groupCreationCheck()
{
    getent group $1 >/dev/null
    if [ $? -eq "0" ]; then
        printf "Group $1 was succesfully created! \xE2\x9C\x94\n"
    else
        printf "Group $1 was not created, please check the issue!"
    fi
}

isGroupContainingGivenUser()
{
    getent group $1 | grep -wFq $2
    if [ $? -eq "0" ]; then
        printf "User $2 is part of group $1!\n"
    else
        printf "User $2 is not part of group $1!\n"
    fi
}

# Location of the configuration file
configFile="config.json"

# Update and upgrade the packages
echo "Update and upgrade steps are in progress ..."
sudo apt-get update >/dev/null && sudo apt-get -y upgrade >/dev/null
# Upgrade checks
if [ $? -eq "0" ]; then
    printf "update and upgrade were made succesfuly\n"
else
    printf "there were some issues during the last step, please check the output error/errors!\n"
fi

echo "System time setup and hardware time setup in progress ..."

# Set the system time without authentification required (only for root user)
sudo timedatectl set-timezone Europe/Bucharest --no-ask-password

# Set the hardware time to be the same with the system time
sudo timedatectl set-local-rtc 1 --adjust-system-clock

echo "System time and hardware time were set!"

# jq tool installation
basicInstallation "jq"

# AnyDesk Installation section
echo "AnyDesk repository setup in progress ..."
# First add the repository key to trusted software providers list
#sudo curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/anydesk.gpg
sudo wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo apt-key add -

# Add the repository

#sudo echo "deb http://deb.anydesk.com/ all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list
sudo echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk-stable.list
# update packages

sudo apt-get update >/dev/null
# install anydesk
basicInstallation "anydesk"

# Configure AnyDesk (Force login screen to use Xorg)
sed 's/^#WaylandEnable/WaylandEnable/' /etc/gdm3/custom.conf > /etc/gdm3/custom.conf

# Some tools which will be needed for docker + vs code on pop version
basicInstallation "apt-transport-https" "ca-certificates" "curl" "software-properties-common"

# VSCode installation section
echo "VSCode installation is in progress ..."
linuxDistribution=$(cat /etc/*-release | grep -oP "(?<=DISTRIB_ID=).*")
if [ $linuxDistribution == "Ubuntu" ]; then
    sudo snap install code --classic
elif [ $linuxDistribution == "Pop" ]; then
    basicInstallation dirmngr
    curl -fSsL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/vscode.gpg >/dev/null
    echo deb [arch=amd64 signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/vscode stable main | sudo tee /etc/apt/sources.list.d/vscode.list 
    sudo apt-get update >/dev/null
    basicInstallation code
fi

# Double Commander
basicInstallation "doublecmd-common"

# Create needed directories
sudo mkdir /home/Datasets /home/Projects

# pip install
basicInstallation "python3-pip"
pip install --upgrade pip >/dev/null

# virtualenv installation
basicInstallation "python3-virtualenv"

echo "Users creation, group creation and users to groups association steps are in progress ..."
# Users creation
jq -c '.SYS_USERS[]' $configFile | while read currentUser; do
    # Get current user name
    currentUserName=$(echo "$currentUser" | jq -r '.username')
    if ! id "$currentUserName" &>/dev/null; then
        # Add a new user and set its bash + a new home directory
        useradd -s /bin/bash -m $currentUserName
        # Add the current password
        echo $currentUserName:$(echo "$currentUser" | jq -r '.password') | chpasswd
        # Set the password to be expired | to force user to change the generated password on the first login
        passwd --expire $currentUserName
        # Check of the user creation success
        userCreationCheck $currentUserName
    fi
done

# Group creation
groupName=$(jq -r '.GROUP_SETUP.name' $configFile) 
sudo groupadd $groupName
groupCreationCheck $groupName

# Add users to the newly created group
jq -r '.GROUP_SETUP.users[]' $configFile | while read currentUserName; do
    sudo usermod -a -G $groupName $currentUserName
    isGroupContainingGivenUser $groupName $currentUserName
done

# miniconda installation
echo "Miniconda download, installation and setup are in progress ..."

sudo mkdir -p /home/miniconda3
sudo wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /home/miniconda3/miniconda.sh -q --show-progress
bash /home/miniconda3/miniconda.sh -b -u -p /home/miniconda3 >/dev/null
sudo rm -rf /home/miniconda3/miniconda.sh
/home/miniconda3/bin/conda init bash >/dev/null
/home/miniconda3/bin/conda config --set auto_activate_base false

#sed -n '/# >>> conda initialize >>>/,/# <<< conda initialize <<</p' .bashrc
jq -c '.SYS_USERS[]' $configFile | while read currentUser; do
    currentUserSpace=$(echo $currentUser | jq -r '.username');
    sed -n '/# >>> conda initialize >>>/,/# <<< conda initialize <<</p' ~/.bashrc >> $currentUserSpace/.bashrc;
done

# Ensure that conda is on the PATH
export PATH=/home/miniconda3/bin:$PATH
alias execBrc='cd ~ && exec bash && cd /home'
execBrc
# Create the .sh script that will run for each new bash session
sudo echo "export PATH=/home/miniconda3/bin:$PATH" > /etc/profile.d/ievInit.sh

# Add conda-forge channel
conda config --add channels conda-forge

echo "Miniconda setup step is done!"

# git installation
basicInstallation "git"
git config --global user.name $(jq -r '.GIT.username' $configFile)
git config --global user.email $(jq -r '.GIT.email' $configFile)

# docker installation from the official repository
sudo apt-get update >/dev/null
echo "Docker repository setup is in progress ..."

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable" >/dev/null
echo "available docker version: $(apt-cache policy docker-ce | grep "Candidate:" | awk '{print $2}')"
echo "Docker repository setup is done!"
basicInstallation "docker-ce"

# Add privilieges for the newly created group
sudo chgrp -R iev$ /home/miniconda3
sudo chmod -R u=rwx,g=rwx /home/miniconda3

sudo chgrp -R iev$ /home/Datasets
sudo chgrp -R iev$ /home/Projects

sudo chmod -R u=rwx,g=rwx /home/Datasets
sudo chmod -R u=rwx,g=rwx /home/Projects

# samba installation
sudo apt-get update >/dev/null
basicInstallation "samba"
# To Do configure samba

echo "Generic conda environment creation is in progress ..."
# Create a generic environment for all users from the iev group
conda create -y --name=genericEnvironment python=3.9 >/dev/null
if [ $? -eq "0" ]
then
    echo "genericEnvironment conda environment was created succesfully!"
    
    conda run -n genericEnvironment conda install -y -c conda-forge cudatoolkit >/dev/null
    afterDownloadExistanceCheck $? "cudatoolkit"

    conda run -n genericEnvironment pip install nvidia-cudnn-cu11 >/dev/null
    afterDownloadExistanceCheck $? "nvidia-cudnn"

    CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))
    export LD_LIBRARY_PATH=$CUDNN_PATH/lib:$CONDA_PREFIX/lib/:$LD_LIBRARY_PATH

    # Dependencies will be added to the path everytime when this environment will be activated
    mkdir -p $CONDA_PREFIX/etc/conda/activate.d
    echo 'CUDNN_PATH=$(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)"))' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    echo 'export LD_LIBRARY_PATH=$CUDNN_PATH/lib:$CONDA_PREFIX/lib/:$LD_LIBRARY_PATH' >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh

    echo "pip upgrade is in progress ..."
    conda run -n genericEnvironment pip install --upgrade pip >/dev/null

    echo "tensorflow installation is in progress ..."
    conda run -n genericEnvironment pip install tensorflow >/dev/null
    afterDownloadExistanceCheck $? "tensorflow"
else
    echo "genericEnvironment conda environment was not created succesfully, please follow the error output!"
fi
 