## FLANG-RT ##

### WHAT IS FLANG-RT? ###

flang-rt is the runtime library for LLVM Flang (formerly known as flang-new for LLVM versions <= 19.x)
It is not associated with [Classic Flang](https://github.com/flang-compiler/flang)

Please see https://flang.llvm.org/docs/.

### INSTALLATION: ###

Ensure you have finished `build.sh` and have added `${TARGET_DIR}/bin` to the system `PATH`,

then run: `./build_flang_rt.sh`.

By default, installation steps for flang-rt will be printed to the terminal
to run manually, but you can automate the installation process by defining
`ENABLE_FLANG_RT_INSTALL`.

You can verify flang-rt is working by invoking the following command:

    echo -e "program return_zero\nend program return_zero" | \
      xcrun flang-new -xf95 -o/dev/null -v - 2>&1 | \
      grep "flang_rt" 1>/dev/null && echo "Success"

If you see "Success", then everything went well.

### USAGE: ###

You do not need to do anything, flang's doing the job for you.