#!/bin/bash -e

set +H

GIT_VERSION_MINIMAL='2.24.0'
CONDA_VERSION_MINIMAL='4.7.12'

if [[ -z "$ENV_INIT_BRANCH" ]]; then ENV_INIT_BRANCH="master"; fi

# inspired by https://stackoverflow.com/a/4025065
check_versions () {
    if [[ $1 == $2 ]]
    then
        VERSION_OK=1
        return
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            VERSION_OK=1
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            VERSION_OK=0
            return
        fi
    done
    VERSION_OK=0
    return
}

add_conda_to_path() {
  if hash conda 2>/dev/null; then
    CONDA_EXECUTABLE_PATH="conda"
    echo "Using Conda executable from PATH"

  elif [ -f "$HOME/Miniconda3/Library/bin/conda.bat" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/Miniconda3/Library/bin/conda.bat"
    source $HOME/Miniconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/Anaconda3/Library/bin/conda.bat" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/Anaconda3/Library/bin/conda.bat"
    source $HOME/Anaconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/AppData/Local/Continuum/miniconda3/condabin/conda.bat" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/AppData/Local/Continuum/miniconda3/condabin/conda.bat"
    source $HOME/AppData/Local/Continuum/miniconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/AppData/Local/Continuum/anaconda3/condabin/conda.bat" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/AppData/Local/Continuum/anaconda3/condabin/conda.bat"
    source $HOME/AppData/Local/Continuum/anaconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/miniconda3/bin/conda" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/miniconda3/bin/conda"
    source $HOME/miniconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/anaconda3/bin/conda" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/anaconda3/bin/conda"
    source $HOME/anaconda3/etc/profile.d/conda.sh

  elif [ -f "$HOME/miniconda/bin/conda" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/miniconda/bin/conda"
    source $HOME/miniconda/etc/profile.d/conda.sh

  elif [ -f "$HOME/anaconda/bin/conda" ]; then
    CONDA_EXECUTABLE_PATH="$HOME/anaconda/bin/conda"
    source $HOME/anaconda/etc/profile.d/conda.sh

  else
    echo "Unable to find Conda executable, exiting..."
    exit 1
  fi

  CONDA_VERSION=$("$CONDA_EXECUTABLE_PATH" --version | sed -E 's|^conda ([0-9.]+).*$|\1|g')

  check_versions $CONDA_VERSION $CONDA_VERSION_MINIMAL

  if [[ $VERSION_OK == 1 ]]; then
    echo "Conda version $CONDA_VERSION ok"
  else
    echo "Conda version $CONDA_VERSION is too old, please update to $CONDA_VERSION_MINIMAL or higher"
    exit 1
  fi

  echo "Using Conda executable: $CONDA_EXECUTABLE_PATH"
}

setup_conda() {
  CONDA_ENV_PATH="$CURRENT_DIR/.venv"
  CONDA_BASE_DIR=$(conda info --base | sed 's/\\/\//g')

  echo "Using Conda base dir: $CONDA_BASE_DIR"

  if [ $IS_WINDOWS == 1 ]; then
    PYTHON_BASE_EXECUTABLE_PATH="$CONDA_BASE_DIR/python.exe"
    # c:/foo/bar -> /c/foo/bar
    PYTHON_ENV_EXECUTABLE_DIR=$(sed -E 's|^([a-zA-Z]):|/\1|g' <<< $CONDA_ENV_PATH)
  else
    PYTHON_BASE_EXECUTABLE_PATH="$CONDA_BASE_DIR/bin/python"
    PYTHON_ENV_EXECUTABLE_DIR="$CONDA_ENV_PATH/bin"
  fi

  if [ ! -f "$HOME/.bash_profile" ]; then
    echo "Creating .bash_profile"
    touch "$HOME/.bash_profile"
    echo "test -f ~/.profile && . ~/.profile" >> "$HOME/.bash_profile"
    echo "test -f ~/.bashrc && . ~/.bashrc" >> "$HOME/.bash_profile"
  fi

  if [ ! -f "$HOME/.bashrc" ]; then
    echo "Creating .bashrc"
    touch "$HOME/.bashrc"
  fi

  # conda.sh not yet added to .bashrc
  if ! grep -q "/etc/profile.d/conda.sh" "$HOME/.bashrc"; then
    echo "Adding $CONDA_BASE_DIR/etc/profile.d/conda.sh to .bashrc"
    echo "source $CONDA_BASE_DIR/etc/profile.d/conda.sh" >> ~/.bashrc
  fi

  echo "Creating ~/pyfony_env.sh"
  rm -f "$HOME/pyfony_env.sh"
  touch "$HOME/pyfony_env.sh"
  echo "alias ca='conda activate \$PWD/.venv'" >> ~/pyfony_env.sh

  if ! grep -q "pyfony_env.sh" "$HOME/.bashrc"; then
      echo "source ~/pyfony_env.sh added to ~/.bashrc"
      echo "source ~/pyfony_env.sh" >> ~/.bashrc
  fi
}

detect_os() {
  if [ "$(cut -c 1-10 <<< "$(uname -s)")" == "MINGW64_NT" ]; then
    echo "Detected Windows OS"
    IS_WINDOWS=1
    DETECTED_OS="win"
  else
    echo "Detected Unix-based OS"
    IS_WINDOWS=0

    if [[ "$OSTYPE" == "darwin"* ]]; then
      DETECTED_OS="mac"
    else
      DETECTED_OS="linux"
    fi
  fi
}

check_git_version() {
  GIT_VERSION=$(git --version | sed -E 's|^git version ([0-9.]+)[.].+$|\1|g')

  check_versions $GIT_VERSION $GIT_VERSION_MINIMAL

  if [[ $VERSION_OK == 1 ]]; then
    echo "Git version $GIT_VERSION ok"
  else
    echo "Git version $GIT_VERSION is too old, please update to $GIT_VERSION_MINIMAL or higher"
    exit 1
  fi
}

resolve_current_dir() {
  CURRENT_DIR="$PWD"

  if [ $IS_WINDOWS == 1 ]; then
    # /c/dir/subdir => c:/dir/subdir
    CURRENT_DIR=$(sed -E "s|^/([a-z])/|\1:/|" <<< $CURRENT_DIR)
  fi
}

prepare_environment() {
  if [ "$(cut -c 1-7 <<< "$(uname -s)")" == "MSYS_NT" ]; then
    echo "Wrong sh.exe in use, fix your PATH! Exiting..."
    exit 1
  fi

  detect_os
  check_git_version
  resolve_current_dir

  if [ $DETECTED_OS == "mac" ]; then
    # pygit2 vs. libgit2 versions compatibility matrix: https://www.pygit2.org/install.html#version-numbers
    brew install https://raw.githubusercontent.com/Homebrew/homebrew-core/f4a74cf22ba61749acb773508e287794bb36ef9d/Formula/libgit2.rb # libgit2 0.28.4
  fi

  add_conda_to_path
  setup_conda
}

create_conda_environment() {
  echo "Creating Conda environment to $CONDA_ENV_PATH"
  conda env create -f environment.yml -p "$CONDA_ENV_PATH"
}

install_poetry() {
  echo "Installing Poetry globally"
  curl -sSL https://raw.githubusercontent.com/sdispater/poetry/master/get-poetry.py --silent -o "$CONDA_ENV_PATH/get-poetry.py"
  $PYTHON_BASE_EXECUTABLE_PATH "$CONDA_ENV_PATH/get-poetry.py" -y --version 1.0.0

  if [ $IS_WINDOWS == 1 ]; then
    # $HOME/.poetry/env does not exist on Windows
    export PATH="$HOME/.poetry/bin:$PATH"
  else
    source $HOME/.poetry/env
  fi
}

install_dependencies() {
  local POETRY_PATH

  if [ $IS_WINDOWS == 1 ]; then
    POETRY_PATH=$(PATH="$PYTHON_ENV_EXECUTABLE_DIR:$PATH" where poetry | sed -n '1!p')
  else
    POETRY_PATH=$(PATH="$PYTHON_ENV_EXECUTABLE_DIR:$PATH" which poetry | sed -n '2!p')
  fi

  echo "Using Poetry from: $POETRY_PATH"

  echo "Installing dependencies from poetry.lock"
  PATH="$PYTHON_ENV_EXECUTABLE_DIR:$PATH" poetry install --no-root
}

create_git_hooks() {
  if [ ! -d "$CURRENT_DIR/.git" ]; then
    echo "Skipping git hooks creation"
    return
  fi

  local POST_MERGE_HOOK_PATH="$CURRENT_DIR/.git/hooks/post-merge"

  echo "Hooks path $POST_MERGE_HOOK_PATH"

  if [ ! -f "$POST_MERGE_HOOK_PATH" ]; then
    echo "Creating empty post-merge git hook"
    echo -e "#!/bin/sh\n\n" > "$POST_MERGE_HOOK_PATH"
  fi

  if ! grep -q "poetry install --no-root" "$POST_MERGE_HOOK_PATH"; then
    echo "Adding poetry install to post-merge git hook"
    echo "poetry install --no-root" >> "$POST_MERGE_HOOK_PATH"
  fi
}

set_conda_scripts() {
  echo "Setting up Conda activation & deactivation scripts"

  echo "Seting-up conda/activate.d"
  local CONDA_ACTIVATE_DIR="$CONDA_ENV_PATH/etc/conda/activate.d"
  mkdir -p $CONDA_ACTIVATE_DIR
  curl "https://raw.githubusercontent.com/pyfony/dev-env-init/$ENV_INIT_BRANCH/unix/conda/activate.d/env_vars.sh?$(date +%s)" --silent > "$CONDA_ACTIVATE_DIR/env_vars.sh"
  chmod +x "$CONDA_ACTIVATE_DIR/env_vars.sh"

  echo "Seting-up conda/deactivate.d"
  local CONDA_DEACTIVATE_DIR="$CONDA_ENV_PATH/etc/conda/deactivate.d"
  mkdir -p $CONDA_DEACTIVATE_DIR
  curl "https://raw.githubusercontent.com/pyfony/dev-env-init/$ENV_INIT_BRANCH/unix/conda/deactivate.d/env_vars.sh?$(date +%s)" --silent > "$CONDA_DEACTIVATE_DIR/env_vars.sh"
  chmod +x "$CONDA_DEACTIVATE_DIR/env_vars.sh"
}

create_dot_env_file() {
  DOT_ENV_PATH="$CURRENT_DIR/.env"

  if [ ! -f "$DOT_ENV_PATH" ]; then
    if [ -f "$CURRENT_DIR/.env.dist" ]; then
      echo "Creating .env file from the .env.dist template"
      cp "$CURRENT_DIR/.env.dist" "$CURRENT_DIR/.env"
    else
      echo "Creating empty .env file in the project root"
      echo "APP_ENV=dev" > $DOT_ENV_PATH
    fi
  fi
}

show_installation_finished_info() {
  echo "---------------"

  echo "Setup completed. Active Conda environment now:"
  echo ""
  echo "conda activate $CONDA_ENV_PATH"
  echo ""
}

base_environment_setup() {
  prepare_environment

  if [ ! -d "$CONDA_ENV_PATH" ]; then
    echo "Creating new Conda environment"
    create_conda_environment
  fi

  install_poetry
  install_dependencies
  create_git_hooks
  set_conda_scripts
}

# main invocation functions ---------------------

prepare_environment_for_package() {
  base_environment_setup
  show_installation_finished_info
}
