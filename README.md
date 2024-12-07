# Sys-Config

**Sys-Config** is a simple tool designed to automate the installation of packages on popular Linux distributions using a JSON configuration file. It adapts to the system's package manager and configuration requirements, making setup easier and more consistent across distributions.

---

## Features

- Supports Debian-based, Fedora-based, and Arch-based Linux distributions.
- Reads a JSON configuration file to determine the packages to install.
- Automatically detects and uses the appropriate package manager (`apt`, `dnf`, `pacman`).
- Checks if the user is running as `root` and adapts by skipping `sudo` if already root.
- Installs `jq` automatically if not already present.
- Displays a detailed list of installed packages after the script completes.

---

## Requirements

- Linux-based system with one of the following package managers:
  - `apt` (Debian/Ubuntu)
  - `dnf` (Fedora)
  - `pacman` (Arch)
- Either `wget` or `curl` installed to fetch the script or configuration file.

---

## Installation

Clone the repository locally:
```bash
git clone https://github.com/animegamer4422/Sys-Config.git
cd Sys-Config
```

---

## Usage

The script reads a JSON configuration file to determine the packages to install. You can provide the configuration file in several ways, including interactively, via the `--config` flag, or through remote execution with `curl` or `wget`.

---

### 1. Interactive Mode

Run the script without arguments, and it will prompt you for the configuration file:
```bash
bash sysconfig.sh
```
Example prompt:
```text
No config file provided.
Please enter the path or URL to the config file:
```

---

### 2. Using the `--config` Flag

You can directly specify the configuration file using the `--config` flag.

#### Local File
```bash
bash sysconfig.sh --config ./Sample-Config.json
```

#### Remote File
```bash
bash sysconfig.sh --config https://raw.githubusercontent.com/animegamer4422/Sys-Config/main/Sample-Config.json
```

#### Remote Execution with `curl`
Run the script remotely and specify the config file:
```bash
curl -fSsl https://raw.githubusercontent.com/animegamer4422/Sys-Config/main/sysconfig.sh | bash -s -- --config https://raw.githubusercontent.com/animegamer4422/Sys-Config/main/Sample-Config.json
```

#### Remote Execution with `wget`
Run the script remotely and specify the config file:
```bash
wget -qO- https://raw.githubusercontent.com/animegamer4422/Sys-Config/main/sysconfig.sh | bash -s -- --config https://raw.githubusercontent.com/animegamer4422/Sys-Config/main/Sample-Config.json
```

---

## Configuration File

The script uses a JSON file to determine which packages to install based on the system's distribution. You can specify the configuration file as a local path or a remote URL.

### Sample Configuration File
You can find the sample configuration file in the repository:  
[Sample-Config.json](./Sample-Config.json)

Below is an example of how the configuration file is structured:

```json
{
    "fedora": {
        "server": ["htop", "curl", "nano"],
        "laptop": ["vlc", "curl", "nano"]
    },
    "debian": {
        "server": ["htop", "curl", "nano"],
        "laptop": ["vlc", "curl", "nano"]
    },
    "arch": {
        "server": ["htop", "curl", "nano"],
        "laptop": ["vlc", "curl", "nano"]
    }
}
```
---

## Example Output

### Installed Packages:
After successful execution, the script lists the packages that were installed:
```text
The following packages were installed:
- curl
- vim
- htop
```

---

## Contributing

Contributions are welcome! If you'd like to contribute:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-name`).
3. Commit your changes (`git commit -m "Feature description"`).
4. Push to your fork (`git push origin feature-name`).
5. Submit a pull request.
