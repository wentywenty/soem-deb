# soem-deb

这个仓库用来把上游 SOEM 作为 git submodule 固定到 v2.0.0，并构建 Debian 开发包 libsoem-dev 2.0.0.1。

## 目录说明

- SOEM/: 上游源码子模块
- debian/: Debian control 和 maintainer scripts
- build_deb.sh: 本地与 CI 共用的唯一打包入口
- output/: 最终生成的 deb 产物目录

## 同步子模块

首次拉取或更新 .gitmodules 后，执行：

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## 本地构建

amd64 原生构建：

```bash
./build_deb.sh
```

arm64 交叉构建：

```bash
ARCH=arm64 CROSS_PREFIX=aarch64-linux-gnu- ./build_deb.sh
```

如果需要让脚本自动安装依赖，可以加：

```bash
INSTALL_DEPS=1 ./build_deb.sh
```

## 产物位置

最终 deb 产物固定输出到：

```bash
output/libsoem-dev_2.0.0.1_${ARCH}.deb
```

例如 amd64 默认构建产物为：

```bash
output/libsoem-dev_2.0.0.1_amd64.deb
```

## GitHub Actions

GitHub Actions 工作流只负责 checkout 仓库，然后调用 build_deb.sh。
依赖安装和打包逻辑全部收敛在脚本内部。

## CMake / pkg-config 使用

这个包会把 SOEM 安装到更适合 Linux 开发包查找的目录：

- 库：`/usr/lib/<triplet>/libsoem.so`
- CMake config：`/usr/lib/<triplet>/cmake/soem/`
- 兼容软链接：`/usr/lib/cmake/soem`
- pkg-config：`/usr/lib/<triplet>/pkgconfig/soem.pc`

其中 CMake 导出文件会在打包阶段重写库路径，使 `find_package(soem CONFIG)` 指向真实的 multiarch 库目录，而不是上游默认的非 Debian 安装布局。

因此项目侧优先建议这样找：

```cmake
find_package(soem CONFIG QUIET)
```

如果目标环境只配了 pkg-config，再回退到：

```cmake
find_package(PkgConfig QUIET)
pkg_check_modules(SOEM QUIET soem)
```
