# stacher-repack
A script to repack Stacher7 into a Appimage.

> [!WARNING]  
> This was a small project I did because I was bored. I do not plan to maintain this script, the issue thread is for just to mark down potential issues when I do work on this again. 
> Feel free to fork this project as long as you give credit.

## Requirements

1.  The **Stacher `.deb` package**. You can download the latest version from [stacher.io](https://stacher.io/).
2.  **Required command-line tools**. The script will check for these automatically.
    -   On **Fedora**, you can install them with:
        ```shell
        sudo dnf update
        sudo dnf install binutils tar zstd coreutils grep sed curl
        ```

## Usage

1.  Clone this repository or download the `stacher-repack.sh` from [releases](https://github.com/pcbcat/stacher-repack/releases/latest).
2.  Place the latest Stacher `.deb` file (e.g., `stacher7_7.0.00_amd64.deb`) in the same directory.
3.  Make the script executable:
    ```shell
    chmod +x stacher-repack.sh
    ```
4.  Run the script:
    ```shell
    ./stacher-repack.sh
    ```
The script will guide you through the rest of the process. The final `Stacher7-x86_64.AppImage` file will be created in the current directory.

## How It Works

The script follows these main steps:

1.  **Pre-flight Checks**: Verifies all required tools from `dependencies.txt` are installed and finds the input `.deb` file.
2.  **Unpack**: Extracts the contents of the `.deb` archive (`control` and `data` tarballs) into a temporary directory.
3.  **Verify**: Checks that the package architecture (e.g., `amd64`) matches the host machine's architecture.
4.  **Assemble**: Creates a standard `AppDir` structure with the application binaries, icons, and metadata.
5.  **Configure**: Sets up the `AppRun` launcher script and modifies the `.desktop` file for proper execution.
6.  **Build**: Uses `appimagetool` to package the `AppDir` into the final AppImage.
7.  **Cleanup**: Removes all temporary files and build artifacts upon completion or failure.

## Contributing

If you find a bug or have a suggestion, please open an issue.
