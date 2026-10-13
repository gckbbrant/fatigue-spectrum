# 机械应力循环谱分析工具

用 MoonBit 提取雨流循环、生成应力范围直方图，并根据给定 S–N 曲线计算 Miner 损伤。
`extract_cycles`、`build_spectrum`、`calculate_damage` 均可独立调用。

应力采用 MPa。雨流结果保留原始索引与循环均值，残余按半循环处理。
S–N 横轴为应力幅，采用双对数插值，不外推、不做平均应力修正。

运行核心测试：`moon test --target native`。
