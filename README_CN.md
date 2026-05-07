# soem-deb

这个仓库用来把上游 SOEM 作为 git submodule 固定到 v2.0.0，并构建 Debian 开发包 libsoem-dev。

## 目录说明

- `SOEM/`: 上游源码子模块
- `debian/`: Debian 打包配置文件 (control、rules 等)

## 同步子模块

首次拉取或更新 .gitmodules 后，执行：

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

## 本地构建

在安装好相关的构建依赖后，直接执行原生 Debian 打包命令：

```bash
dpkg-buildpackage -us -uc -b
```

## 产物位置

最终 deb 产物会默认输出到上级目录（与 `soem-deb` 平级）：

```bash
../libsoem-dev_<version>_<arch>.deb
```

## GitHub Actions

GitHub Actions 工作流现已原生支持并调用 `dpkg-buildpackage`，自动完成相关多架构的构建和打包工作，打包逻辑全部标准化收敛于 `debian/` 文件夹内部。

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
