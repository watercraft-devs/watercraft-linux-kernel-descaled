# build.sh README

This build script takes the CURRENT kernel on your build system, and "descales" it. It runs several checks to ensure there is no rust toolchain on your build system or needed for the build, so if there is you will need to remove it or go to a system without it (vm or anything) to build this properly.

It also runs (optional but recommended) checks afterwards that absolutely no rust made it into the final build.

Current Linux kernel version as of this commit: 6.12.115


# building

```
chmod +x build.sh
./build.sh
# respond 'y' when prompted in order to proceed
```

# License

GPL 2.0
