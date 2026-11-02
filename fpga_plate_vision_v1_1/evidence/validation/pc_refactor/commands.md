# PC拆分验证命令

工作目录：`E:/FPGA_Test_Work/plate_recognition_engineering`。全部为离线运行；单元测试中的串口对象被测试替身替代。

```powershell
python -m unittest discover -s pc -p test_observe_auto.py -v
python -m unittest discover -s pc -p test_auto_capture.py -v
python -m unittest discover -s pc -p 'test_*.py' -v
python -B E:/FPGA_Test_Work/plate_autonomous_board_20261101/pc/observe_auto.py --wire evidence/baseline/reports/split_aligned_repeat_100/wire.bin --frames 100 --truth BD12345 --out reports/pc_refactor/baseline_replay
python -B pc/observe_auto.py --wire evidence/baseline/reports/split_aligned_repeat_100/wire.bin --frames 100 --truth BD12345 --out reports/pc_refactor/current_replay
```

原始运行输出分别为`before_observer_tests.log`、`red_capture_tests.log`、`after_all_tests.log`、`baseline_replay.log`、`current_replay.log`。红灯测试在抽取前执行，因`auto_capture`不存在出现2项预期失败；抽取后全部61项通过。已有输出目录不能复用，复验时指定新目录并相应更新比较路径。

比较记录`replay_comparison.json`检查：新旧回放汇总除两项实测耗时外相等；wire与历史输入相同；拒绝记录、packets.json、raw.npy、result.json逐字节相同；NPZ中的各命名数组相等；历史100帧result.json结构相等；历史汇总再排除source后相等。JSON编解码、FrameCollector和verify_frame共5个定义的AST与旧observe_auto.py相同。

阶段边界：这是结构重构、PC单元测试和旧wire回放，不是新RTL、时序或实机结果。未写入旧目录、未打开任何串口、未修改模型、未访问Flash。
