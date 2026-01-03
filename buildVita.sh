#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Vitaki Build Script for PS Vita${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Function to print status messages
print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check if VitaSDK is installed
check_vitasdk() {
    if [ -z "$VITASDK" ]; then
        if [ -d "/usr/local/vitasdk" ]; then
            export VITASDK=/usr/local/vitasdk
            export PATH=$VITASDK/bin:$PATH
            print_status "Found VitaSDK at /usr/local/vitasdk"
        else
            print_error "VitaSDK not found and VITASDK environment variable not set"
            return 1
        fi
    else
        print_status "Using VitaSDK from: $VITASDK"
        export PATH=$VITASDK/bin:$PATH
    fi
    
    # Verify VitaSDK installation
    if ! command -v arm-vita-eabi-gcc &> /dev/null; then
        print_error "VitaSDK toolchain not found in PATH"
        return 1
    fi
    
    print_status "VitaSDK toolchain verified"
    return 0
}

# Install VitaSDK if not present
install_vitasdk() {
    print_status "Installing VitaSDK..."
    
    # Save current directory
    local ORIGINAL_DIR=$(pwd)
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    git clone https://github.com/vitasdk/vdpm.git
    cd vdpm
    
    sudo ./bootstrap-vitasdk.sh
    
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    export VITASDK=/usr/local/vitasdk
    export PATH=$VITASDK/bin:$PATH
    
    print_status "VitaSDK installed successfully"
}

# Install VitaSDK packages using vdpm
install_vita_packages() {
    print_status "Checking VitaSDK packages..."
    
    # Save current directory
    local ORIGINAL_DIR=$(pwd)
    
    # Required packages
    PACKAGES=(
        "openssl"
        "opus"
        "speexdsp"
        "curl"
        "zlib"
        "libpng"
        "libjpeg-turbo"
        "freetype"
        "zstd"
        "bzip2"
        "libzip"
    )
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    if [ ! -d "vdpm" ]; then
        git clone https://github.com/vitasdk/vdpm.git
    fi
    
    cd vdpm
    
    for package in "${PACKAGES[@]}"; do
        print_status "Installing $package..."
        ./vdpm "$package" || print_warning "Package $package may already be installed or failed"
    done
    
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    print_status "VitaSDK packages installation complete"
}

# Install vita2dlib manually
install_vita2d() {
    print_status "Checking vita2d library..."
    
    if [ -f "$VITASDK/arm-vita-eabi/include/vita2d.h" ]; then
        print_status "vita2d already installed"
        return 0
    fi
    
    print_status "Building and installing vita2d..."
    
    # Save current directory
    local ORIGINAL_DIR=$(pwd)
    
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    git clone https://github.com/xerpi/vita2dlib.git
    cd vita2dlib/libvita2d
    
    make -j$(nproc)
    sudo make install
    
    cd "$ORIGINAL_DIR"
    rm -rf "$TEMP_DIR"
    
    print_status "vita2d installed successfully"
}

# Check and install system dependencies
install_system_deps() {
    print_status "Checking system dependencies..."
    
    # Check if protobuf-compiler is installed
    if ! command -v protoc &> /dev/null; then
        print_status "Installing protobuf-compiler..."
        sudo apt-get update
        sudo apt-get install -y protobuf-compiler
    else
        print_status "protobuf-compiler already installed"
    fi
    
    # Check Python protobuf module
    if ! python3 -c "import google.protobuf" 2>/dev/null; then
        print_status "Installing Python protobuf module..."
        python3 -m pip install 'protobuf<4'
    else
        # Check version
        PB_VERSION=$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || echo "unknown")
        if [[ "$PB_VERSION" == 4.* ]] || [[ "$PB_VERSION" == 5.* ]] || [[ "$PB_VERSION" == 6.* ]]; then
            print_warning "protobuf version $PB_VERSION is too new, downgrading..."
            python3 -m pip install 'protobuf<4'
        else
            print_status "Python protobuf (version $PB_VERSION) already installed"
        fi
    fi
}

# Initialize git submodules
init_submodules() {
    print_status "Checking git submodules..."
    
    # Check if critical submodule files exist
    if [ -f "third-party/nanopb/CMakeLists.txt" ] && \
       [ -f "third-party/curl/CMakeLists.txt" ] && \
       [ -f "vita/third_party/tomlc99/toml.c" ]; then
        print_status "Submodules already present"
        return 0
    fi
    
    # Try to initialize submodules if we're in a git repo
    if git rev-parse --git-dir > /dev/null 2>&1; then
        print_status "Initializing git submodules..."
        git submodule update --init --recursive
        print_status "Submodules initialized"
    else
        print_warning "Not a git repository, cannot initialize submodules automatically"
        print_error "Required submodules are missing!"
        print_error "Please clone the repository with: git clone --recursive <repository-url>"
        print_error "Or initialize submodules manually: git submodule update --init --recursive"
        exit 1
    fi
}

# Build the project
build_project() {
    print_status "Configuring CMake..."
    
    # Remove old build directory if requested
    if [ "$CLEAN_BUILD" = "1" ]; then
        print_status "Cleaning old build directory..."
        rm -rf build
    fi
    
    cmake -B "./build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="${VITASDK}/share/vita.toolchain.cmake" \
        -DCHIAKI_ENABLE_VITA=ON \
        -DCHIAKI_ENABLE_TESTS=OFF \
        -DCHIAKI_ENABLE_CLI=OFF \
        -DCHIAKI_ENABLE_GUI=OFF \
        -DCHIAKI_ENABLE_ANDROID=OFF \
        -DCHIAKI_ENABLE_SETSU=OFF \
        -DCHIAKI_FFMPEG_DEFAULT=OFF \
        -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
        -DCHIAKI_ENABLE_PI_DECODER=OFF \
        -DCHIAKI_USE_SYSTEM_NANOPB=OFF \
        -DCHIAKI_LIB_ENABLE_OPUS=ON
    
    print_status "Building project..."
    make -j$(nproc) -C "./build"
    
    print_status "Build complete!"
}

# Main script
main() {
    # Parse arguments
    CLEAN_BUILD=0
    SKIP_DEPS=0
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_BUILD=1
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=1
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --clean      Clean build directory before building"
                echo "  --skip-deps  Skip dependency installation"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Change to script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    cd "$SCRIPT_DIR"
    
    if [ "$SKIP_DEPS" = "0" ]; then
        # Check and install VitaSDK
        if ! check_vitasdk; then
            print_status "VitaSDK not found, installing..."
            install_vitasdk
        fi
        
        # Install system dependencies
        install_system_deps
        
        # Install VitaSDK packages
        install_vita_packages
        
        # Install vita2d
        install_vita2d
        
        # Initialize submodules
        init_submodules
    else
        print_warning "Skipping dependency checks (--skip-deps)"
        if ! check_vitasdk; then
            print_error "VitaSDK not found and --skip-deps was specified"
            exit 1
        fi
    fi
    
    # Build the project
    build_project
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Build successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    print_status "VPK file location: $(realpath build/vita/Vitaki.vpk)"
    echo
    print_status "You can now transfer this file to your PS Vita and install it with VitaShell"
}

# Run main function
main "$@"
