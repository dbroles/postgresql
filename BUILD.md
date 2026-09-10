# Linux

sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev

flutter config --enable-linux-desktop
flutter doctor

flutter create --platforms=linux .

flutter build linux --release

build/linux/x64/release/bundle/
├── your_app_name          # Native Linux executable
├── lib/                   # libflutter_linux_gtk.so & plugin libraries
└── data/                  # Assets, fonts, and compiled Dart AOT code

Package:
dart pub global activate flutter_distributor

flutter_distributor package --platform linux --targets appimage

