# Gerrit补丁管理工具

## 🎯 核心文件（3个）

- **`apply_patches_flexible.sh`** - 批量打补丁的主脚本
- **`clean_patches.sh`** - 清理和重置仓库的脚本  
- **`patch_config_flexible.conf`** - 补丁配置文件

## ⚡ 快速上手

### 首次配置

```bash
# 1. 编辑配置文件
vim patch_config_flexible.conf
# 修改: GERRIT_USER="你的用户名"

# 2. 测试连接
./apply_patches_flexible.sh --dry-run
```

### 应用补丁

```bash
./apply_patches_flexible.sh        # 全部应用
./apply_patches_flexible.sh --repo io     # 只处理io仓库
```

### 回到原始状态

```bash
./clean_patches.sh --dry-run       # 预览清理
./clean_patches.sh --force         # 强制清理所有仓库
```

## 🔧 详细使用说明

### 打补丁脚本选项

```bash
# 查看帮助
./apply_patches_flexible.sh --help

# 预览模式（不实际执行）
./apply_patches_flexible.sh --dry-run

# 使用默认配置打补丁
./apply_patches_flexible.sh

# 指定用户名
./apply_patches_flexible.sh --user your_username

# 不创建新分支，在当前分支打补丁
./apply_patches_flexible.sh --no-branch

# 处理特定仓库
./apply_patches_flexible.sh --repo io

# 自定义分支名称
./apply_patches_flexible.sh --branch my_test_branch
```

### 清理脚本选项

```bash
# 查看帮助
./clean_patches.sh --help

# 预览清理操作（推荐先执行）
./clean_patches.sh --dry-run

# 强制清理所有仓库（重置到干净的master状态）
./clean_patches.sh --force

# 只清理特定仓库
./clean_patches.sh --repo io
```

## 🔧 配置文件说明

### 修改用户名

```bash
# 在 patch_config_flexible.conf 中
GERRIT_USER="runyuwei"  # 改成你的用户名
```

### 添加/修改补丁

```bash
# 在 PATCH_CONFIGS 关联数组中
declare -A PATCH_CONFIGS=(
    # 格式: ["目录"]="gerrit仓库名:补丁ID列表"
    ["common"]="hkr-common:850035"
    ["io"]="soc-io-drivers:850447 851971"
    ["apps"]="hkr-apps:850718 852504"
    
    # 添加新补丁
    ["新目录"]="gerrit仓库名:新补丁ID"
    
    # 修改现有补丁（添加新补丁ID）
    ["io"]="soc-io-drivers:850447 851971 新补丁ID"
)

# 调整处理顺序
REPO_ORDER=("common" "io" "apps" "framework/device-mgr" "components/ipu/drivers" "components/ipu/mw" "components/ipu/gdf")
```

### 分支命名策略

```bash
# 选项1: 基于日期 (默认)
BRANCH_NAME="patches_$(date +%m%d)"  # 例如: patches_0916

# 选项2: 固定名称
BRANCH_NAME="my_feature_branch"

# 选项3: 不创建分支，在当前分支应用
CREATE_BRANCH=false
```

## 🗂️ 工作流程

1. **修改配置** - 编辑 `patch_config_flexible.conf` 添加需要的补丁
2. **预览操作** - 运行 `./apply_patches_flexible.sh --dry-run` 查看会做什么
3. **应用补丁** - 运行 `./apply_patches_flexible.sh` 应用补丁
4. **清理重置** - 需要重置时运行 `./clean_patches.sh --force`

## 🗑️ 完全清理回到原始状态

clean脚本会执行以下操作：

- 中止所有进行中的git操作（rebase、merge、cherry-pick等）
- 丢弃所有未提交的修改
- 切换到master分支
- 删除所有非master分支
- 重置master到远程状态
- 拉取最新代码

```bash
# 推荐工作流
./clean_patches.sh --dry-run    # 先预览
./clean_patches.sh --force      # 确认后执行
```

## 📋 常见问题

### Q: 如何查看当前配置的补丁？

```bash
./apply_patches_flexible.sh --dry-run
```

### Q: 如何只应用部分补丁？

```bash
# 方法1: 只处理特定仓库
./apply_patches_flexible.sh --repo io

# 方法2: 编辑配置文件，注释或删除不需要的补丁
vim patch_config_flexible.conf
```

### Q: 出错了怎么办？

```bash
# 查看日志文件
ls -la patch_apply_*.log
cat patch_apply_*.log

# 清理重新开始
./clean_patches.sh --force
```

### Q: 怎么完全回到master原始状态？

```bash
./clean_patches.sh --force  # 彻底清理，回到干净的master状态
```

### Q: 如何验证仓库状态？

清理后可以检查仓库状态：

```bash
# 检查分支
git branch

# 检查未提交改动
git status

# 检查当前分支
git rev-parse --abbrev-ref HEAD
```

## ⚠️ 注意事项

- **clean脚本会完全重置仓库到干净的master状态**
- **所有未提交的修改都会丢失**
- **非master分支都会被删除**
- **建议先用 `--dry-run` 预览操作**
- **重要工作请先备份或提交**

## 📂 文件结构

```
工作目录/
├── apply_patches_flexible.sh     # 主工具：应用补丁
├── clean_patches.sh              # 清理工具：重置仓库
├── patch_config_flexible.conf    # 配置文件：补丁列表
├── README_PATCHES.md             # 本使用指南
└── patch_apply_*.log             # 执行日志
    repo_clean_*.log              # 清理日志
```

**总结**: 日常使用只需要关注前3个核心文件！
