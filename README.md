**Targeting Linux 6.8.** Both modes assume the host is running a 6.8.x kernel
with `/boot/config-$(uname -r)` available.

There are two ways to set up the analysis tree:

* **Integrated with Xkernel** (the kernel is already built by Xkernel's
  `scripts/install_deps.sh` at `~/linux-6.8.0`):

  ```shell
  bash scripts/setup.sh
  ```

* **Standalone** (no Xkernel checkout; mirrors Xkernel's GCC kernel-build
  steps to produce `~/linux-6.8.0` itself):

  ```shell
  bash scripts/setup-standalone.sh
  ```

As prompted, log out of the current shell and log back in again.

Both modes stage `$LINUX_WLLVM = $WORKDIR/linux-6.8.0-wllvm` as a copy of
`$LINUX_GCC = ~/linux-6.8.0`. Build the wllvm bitcode for analysis:

```shell
bash $WORKDIR/linux-analysis/scripts/build-with-wllvm.sh
```

Run individual SS analysis:

```shell
bash $WORKDIR/linux-analysis/scripts/ss-analysis.sh \
    $WORKDIR/linux-analysis/dataset/AIO_PLUG_THRESHOLD/1.input.txt
```

Run SS analysis for the whole [dataset](./dataset):

```shell
python $WORKDIR/linux-analysis/scripts/ss-analysis-parallel.py
```
