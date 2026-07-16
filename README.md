# PullFilesOffPhone

A small macOS command-line tool that uses `libimobiledevice`

## Dependencies

- macOS and Xcode command-line tools
- [Homebrew](https://brew.sh/)
- `libimobiledevice`
- `libplist`

Install the native libraries with:

```sh
brew install libimobiledevice libplist
```

The Xcode project currently looks for headers and libraries in
`/opt/homebrew`, the default Homebrew prefix on Apple Silicon Macs. If you use
an Intel Mac, update `HEADER_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` in the
project from `/opt/homebrew` to `/usr/local`.

## Run

Connect and unlock your iPhone, tap **Trust** if prompted, then run:

```sh
./run.sh
```

Choose a device by entering the UDID printed by the program.

The `clones/` directory is only for local dependency source checkouts and is
not required to build the project.
