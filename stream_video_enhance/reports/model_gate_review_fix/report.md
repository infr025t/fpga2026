# 第二轮模型门槛审阅修正

本轮只修复两个P2验收护栏。原72项正式实验仍为FAIL，零可行参数、无profile；没有重跑正式候选或保留集。第一、二轮全部62个归档文件相对`f4fb6af`逐字节不变，见`preservation.json`。

主增强目标现在由已知expanded-v2实验的独立固定契约约束：tuning/holdout各恰为对应`text_low_clean`和`texture_p4_a32_clean`，顺序固定；每个目标恰有一个匹配split、category、clean自身引用、sigma0及原掩膜名的case。随后以这组固定目标校验17项required清单，拒绝删减、重复和替换。不能同时编辑primary和required元数据来降低门槛。original-v1的历史重放语义保留。

`red_primary.txt`记录修复前16个primary/关联case变体均未被拒绝；修复后同组测试通过。`inventory_validation.json`额外证明required清单缺失、重复、替换均被拒绝，原登记907个数组和17项required仍有效。

执行追溯在数值回归和任何滤波前绑定源码身份。公共API：

```python
bundle = capture_execution_sources(root=dataset.ROOT)
# {'commit': '<entry HEAD SHA>',
#  'source_sha256': {'stream_video_enhance/model/evaluate.py': '<SHA256>', ...}}
verify_execution_sources(bundle, root=dataset.ROOT)
# 成功返回None，不修改bundle；脏/未跟踪/缺失/变化的Python源抛ValueError。
```

入口快照覆盖已知六个model/test Python文件及这些目录里新增的Python源。每份当前文件字节必须匹配入口commit的Git blob，且相关工作区/暂存区保持干净；新增未跟踪Python源也拒绝。运行结束、发布前重新检查源码哈希与文件集合。无关文档提交允许推进HEAD，bundle的入口commit不随之改变。未来metrics/profile同时保存`source_model_commit=bundle['commit']`和完整`execution_sources=bundle`。本修正不追补或改写原轮已归档的执行追溯。

测试使用独立的临时真实Git仓库：入口未暂存/已暂存改动、未跟踪源、缺失源均拒绝；运行中修改源、新增源、提交修改后的源均拒绝；只新增并提交README允许通过，并保留入口commit及该commit对应的源码哈希。没有运行任何新候选。

修复前API缺失的RED证据在`red.txt`；其最初两个primary测试曾因Windows默认GBK读取UTF-8登记发生测试夹具错误，纠正为显式UTF-8后，在`red_primary.txt`得到预期16个拒绝缺失失败。focused GREEN命令为`python -m unittest stream_video_enhance.tests.test_evaluation -v`，22项测试、17.898秒、OK，详见`green.txt`。

最终全套命令为`python -m unittest discover -s stream_video_enhance/tests -v`；33项测试、110.771秒、OK。288组VGA最大误差1 LSB，误差直方图0/1LSB=[85812329,99223]、MAE0.001154944、RMSE0.033984462；输出保存在`full_suite.txt`。源码修正不改变参考算术、既有数据、公式、阈值或正式实验结论；真实曝光/固定曝光视频继续DEFERRED，不产生RTL或profile。

修正代码提交`dfce26a`后，在真实仓库调用上述两个API得到入口源码身份校验PASS，六个源码哈希均与该commit的Git blob一致，记录于`source_guard_validation.json`。此记录只验证修正后的入口护栏，不是质量搜索或对原FAIL实验追溯字段的回填。
