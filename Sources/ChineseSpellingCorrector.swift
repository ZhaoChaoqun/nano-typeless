import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "CSC")

/// macbert4csc 中文拼写纠错器
///
/// 使用 ONNX Runtime C API 加载 macbert4csc-base-chinese INT8 模型，
/// 对 ASR 输出的中文文本进行同音字/近音字纠错。
class ChineseSpellingCorrector {

    // MARK: - Constants

    /// ONNX Runtime intra-op 线程数
    private static let ortIntraOpThreads: Int32 = 2

    /// BERT 最大序列长度
    private static let maxSequenceLength = 512

    /// logit 差值阈值：预测 token 与原始 token 的 logit 差必须大于此值才执行替换
    private static let logitDiffThreshold: Float = 5.0

    /// softmax top-1 概率阈值：预测 token 的 softmax 概率必须大于此值才执行替换
    private static let softmaxProbThreshold: Float = 0.9

    /// 纠正比例上限：纠正的中文字符占比超过此值时丢弃所有纠正（防止上下文异常导致误纠）
    private static let maxCorrectionRatio: Float = 0.2

    // MARK: - Properties

    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?           // OrtEnv*
    private var session: OpaquePointer?       // OrtSession*
    private var memoryInfo: OpaquePointer?    // OrtMemoryInfo*
    private let tokenizer: BertTokenizer
    private let confidenceThreshold: Float

    /// 从 OrtStatus 提取错误信息
    private static func errorMessage(from api: UnsafePointer<OrtApi>, status: OpaquePointer) -> String {
        if let msg = api.pointee.GetErrorMessage(status) {
            return String(cString: msg)
        }
        return "未知错误"
    }

    /// 初始化 CSC 纠错器
    /// - Parameters:
    ///   - modelPath: model_int8.onnx 的路径
    ///   - vocabPath: vocab.txt 的路径
    ///   - confidenceThreshold: 纠正置信度阈值（默认 0.9）
    init?(modelPath: String, vocabPath: String, confidenceThreshold: Float = 0.9) {
        logger.info("ChineseSpellingCorrector: 开始初始化...")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            logger.error("CSC 模型文件不存在: \(modelPath, privacy: .public)")
            return nil
        }

        guard let tokenizer = BertTokenizer(vocabPath: vocabPath) else {
            logger.error("CSC 词表加载失败: \(vocabPath, privacy: .public)")
            return nil
        }

        self.tokenizer = tokenizer
        self.confidenceThreshold = confidenceThreshold

        // 获取 ONNX Runtime API
        guard let apiBase = OrtGetApiBase() else {
            logger.error("OrtGetApiBase() 返回 nil")
            return nil
        }
        guard let apiPtr = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            logger.error("GetApi() 返回 nil")
            return nil
        }
        self.api = apiPtr

        // 创建 Env
        var envPtr: OpaquePointer? = nil
        var status = api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "csc", &envPtr)
        if let status = status {
            let msg = Self.errorMessage(from: api, status: status)
            logger.error("CreateEnv 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(status)
            return nil
        }
        self.env = envPtr

        // 创建 SessionOptions
        var sessionOptionsPtr: OpaquePointer? = nil
        status = api.pointee.CreateSessionOptions(&sessionOptionsPtr)
        if let status = status {
            let msg = Self.errorMessage(from: api, status: status)
            logger.error("CreateSessionOptions 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(status)
            api.pointee.ReleaseEnv(envPtr)
            self.env = nil
            return nil
        }

        // 设置线程数
        _ = api.pointee.SetIntraOpNumThreads(sessionOptionsPtr, Self.ortIntraOpThreads)

        // 创建 Session
        var sessionPtr: OpaquePointer? = nil
        status = api.pointee.CreateSession(envPtr, modelPath, sessionOptionsPtr, &sessionPtr)
        api.pointee.ReleaseSessionOptions(sessionOptionsPtr)

        if let status = status {
            let msg = Self.errorMessage(from: api, status: status)
            logger.error("CreateSession 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(status)
            api.pointee.ReleaseEnv(envPtr)
            self.env = nil
            return nil
        }
        self.session = sessionPtr

        // 创建 MemoryInfo
        var memInfoPtr: OpaquePointer? = nil
        status = api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memInfoPtr)
        if let status = status {
            let msg = Self.errorMessage(from: api, status: status)
            logger.error("CreateCpuMemoryInfo 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(status)
            api.pointee.ReleaseSession(sessionPtr)
            api.pointee.ReleaseEnv(envPtr)
            self.session = nil
            self.env = nil
            return nil
        }
        self.memoryInfo = memInfoPtr

        logger.info("ChineseSpellingCorrector: 初始化成功 (vocab=\(tokenizer.vocabSize), threshold=\(confidenceThreshold))")
    }

    deinit {
        if let memoryInfo = memoryInfo { api.pointee.ReleaseMemoryInfo(memoryInfo) }
        if let session = session { api.pointee.ReleaseSession(session) }
        if let env = env { api.pointee.ReleaseEnv(env) }
    }

    /// 对文本进行拼写纠错
    func correctSpelling(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let chars = Array(text)

        // 分词
        let inputIds = tokenizer.tokenize(text)
        let seqLen = inputIds.count

        guard seqLen > 2 else { return text }  // 只有 [CLS] 和 [SEP]
        guard seqLen <= Self.maxSequenceLength else {
            logger.warning("文本过长 (\(seqLen) tokens)，跳过 CSC")
            return text
        }

        // 运行推理，获取 logits 指针
        guard let (logitsPtr, outputValue) = runInference(inputIds: inputIds, seqLen: seqLen) else {
            return text
        }
        defer { api.pointee.ReleaseValue(outputValue) }

        // 应用纠正
        return applyCorrections(
            chars: chars,
            inputIds: inputIds,
            seqLen: seqLen,
            logitsPtr: logitsPtr,
            originalText: text
        )
    }

    /// 运行 ONNX 推理，返回 logits 指针和输出 OrtValue（调用方负责释放）
    private func runInference(inputIds: [Int32], seqLen: Int) -> (UnsafeMutablePointer<Float>, OpaquePointer)? {
        // 准备输入张量
        var inputIdsCopy = inputIds.map { Int64($0) }
        var attentionMask = [Int64](repeating: 1, count: seqLen)
        var tokenTypeIds = [Int64](repeating: 0, count: seqLen)
        var shape: [Int64] = [1, Int64(seqLen)]

        // 创建 OrtValue
        guard let inputIdsValue = createTensor(&inputIdsCopy, shape: &shape),
              let attMaskValue = createTensor(&attentionMask, shape: &shape),
              let tokenTypeValue = createTensor(&tokenTypeIds, shape: &shape) else {
            logger.error("创建输入张量失败")
            return nil
        }
        defer {
            api.pointee.ReleaseValue(inputIdsValue)
            api.pointee.ReleaseValue(attMaskValue)
            api.pointee.ReleaseValue(tokenTypeValue)
        }

        let inputNames: [UnsafePointer<CChar>?] = [
            "input_ids",
            "attention_mask",
            "token_type_ids"
        ].map { ($0 as NSString).utf8String }

        let outputNames: [UnsafePointer<CChar>?] = [
            ("logits" as NSString).utf8String
        ]

        var inputValues: [OpaquePointer?] = [inputIdsValue, attMaskValue, tokenTypeValue]
        var outputValues: [OpaquePointer?] = [nil]

        let runStatus = api.pointee.Run(
            session,
            nil,  // RunOptions
            inputNames,
            &inputValues,
            3,
            outputNames,
            1,
            &outputValues
        )

        if let runStatus = runStatus {
            let msg = Self.errorMessage(from: api, status: runStatus)
            logger.error("Run 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(runStatus)
            return nil
        }

        guard let outputValue = outputValues[0] else {
            logger.error("输出值为 nil")
            return nil
        }

        // 获取 logits 数据指针
        var outputData: UnsafeMutableRawPointer? = nil
        let dataStatus = api.pointee.GetTensorMutableData(outputValue, &outputData)
        if let dataStatus = dataStatus {
            let msg = Self.errorMessage(from: api, status: dataStatus)
            logger.error("GetTensorMutableData 失败: \(msg, privacy: .public)")
            api.pointee.ReleaseStatus(dataStatus)
            api.pointee.ReleaseValue(outputValue)
            return nil
        }

        guard let logitsPtr = outputData?.assumingMemoryBound(to: Float.self) else {
            logger.error("logits 指针为 nil")
            api.pointee.ReleaseValue(outputValue)
            return nil
        }

        return (logitsPtr, outputValue)
    }

    /// 根据 logits 对每个位置进行纠正判定，返回纠正后的文本
    private func applyCorrections(
        chars: [Character],
        inputIds: [Int32],
        seqLen: Int,
        logitsPtr: UnsafeMutablePointer<Float>,
        originalText: String
    ) -> String {
        let vocabSize = tokenizer.vocabSize
        var corrected = chars
        var correctionCount = 0
        var chineseCharCount = 0

        // 遍历中间 token（跳过 [CLS] 和 [SEP]）
        for i in 1..<(seqLen - 1) {
            let charIndex = i - 1  // chars 数组的索引
            guard charIndex < chars.count else { break }

            // 只纠正中文字符
            guard BertTokenizer.isChinese(chars[charIndex]) else { continue }
            chineseCharCount += 1

            if let correctedChar = evaluateCorrection(
                tokenIndex: i,
                originalId: inputIds[i],
                logitsPtr: logitsPtr,
                vocabSize: vocabSize
            ) {
                corrected[charIndex] = correctedChar
                correctionCount += 1
            }
        }

        // Sanity check：如果纠正比例超过 20%，说明输入可能有上下文问题，丢弃纠正
        if correctionCount > 0 && chineseCharCount > 0 {
            let correctionRatio = Float(correctionCount) / Float(chineseCharCount)
            if correctionRatio > Self.maxCorrectionRatio {
                logger.warning("CSC 纠正比例过高 (\(correctionCount)/\(chineseCharCount) = \(String(format: "%.0f%%", correctionRatio * 100)))，丢弃纠正结果")
                return originalText
            }

            let result = String(corrected)
            logger.info("CSC 纠正了 \(correctionCount) 处: \(originalText, privacy: .public) → \(result, privacy: .public)")
            return result
        }

        return originalText
    }

    /// 评估单个位置是否需要纠正，返回纠正后的字符（若不需要纠正则返回 nil）
    private func evaluateCorrection(
        tokenIndex: Int,
        originalId: Int32,
        logitsPtr: UnsafeMutablePointer<Float>,
        vocabSize: Int
    ) -> Character? {
        let logitsOffset = tokenIndex * vocabSize

        // 取 argmax
        var maxVal: Float = -Float.infinity
        var maxIdx: Int32 = 0

        for j in 0..<vocabSize {
            let val = logitsPtr[logitsOffset + j]
            if val > maxVal {
                maxVal = val
                maxIdx = Int32(j)
            }
        }

        // 如果预测不同于输入且不是特殊 token
        guard maxIdx != originalId && maxIdx != tokenizer.unkId else { return nil }

        let originalLogit = logitsPtr[logitsOffset + Int(originalId)]
        let logitDiff = maxVal - originalLogit

        // 条件 1：logit 差值必须足够大，防止低置信度替换
        guard logitDiff > Self.logitDiffThreshold else { return nil }

        // 条件 2：计算 softmax 概率，top-1 概率必须足够高
        // 为数值稳定性，对 logits 减去 maxVal 后再 softmax
        var expSum: Float = 0
        for j in 0..<vocabSize {
            expSum += exp(logitsPtr[logitsOffset + j] - maxVal)
        }
        let topProb = 1.0 / expSum  // exp(0) / expSum since maxVal - maxVal = 0
        guard topProb > Self.softmaxProbThreshold else { return nil }

        let correctedChar = tokenizer.decode([maxIdx])
        if !correctedChar.isEmpty && correctedChar.count == 1 {
            if let firstChar = correctedChar.first, BertTokenizer.isChinese(firstChar) {
                return firstChar
            }
        }
        return nil
    }

    /// 创建 Int64 类型的 OrtValue 张量
    private func createTensor(_ data: inout [Int64], shape: inout [Int64]) -> OpaquePointer? {
        var value: OpaquePointer? = nil
        let dataSize = data.count * MemoryLayout<Int64>.stride
        let status = data.withUnsafeMutableBufferPointer { dataBuffer in
            shape.withUnsafeMutableBufferPointer { shapeBuffer in
                api.pointee.CreateTensorWithDataAsOrtValue(
                    memoryInfo,
                    dataBuffer.baseAddress,
                    dataSize,
                    shapeBuffer.baseAddress,
                    shapeBuffer.count,
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                    &value
                )
            }
        }
        if let status = status {
            api.pointee.ReleaseStatus(status)
            return nil
        }
        return value
    }
}
