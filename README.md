# 机械应力循环谱分析工具

`fatigue-spectrum` 是一个 MoonBit 库和本地命令行工具。从应力记录提取雨流循环，保留幅值、均值、次数及原始位置；输出载荷谱，并根据用户提供的 S–N 曲线计算 Miner 损伤。应力可以来自任何构件或其他分析软件。

## 运行

需要 MoonBit 工具链；native 后端需要本机 C 编译环境。已验证 moon `0.1.20260920 (914d7da)`、moonc `v0.10.14+7d59c7ec9`。运行依赖为 `moonbitlang/async@0.22.4`；计算核心支持 native 和 JS，文件 CLI 使用 native。

在项目目录运行：

```sh
moon update
moon run --target native cmd/main -- analyze samples/stress.csv --sn samples/sn.json --bin-width 10 --json _build/analysis.json --cycles _build/cycles.csv --svg _build/spectrum.svg
```

不提供 `--sn` 时只提取循环与直方图。示例产生 3 条循环记录：范围 20 MPa 的一个完整循环，以及范围 40 MPa 的两个半循环。演示曲线下的损伤为 **1.7×10⁻⁵**。[实际结果](samples/analysis.json)与[未分箱循环](samples/cycles.csv)由 CLI 生成。

![应力范围循环谱](samples/spectrum.svg)

## 输入与计数约定

默认读取名为 `time_s`、`stress_mpa` 的应力列，输入单位为 s、MPa：

```csv
time_s,stress_mpa
0,0
1,30
2,10
3,40
4,0
```

数值必须有限，时间严格递增；接受 UTF-8 BOM、CRLF 和空行。应力可以为负。原始索引从 0 开始，保留 plateau 结束时的位置，不因转折点筛选重新编号。

多列采集文件可直接指定列、单位和分隔符。以下 [instrument-stress.tsv](samples/instrument-stress.tsv) 是 ms／kPa 的合成示例，换算后与 `samples/stress.csv` 相同：

```sh
moon run --target native cmd/main -- analyze samples/instrument-stress.tsv --time-column Clock --stress-column Stress --time-unit ms --stress-unit kPa --delimiter tab --sn samples/sn.json --json _build/imported-analysis.json
```

时间单位支持 `s`、`ms`，应力单位支持 `MPa`、`kPa`、`Pa`；分隔符为 `comma`、`semicolon`、`tab`。单位由参数指定，列名用于定位。每条记录占一行；引号内可包含分隔符，双引号以两个双引号转义。其他列可为空或包含文字，但每行字段数须匹配表头，选定列名须唯一。数值使用小数点，换算溢出或非零值变成零会报错。这些输入选项用于 `analyze` 和 `normalize`；`from-cycles` 继续读取固定单位 MPa 的未分箱循环。

含采集说明行或小数逗号的文件可显式导入。例如 [logger-stress.csv](samples/logger-stress.csv) 是含两行说明、ms 时间和 kPa 应力的合成示例：

```sh
moon run --target native cmd/main -- analyze samples/logger-stress.csv --time-column Clock --stress-column Stress --time-unit ms --stress-unit kPa --delimiter semicolon --skip-rows 2 --decimal-separator comma --sn samples/sn.json --json _build/logger-analysis.json
```

`--skip-rows` 是表头前的物理行数，包含空行，默认 0；错误信息保留原文件行号。`--decimal-separator` 默认为 `dot`，可指定 `comma`；小数逗号配合分号、制表符或带引号字段使用。逗号模式下 `1,25` 解析为 1.25；混用小数点、多个小数逗号和数字分组会报错。仍要求时间严格递增、数值有限。这两个选项同样用于 `analyze` 和 `normalize`。

### 保存可反复使用的标准应力输入

`normalize` 使用相同导入选项，不需要 S–N 曲线，也不提取循环。先确认采集记录，再用标准文件反复分析：

```sh
moon run --target native cmd/main -- normalize samples/logger-stress.csv --time-column Clock --stress-column Stress --time-unit ms --stress-unit kPa --delimiter semicolon --skip-rows 2 --decimal-separator comma --csv _build/normalized-stress.csv --json _build/stress-summary.json
moon run --target native cmd/main -- analyze _build/normalized-stress.csv --sn samples/sn.json --json _build/normalized-analysis.json
```

合成示例得到 5 个样本、时间 0 至 4 s、应力 0 至 40 MPa，标准文件与 `samples/stress.csv` 数值相同。`--csv` 保存 `time_s,stress_mpa`；`--json` 保存 `input_samples`、`time_start_s`、`time_end_s`、`minimum_stress_mpa`、`maximum_stress_mpa`。两项输出均可省略，只打印摘要；指定输出的父目录须已存在。规范化保留全部样本、时间值、顺序及负应力，不平移时间、不滤波，默认不应用标定，只舍去非选定列。再次分析标准文件时使用默认导入参数，避免重复换算单位。

通过规范化表示输入格式与数值有效，不代表采样充分或曲线适用。输入覆盖保护、失败清除旧输出和错误码 2 与分析命令一致。`normalize` 不接受 `--sn`、`--cycles` 等分析选项。

### 显式标定传感器通道

`normalize` 和 `analyze` 接受 `--stress-zero`、`--stress-gain`，默认 0、1：

```text
stress_mpa = (reading - stress_zero) * stress_gain * unit_scale
```

零点使用原读数的单位，增益将每单位原读数换到 `--stress-unit` 声明的应力单位，再换算为 MPa。增益可为负但须有限且非零，零点须有限。例如 [sensor-stress.csv](samples/sensor-stress.csv) 是合成电压通道，零点 2.5 V、灵敏度 -20 MPa/V，换算后与 `samples/stress.csv` 数值相同：

```sh
moon run --target native cmd/main -- normalize samples/sensor-stress.csv --time-column Clock --stress-column Bridge --time-unit ms --stress-unit MPa --delimiter semicolon --skip-rows 1 --decimal-separator comma --stress-zero 2.5 --stress-gain -20 --csv _build/sensor-stress.csv --json _build/sensor-summary.json
moon run --target native cmd/main -- analyze _build/sensor-stress.csv --sn samples/sn.json --json _build/sensor-analysis.json
```

也可将同一组导入参数直接传给 `analyze`。参数始终使用小数点，即使 CSV 使用小数逗号。各换算步骤出现非有限结果或非零值变成零时，会按原文件行号报错。标准 CSV 已完成标定，后续使用默认参数，避免重复应用增益和零点。工具不自动估计零点、去均值或截断负应力；保留标定后的循环均值，仍不进行平均应力修正。`from-cycles` 不接受这两个测量选项。

计数采用三点雨流方法，残余保留为半循环，不自动假定输入首尾周期闭合。两点非恒值输入产生一个半循环；恒值输入不产生零幅循环。应力历史的采样质量由数据提供者负责，计数工具不恢复缺失的载荷峰值。

输出 `range_mpa` 为峰谷差，S–N 使用的应力幅为其一半。直方图使用稀疏的 `(lower, upper]` 范围区间，第一箱包含零；SVG 的横轴列出实际占用的箱上界。分箱仅用于展示，损伤始终基于原始循环。

已有循环记录时，可以直接读取本工具导出的 CSV，换用曲线或分箱宽度重新分析，不必再次计数：

```sh
moon run --target native cmd/main -- from-cycles samples/cycles.csv --sn samples/sn.json --bin-width 20 --json _build/reanalyzed.json
```

循环 CSV 的表头为 `range_mpa,mean_mpa,count,start_index,end_index`。范围必须有限且非负，均值有限，次数有限且为正；次数可为半循环或累计次数。索引须为非负整数且 `end_index > start_index`。输入的是未分箱循环，不能把直方图箱上界当作原始范围。仅含表头的文件表示空循环谱，与恒值应力导出一致；缺少表头则是输入错误。读取循环 CSV 后仍使用相同的曲线覆盖检查和退出码。循环记录不能还原原始采样数，因此该模式的 JSON 不提供 `input_samples`。

S–N JSON 是点数组：

```json
[
  {"amplitude_mpa": 1, "cycles_to_failure": 10000000000},
  {"amplitude_mpa": 10, "cycles_to_failure": 1000000},
  {"amplitude_mpa": 100, "cycles_to_failure": 100}
]
```

至少两个点，幅值与寿命均有限且为正；幅值严格上升、寿命严格下降。区间内进行双对数插值，以 `Σ(count / allowable_cycles)` 计算 Miner 损伤。不外推、不假定曲线外存在疲劳极限。

首版不进行平均应力修正，输出保留 `mean_mpa` 和 `mean_stress_model: "none"`。使用者需确定曲线与所分析应力条件是否适配。示例曲线是 `N = 10¹⁰ / amplitude⁴` 的合成数据，不能用于真实材料寿命结论。

曲线未覆盖某些非零幅值时，JSON 省略 `total_damage`，列出 `out_of_range_cycles`；`evaluated_damage` 仅代表已覆盖的子集。CLI 返回 1，循环 CSV 和谱图仍可使用。恒值输入产生零损伤，但不代表静强度合格。

CLI 返回码：0 为所请求计算完成，1 为 S–N 覆盖不足，2 为无效输入、数值或文件错误。输出不能覆盖输入或彼此重合；路径检查后清除已存在的指定输出，避免失败后残留旧结果。JSON 中的无值可选字段省略。

## 调用计算核心

在调用方 `moon.pkg` 中导入 `"gckbbrant/fatigue-spectrum" @fatigue`。公开类型与接口见 [pkg.generated.mbti](pkg.generated.mbti)。

- `extract_cycles(stress)` 返回未分箱循环或结构化错误。
- `build_spectrum(cycles, width)` 生成显示用的范围直方图。
- `calculate_damage(cycles, curve)` 返回逐循环损伤与曲线覆盖情况。
- `parse_stress_csv`、`stress_csv`、`parse_cycles_csv`、`cycles_csv` 与 `render_spectrum_svg` 提供文件和图表接口。

`parse_stress_csv` 的可选参数 `time_column`、`stress_column`、`delimiter` 可选择测量列；`time_scale`、`stress_scale` 将输入乘到 s、MPa，默认均为 1。库调用者依据输入单位提供有限正比例即可复用同一解析过程。

可选参数 `skip_rows`、`decimal_comma` 分别控制跳过的物理行数和小数逗号，默认 0、false，与命令行共享实现。

可选 `stress_zero`、`stress_gain` 默认为 0、1，先计算 `(reading - stress_zero) * stress_gain`，再乘有限正数 `stress_scale`；增益允许负值。非有限参数、零增益和不可表示的换算返回错误，默认调用保持原有行为。

`stress_csv(samples)` 将公开的 `StressSample` 数组导出为标准应力 CSV，保留负应力和恒值段；空数组、非有限数值和不递增时间返回错误。

完整独立示例：[examples/basic/main.mbt](examples/basic/main.mbt)。

```sh
moon run --target native examples/basic
moon run --target js examples/basic
```

本地消费时将本项目和调用方列入 `moon.work`，调用方 `moon.mod` 引入 `gckbbrant/fatigue-spectrum@0.1.0`，再在包中导入核心。该库不依赖 bolt-preload；配套使用只需读取其导出的 `time_s,stress_mpa` CSV。

## 测试与对照

```sh
moon check --target native
moon test --target native
moon test --target js
python tests/test_cli.py
```

雨流参考对照需要可选的 Python 依赖：

```sh
python -m pip install rainflow==3.2.0
python scripts/compare_rainflow.py --cases 500 --seed 20261013
```

对照包含 12 组固定序列及 500 组随机序列，共比较 13377 条循环记录，范围、均值、次数和原始位置均无差异。[对照结果](samples/reference-check.json)记录版本、随机种子、命令和容差。

参考 rainflow 3.2.0 的两点输入会遗漏末端，恒值序列会产生零范围半循环；比较脚本明确应用本项目的端点约定后逐项比较，保留原始参考程序。核心测试另以手算验证这些约定、半循环残余、曲线端点、紧邻幅值与大寿命比的插值精度。

算法参考：[rainflow 3.2.0](https://github.com/iamlikeme/rainflow)。项目采用 [Apache-2.0](LICENSE)，参考实现的 MIT 许可全文保存在 [NOTICE](NOTICE)。Python 仅用于测试，运行库与 CLI 不依赖 Python。
