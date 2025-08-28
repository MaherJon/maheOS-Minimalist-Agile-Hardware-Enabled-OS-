# maheOS v1.2 Automated Build Tools
A collection of scripts for automatically building maheOS v1.2 on Ubuntu 22.04 environment, based on Linux 6.0.11 kernel and statically compiled busybox, producing a bootable ISO image.
## Project Description
maheOS is a lightweight Linux system. This project provides a complete set of automated build scripts that simplify the entire process from source code compilation to ISO image generation. With two core scripts, build_maheos.sh and clean_maheos.sh, you can easily build and clean up the system.
### Features
1.Automated build process, reducing manual operations  
2.Includes error handling and automatic repair mechanisms  
3.Supports retry functionality after build interruptions  
4.Offers two cleaning modes (full cleanup/partial cleanup)  
5.Based on Linux 6.0.11 kernel and busybox 1.36.1  
6.Generates directly bootable ISO images  
## Requirements
1.**Operating System**: Ubuntu 22.04 LTS  
2.**Permissions**: Requires root privileges (sudo)  
3.**Hardware**: Minimum 2GB RAM recommended, 20GB free disk space  
4.**Network**: Internet connection required to download sources and dependencies  
## Installation and Usage
### Prerequisites  
```bash  
#Clone the repository  
git clone https://github.com/yourusername/maheos-build.git  
cd maheos-build

#Make scripts executable  
chmod +x build_maheos.sh clean_maheos.sh
``` 
### Building the System   
#### Regular build  
```bash
sudo ./build_maheos.sh

#Build with auto-fix disabled
sudo ./build_maheos.sh --no-auto-fix

#Show help information
sudo ./build_maheos.sh --help
```
After successful build, the ISO image will be generated at:
$HOME/maheOS-build/maheOS.iso  
#### Cleaning the Build Environment
```bash
#Run the cleanup script
sudo ./clean_maheos.sh

# Then select cleanup mode:
# 1 - Full cleanup (including source code, requires redownload for rebuild)
# 2 - Partial cleanup (preserves source code, only deletes compilation products)
```
You can also perform a full cleanup through the build script:
```bash
sudo ./build_maheos.sh --clean
```
#### Build Process Explanation  
-**Environment Check**: Verify system dependencies and permissions  
-**Project Structure Creation**: Establish necessary directory structure  
-**Source Download**: Retrieve Linux kernel and busybox sources  
-**Source Extraction**: Uncompress downloaded source packages  
-**Kernel Compilation**: Configure and compile the Linux kernel  
-**Busybox Compilation**: Configure and statically compile busybox  
-**Root Filesystem Configuration**: Create necessary device nodes and initialization scripts  
-**Initramfs Creation**: Generate initial ramdisk filesystem  
-**ISO Image Creation**: Produce bootable ISO image  
## Log Viewing
Detailed logs of the build process are saved to:  
```plaintext  
$HOME/maheOS-build/build.log
```
## Frequently Asked Questions  
1.**Build Failures**: Check the log file for detailed error information. Try cleaning with the `--clean` parameter and rebuilding.  
2.**Missing Dependencies**: The script will attempt to install dependencies automatically. If this fails, please install them manually according to the prompts.  
3.**Network Issues**: Ensure network connectivity is working. Source downloads require access to kernel.org and busybox.net.  
## License  
MIT  
## Contributions  
Issue reports and pull requests are welcome to help improve this build tool.  
## Acknowledgments  
Linux kernel development team  
Busybox project  
GRUB bootloader development team  
