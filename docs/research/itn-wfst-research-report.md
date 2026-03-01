# 中文 ITN WFST 方案调研报告

*2026-03-01*

---

## 1. 背景

Streaming Paraformer 当前使用 sherpa-onnx 提供的 `itn_zh_number.fst`（25KB）做中文数字 ITN。该 FST 存在严重缺陷（见 `docs/itn-fst-bug-analysis.md`）：无上下文感知、数字组合顺序反转、非数字文本破坏。需要寻找更好的 WFST 方案。

---

## 2. 两个主流中文 WFST ITN 方案

### 2.1 WeTextProcessing（出门问问 + 西北工业大学）

| 属性 | 详情 |
|------|------|
| **仓库** | [wenet-e2e/weTextProcessing](https://github.com/wenet-e2e/weTextProcessing) |
| **Stars** | ~727 |
| **License** | Apache 2.0 |
| **依赖** | Pynini + OpenFst |
| **语言** | Python 82%, C++ 13% |
| **维护方** | WeNet 团队（西北工业大学 + 出门问问）|

**支持的中文 ITN 规则（10 类）：**

| 分类 | 示例 |
|------|------|
| 基数词 | 四百六十五 → 465 |
| 小数 | 六点四二 → 6.42 |
| 分数 | 五分之一 → 1/5 |
| 百分比 | 百分之六点三 → 6.3% |
| 日期 | 二零零二年一月二十八日 → 2002/01/28 |
| 时间 | 五点三十五分三十六秒 → 5:35:36 |
| 货币 | 十三点五美元 → $13.5 |
| 度量衡 | 二十五千克 → 25kg |
| 号码序列 | 幺二三零六 → 12306 |
| 数学 | 七十八比九十六 → 78:96 |

**关键特性：**
- `enable_0_to_9=False`：控制是否转换独立的小数字
- `exclue_one=True`（默认）：**防止 "一" 在度量词前被转换**（如 "一年后" 保持不变）
- Whitelist 机制：保护成语（如 "三心二意" 不被转换）
- Blacklist 机制：去除语气词（呃、啊等）

**FST 文件结构：**
```
itn/
├── zh_itn_tagger.fst      # 阶段1：标注
└── zh_itn_verbalizer.fst   # 阶段2：转写
```

---

### 2.2 FunASR fun_text_processing（阿里达摩院）

| 属性 | 详情 |
|------|------|
| **仓库** | [modelscope/FunASR](https://github.com/modelscope/FunASR) 的 `fun_text_processing/` 子目录 |
| **License** | MIT |
| **依赖** | Pynini + OpenFst |
| **维护方** | 阿里巴巴达摩院 |
| **关系** | 明确参考了 WeTextProcessing 的代码 |

**支持的中文 ITN 规则（12 类）：**

| 分类 | tagger 文件 |
|------|------------|
| 基数词 | cardinal.py |
| 小数 | decimal.py |
| 分数 | fraction.py |
| 日期 | date.py |
| 时间 | time.py |
| 货币 | money.py |
| 度量衡 | measure.py |
| 电话号码 | telephone.py |
| 电子地址 | electronic.py |
| 标点 | punctuation.py |
| 白名单 | whitelist.py |
| 通用词 | word.py |

**关键引用：**
> "We referred the codes from WeTextProcessing for Chinese inverse text normalization."

FunASR 的中文 ITN 直接参考了 WeTextProcessing 的实现。

---

## 3. 对比分析

| 维度 | WeTextProcessing | FunASR fun_text_processing |
|------|-----------------|---------------------------|
| **独立性** | 独立包，`pip install WeTextProcessing` | FunASR 子模块，需安装整个 FunASR |
| **中文 ITN 规则数** | 10 类 | 12 类（多 electronic、punctuation） |
| **代码原创性** | 原创 | 参考 WeTextProcessing |
| **C++ Runtime** | 有，CMake 构建 | 无独立 C++ Runtime |
| **FST 导出** | 开箱即用，生成 tagger.fst + verbalizer.fst | 可以生成，但文档较少 |
| **关键参数** | `enable_0_to_9`, `exclue_one` | 参考 WeTextProcessing 的参数 |
| **License** | Apache 2.0 | MIT |
| **包大小** | 独立轻量 | 大（依赖整个 FunASR） |
| **社区维护** | 活跃，专注于文本处理 | 活跃，但 ITN 只是 FunASR 的子功能 |

**结论：WeTextProcessing 更适合 Typeless 项目。** 原因：
1. 独立包，不引入 FunASR 庞大的依赖
2. 是中文 ITN WFST 的原创方案，FunASR 的实现参考了它
3. 有独立的 C++ Runtime
4. `exclue_one` 参数直接解决 "一些→1些" 的问题
5. 导出 FST 文件的流程清晰成熟

---

## 4. sherpa-onnx 兼容性分析

### 4.1 sherpa-onnx 的 rule_fsts 机制

通过分析 sherpa-onnx 源码（`online-recognizer-impl.cc` + `kaldifst::TextNormalizer`）：

```
config.rule_fsts = "fst1.fst,fst2.fst"  // 逗号分隔多个 FST
↓
Split by ","
↓
每个 FST → kaldifst::TextNormalizer(path)
↓
推理时串联应用：text → tn[0].Normalize(text) → tn[1].Normalize(text) → 结果
```

`TextNormalizer` 内部对每个 FST 执行：
1. 将输入文本转为字节级线性 FST acceptor
2. `fst::Compose(input, rule)` — 与规则 FST 做 composition
3. `fst::ShortestPath(composed)` — 取最短路径
4. 提取输出 label 拼成字符串

**关键：byte-level 操作**，输入输出均为 UTF-8 字节序列。

### 4.2 WeTextProcessing FST 兼容性

WeTextProcessing 使用 Pynini（OpenFst 的 Python 封装）生成 FST，同样基于 byte-level 操作。其 tagger+verbalizer 两阶段管线：

```
原始文本 → [zh_itn_tagger.fst] → 带标签的中间表示 → [zh_itn_verbalizer.fst] → 最终文本
```

对应 sherpa-onnx 的 `rule_fsts` 用法：

```swift
config.rule_fsts = "path/to/zh_itn_tagger.fst,path/to/zh_itn_verbalizer.fst"
```

sherpa-onnx 会先用 tagger FST normalize 一次得到中间结果，再用 verbalizer FST normalize 得到最终结果——**与 weTextProcessing 的设计完全一致**。

### 4.3 确认兼容

| 检查项 | 结果 |
|--------|------|
| FST 格式 | OpenFst StdArc (vector/const) ✅ |
| 符号约定 | byte-level (0-255) ✅ |
| 多 FST 串联 | sherpa-onnx 支持逗号分隔 ✅ |
| tagger→verbalizer 管线 | 与串联应用语义一致 ✅ |

---

## 5. 集成方案

### 5.1 下载预构建 FST 文件

WeTextProcessing 在 GitHub Releases 提供预构建的 FST 文件，无需自行生成：

- **下载地址**：`https://github.com/wenet-e2e/WeTextProcessing/releases/download/1.0.4/release-graph-v1.0.4.1.zip`（v1.0.4，2024-08-01）
- **ZIP 内容**：包含 `itn/zh_itn_tagger.fst`（1.19MB）和 `itn/zh_itn_verbalizer.fst`（119KB）

App 启动时自动检测并下载，解压后提取两个 FST 文件到本地模型目录。

### 5.2 代码修改（已完成）

**`Sources/SherpaOnnxManager.swift`**：
- 替换 `itn_zh_number.fst` 配置为 WeTextProcessing ZIP 下载链接
- `getITNFstPath()` 返回逗号拼接的两个文件路径：`"path/zh_itn_tagger.fst,path/zh_itn_verbalizer.fst"`
- `downloadITNFst()` 下载 ZIP → 解压 → 提取两个 FST 文件

**`Sources/RecordingManager.swift`**：
- `loadITNFst()` 无需修改（接口不变，返回的路径格式变化由 SherpaOnnxManager 处理）

**`Sources/SherpaOnnxOnlineRecognizer.swift`**：
- `ruleFstsPath` 接受逗号分隔的多路径格式
- sherpa-onnx 串联执行：text → tagger.fst → verbalizer.fst → 最终结果

---

## 6. 预期效果

| 输入 | itn_zh_number.fst（当前） | WeTextProcessing（目标） |
|------|--------------------------|------------------------|
| 一些 | 1些 ❌ | 一些 ✅ |
| 一个苹果 | 1个苹果 ❌ | 一个苹果 ✅ |
| 一定 | 1定 ❌ | 一定 ✅ |
| 一百二十三 | 321 ❌ | 123 ✅ |
| 二零二六年 | 年6202 ❌ | 2026年 ✅ |
| 三百六十五 | 563 ❌ | 365 ✅ |
| 百分之六点三 | N/A | 6.3% ✅ |
| 五点三十五分 | N/A | 5:35 ✅ |
| 我有三个苹果 | 乱码 ❌ | 我有三个苹果 ✅ |
| 三心二意 | 3心2意 ❌ | 三心二意 ✅（白名单） |

---

## 7. 风险与注意事项

1. **FST 文件大小**：WeTextProcessing 的 tagger（1.19MB）+ verbalizer（119KB）合计约 1.3MB，比旧的 25KB 大，但仍然很小
2. **运行时性能**：WFST composition 是 O(n) 的，对短文本（ASR 输出通常 <100 字）应在毫秒级完成
3. **Version 锁定**：使用 v1.0.4 预构建文件，版本固定
4. **下载源**：从 GitHub Releases 下载，国内网络可能需要代理

---

## 8. 实施步骤（已完成）

1. ~~安装 WeTextProcessing 并生成 FST 文件~~ → 直接使用预构建 FST
2. ~~打包上传到 ModelScope~~ → 直接使用 GitHub Releases 下载链接
3. ✅ 修改 `SherpaOnnxManager.swift`：替换 ITN 配置和下载逻辑
4. ✅ 修改 `SherpaOnnxOnlineRecognizer.swift`：适配逗号分隔的多 FST 路径
5. ✅ 构建验证通过
6. 待验证：端到端测试（启动 app，选择 Streaming Paraformer，验证 ITN 效果）
