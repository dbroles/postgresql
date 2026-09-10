# Linux

sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

The `libsecret` library needs to be installed:
sudo apt install libsecret-1-dev

flutter build linux --release

```text
build/linux/x64/release/bundle/
├── user_manager          # Native Linux executable
├── lib/                   # libflutter_linux_gtk.so & plugin libraries
└── data/                  # Assets, fonts, and compiled Dart AOT code
```
Package:
dart pub global activate flutter_distributor

flutter_distributor package --platform linux --targets appimage

