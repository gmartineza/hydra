# Dependencies and Prerequisites

This document lists all required software and configuration needed to run the distributed database system.

## Required Dependencies

### 1. Docker Desktop for Windows

**What it is:** Containerization platform that allows running the MySQL and ProxySQL containers.

**Installation:**
- Download from: https://www.docker.com/products/docker-desktop/
- Install the Windows version (Docker Desktop for Windows)
- Requires Windows 10/11 64-bit with WSL 2 feature

**Configuration/Tweaks:**
- **Enable WSL 2 backend** (recommended):
  - Docker Desktop will prompt you during installation
  - If not enabled, go to Docker Desktop Settings → General → Use WSL 2 based engine
  - Requires WSL 2 to be installed (see below)

- **Resource allocation** (recommended for better performance):
  - Docker Desktop Settings → Resources
  - Allocate at least:
    - **CPUs:** 2-4 cores (minimum 2)
    - **Memory:** 4GB minimum (8GB recommended)
    - **Disk:** 20GB minimum free space

- **Start Docker Desktop** before running `docker-compose` commands

**Verification:**
```powershell
docker --version
docker-compose --version
```

Both commands should return version numbers without errors.

---

### 2. WSL 2 (Windows Subsystem for Linux)

**What it is:** Required by Docker Desktop for Windows (if using WSL 2 backend).

**Installation:**
- Open PowerShell as Administrator
- Run:
```powershell
wsl --install
```
- Restart your computer when prompted
- After restart, WSL will complete installation automatically

**Alternative (if above doesn't work):**
```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Then download and install the WSL 2 Linux kernel update package from Microsoft.

**Configuration/Tweaks:**
- No special configuration needed
- Docker Desktop will automatically use WSL 2

**Verification:**
```powershell
wsl --list --verbose
```

Should show your installed Linux distribution with version 2.

---

### 3. MySQL Client (Optional but Recommended)

**What it is:** Command-line tool to connect to and test the database.

**Installation Options:**

**Option A - MySQL Installer (Full MySQL Server):**
- Download from: https://dev.mysql.com/downloads/installer/
- Choose "MySQL Installer for Windows"
- During installation, select "MySQL Command Line Client" or "MySQL Shell"
- Adds `mysql` command to PATH

**Option B - MySQL Shell Only (Lighter):**
- Download MySQL Shell from: https://dev.mysql.com/downloads/shell/
- Extract and add to PATH, or use full path

**Option C - Use Docker MySQL Client (No Installation):**
- You can use the MySQL client from within a container:
```powershell
docker run -it --rm mysql:8.0 mysql -h host.docker.internal -P 6033 -u root -prootpassword demo_db
```

**Configuration/Tweaks:**
- If installed, ensure MySQL bin directory is in your system PATH
- No additional configuration needed

**Verification:**
```powershell
mysql --version
```

---

### 4. Git Bash or WSL Terminal (For Bash Scripts)

**What it is:** Needed to run the `.sh` setup and test scripts.

**Option A - Git Bash (Recommended for Windows):**
- Comes with Git for Windows
- Download from: https://git-scm.com/download/win
- During installation, ensure "Git Bash Here" option is selected
- No special configuration needed

**Option B - WSL Terminal:**
- If you installed WSL 2, you can use the WSL terminal
- Open from Start Menu → Ubuntu (or your Linux distro)
- No special configuration needed

**Option C - PowerShell (Manual Commands):**
- You can skip bash scripts entirely and run commands manually
- All commands are documented in README.md

**Configuration/Tweaks:**
- For Git Bash: No configuration needed
- For WSL: May need to install Docker inside WSL if using WSL terminal directly (not recommended - use Docker Desktop instead)

**Verification (Git Bash):**
```bash
bash --version
```

---

## Optional Dependencies

### 5. Docker Compose (Usually Included)

**What it is:** Tool for defining and running multi-container Docker applications.

**Status:** Usually included with Docker Desktop for Windows automatically.

**If Not Included:**
- Install separately: https://docs.docker.com/compose/install/
- Or use `docker compose` (without hyphen) - newer Docker versions include it as a plugin

**Verification:**
```powershell
docker-compose --version
# OR
docker compose version
```

---

### 6. Text Editor (For Viewing/Editing Files)

**Recommended:**
- VS Code: https://code.visualstudio.com/
- Notepad++: https://notepad-plus-plus.org/
- Any text editor that supports Unix line endings (LF) for `.sh` files

**Configuration/Tweaks:**
- If editing `.sh` files, ensure line endings are LF (Unix), not CRLF (Windows)
- Git Bash handles this automatically
- VS Code can be configured to use LF line endings

---

## System Requirements

### Minimum System Requirements:
- **OS:** Windows 10 64-bit (version 1903 or later) or Windows 11
- **RAM:** 8GB (4GB minimum, but 8GB recommended)
- **CPU:** 64-bit processor with virtualization support
- **Disk Space:** 20GB free space
- **Virtualization:** Enabled in BIOS (required for Docker)

### Recommended System Requirements:
- **RAM:** 16GB
- **CPU:** 4+ cores
- **Disk Space:** 50GB free (SSD recommended)

---

## Installation Checklist

Before starting the project, verify you have:

- [ ] Docker Desktop installed and running
- [ ] WSL 2 installed and configured
- [ ] Docker Desktop configured to use WSL 2 backend
- [ ] Docker Desktop allocated sufficient resources (4GB+ RAM, 2+ CPUs)
- [ ] MySQL client installed (or plan to use Docker MySQL client)
- [ ] Git Bash or WSL terminal available (or plan to use PowerShell manually)
- [ ] Virtualization enabled in BIOS (if Docker fails to start)

---

## Common Issues and Solutions

### Issue: Docker Desktop won't start
**Solution:**
- Ensure virtualization is enabled in BIOS
- Check Windows Features: Enable "Virtual Machine Platform" and "Windows Subsystem for Linux"
- Restart computer after enabling features

### Issue: "WSL 2 installation is incomplete"
**Solution:**
- Run: `wsl --update` in PowerShell as Administrator
- Restart computer
- Verify with: `wsl --status`

### Issue: Docker containers can't connect to each other
**Solution:**
- Ensure all containers are on the same Docker network (handled by docker-compose.yml)
- Check Docker Desktop is running
- Verify firewall isn't blocking Docker

### Issue: MySQL client not found
**Solution:**
- Use Docker MySQL client instead (see Option C above)
- Or add MySQL bin directory to system PATH
- Or use full path to mysql.exe

### Issue: Bash scripts won't run
**Solution:**
- Use Git Bash instead of PowerShell
- Or run commands manually from README.md
- Or convert scripts to PowerShell (.ps1)

---

## Quick Verification Commands

Run these commands to verify everything is set up correctly:

```powershell
# Check Docker
docker --version
docker-compose --version

# Check WSL
wsl --list --verbose

# Check MySQL (if installed)
mysql --version

# Check Git Bash (if installed)
bash --version
```

All commands should return version information without errors.

---

## Next Steps

Once all dependencies are installed and verified:

1. Navigate to the project directory
2. Start the cluster: `docker-compose up -d`
3. Follow the setup instructions in README.md

Good luck with your evaluation! 🚀

