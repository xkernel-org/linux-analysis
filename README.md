```shell
# FIXME change to GitHub link once publicized
# 12 min on c6420
wget 'https://mir.cs.illinois.edu/~wentaoz5/ss-public/scripts/setup-standalone.sh' -O- | bash
```

As prompted, log out the current shell and log back in again.

Build Linux kernel first for deployment with GNU toolchain, then for
whole-program analysis with [wllvm](https://github.com/travitch/whole-program-llvm).

```shell
# 1 hour on c6420
bash $WORKDIR/linux-analysis/scripts/build-with-gcc-outer.sh
# 2 hour 36 min on c6420
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
