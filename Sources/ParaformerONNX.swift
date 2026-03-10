import Foundation
import os

#if SWIFT_PACKAGE
import CSherpaOnnx
#endif

private let logger = Logger(subsystem: "com.typeless.app", category: "ParaformerONNX")

/// 原生 ONNX Runtime Streaming Paraformer 推理引擎
///
/// 替换 sherpa-onnx 的流式 Paraformer，修复三层尾部截断问题：
/// 1. IsReady() 门控允许短 chunk（final chunk 不足 61 帧也处理）
/// 2. Final chunk 不对右上下文 alpha 置零
/// 3. CIF tail_threshold=0.45 flush 残余 token
///
/// 使用 fp16 模型，需要 ORT_ENABLE_EXTENDED 图优化级别。
class ParaformerONNX {

    // MARK: - ORT handles

    private let api: UnsafePointer<OrtApi>
    private var env: OpaquePointer?              // OrtEnv*
    private var encoderSession: OpaquePointer?   // OrtSession*
    private var decoderSession: OpaquePointer?   // OrtSession*
    private var memoryInfo: OpaquePointer?        // OrtMemoryInfo*

    // MARK: - 模型参数（从 encoder metadata 读取）

    private var negMean: [Float] = []             // 560-dim CMVN
    private var invStddev: [Float] = []           // 560-dim CMVN
    private let lfrM: Int = 7                     // LFR 窗口大小
    private let lfrN: Int = 6                     // LFR 步长
    private let encoderDim: Int = 512
    private let featureDim: Int = 560             // 80 * 7

    // MARK: - Token 映射

    private let tokens: [Int: String]

    // MARK: - 流式参数

    private let chunkSize: Int = 61               // raw fbank frames per chunk
    private let leftChunkSize: Int = 5            // LFR frames of left context
    private let rightChunkSize: Int = 3           // LFR frames of right context
    private let lfrChunkSize: Int = 10            // effective LFR frames per chunk
    private let cifThreshold: Float = 1.0
    private let tailThreshold: Float = 0.45

    // MARK: - 流式状态

    private var fbank: ParaformerFbank
    private var processedFbankFrames: Int = 0     // 已处理的 raw fbank 帧数
    private var featCache: [Float] = []           // LFR feature cache [8 * 560]
    private var cifAlphaRemainder: Float = 0.0    // CIF 残余 alpha
    private var cifHiddenCache: [Float] = []      // CIF 残余 hidden [512]
    private var decoderCaches: [[Float]] = []     // 16 层 decoder cache [512 * 10]
    private var resultTokenIds: [Int32] = []      // 已解码的全部 token IDs
    private var isFinalProcessed: Bool = false
    private var isFirstChunk: Bool = true

    // MARK: - 初始化

    init?(encoderPath: String, decoderPath: String, tokensPath: String) {
        logger.info("ParaformerONNX: 开始初始化...")

        guard FileManager.default.fileExists(atPath: encoderPath),
              FileManager.default.fileExists(atPath: decoderPath),
              FileManager.default.fileExists(atPath: tokensPath) else {
            logger.error("ParaformerONNX: 模型文件不存在")
            return nil
        }

        // 获取 ORT API
        guard let apiBase = OrtGetApiBase() else {
            logger.error("OrtGetApiBase() 返回 nil")
            return nil
        }
        guard let apiPtr = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            logger.error("GetApi() 返回 nil")
            return nil
        }
        self.api = apiPtr

        // 加载 tokens
        guard let toks = ParaformerONNX.loadTokens(path: tokensPath) else {
            logger.error("加载 tokens.txt 失败")
            return nil
        }
        self.tokens = toks

        // 创建 fbank
        self.fbank = ParaformerFbank()

        // 创建 ORT Env
        var envPtr: OpaquePointer? = nil
        let localApi = self.api
        var status = localApi.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "paraformer", &envPtr)
        if let s = status {
            logger.error("CreateEnv 失败: \(Self.errorMsg(localApi, s), privacy: .public)")
            localApi.pointee.ReleaseStatus(s)
            return nil
        }
        self.env = envPtr

        // 创建 SessionOptions (fp16 需要 ORT_ENABLE_EXTENDED)
        var sessionOptsPtr: OpaquePointer? = nil
        status = localApi.pointee.CreateSessionOptions(&sessionOptsPtr)
        if let s = status {
            logger.error("CreateSessionOptions 失败: \(Self.errorMsg(localApi, s), privacy: .public)")
            localApi.pointee.ReleaseStatus(s)
            localApi.pointee.ReleaseEnv(envPtr)
            self.env = nil
            return nil
        }
        _ = localApi.pointee.SetIntraOpNumThreads(sessionOptsPtr, 2)
        _ = localApi.pointee.SetSessionGraphOptimizationLevel(sessionOptsPtr, ORT_ENABLE_EXTENDED)

        // 创建 Encoder Session
        var encSessPtr: OpaquePointer? = nil
        status = localApi.pointee.CreateSession(envPtr, encoderPath, sessionOptsPtr, &encSessPtr)
        if let s = status {
            logger.error("CreateSession(encoder) 失败: \(Self.errorMsg(localApi, s), privacy: .public)")
            localApi.pointee.ReleaseStatus(s)
            localApi.pointee.ReleaseSessionOptions(sessionOptsPtr)
            localApi.pointee.ReleaseEnv(envPtr)
            self.env = nil
            return nil
        }
        self.encoderSession = encSessPtr

        // 创建 Decoder Session
        var decSessPtr: OpaquePointer? = nil
        status = localApi.pointee.CreateSession(envPtr, decoderPath, sessionOptsPtr, &decSessPtr)
        localApi.pointee.ReleaseSessionOptions(sessionOptsPtr)
        if let s = status {
            logger.error("CreateSession(decoder) 失败: \(Self.errorMsg(localApi, s), privacy: .public)")
            localApi.pointee.ReleaseStatus(s)
            localApi.pointee.ReleaseSession(encSessPtr)
            localApi.pointee.ReleaseEnv(envPtr)
            self.encoderSession = nil
            self.env = nil
            return nil
        }
        self.decoderSession = decSessPtr

        // 创建 MemoryInfo
        var memInfoPtr: OpaquePointer? = nil
        status = localApi.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memInfoPtr)
        if let s = status {
            logger.error("CreateCpuMemoryInfo 失败: \(Self.errorMsg(localApi, s), privacy: .public)")
            localApi.pointee.ReleaseStatus(s)
            localApi.pointee.ReleaseSession(decSessPtr)
            localApi.pointee.ReleaseSession(encSessPtr)
            localApi.pointee.ReleaseEnv(envPtr)
            self.decoderSession = nil
            self.encoderSession = nil
            self.env = nil
            return nil
        }
        self.memoryInfo = memInfoPtr

        // 从 encoder metadata 读取 CMVN 参数
        if !self.loadMetadata(from: encSessPtr!) {
            logger.error("读取 encoder metadata 失败")
            localApi.pointee.ReleaseMemoryInfo(memInfoPtr)
            localApi.pointee.ReleaseSession(decSessPtr)
            localApi.pointee.ReleaseSession(encSessPtr)
            localApi.pointee.ReleaseEnv(envPtr)
            self.memoryInfo = nil
            self.decoderSession = nil
            self.encoderSession = nil
            self.env = nil
            return nil
        }

        // 初始化流式状态
        self.initStreamState()

        logger.info("ParaformerONNX: 初始化成功 (vocab=\(self.tokens.count))")
    }

    deinit {
        if let m = memoryInfo { api.pointee.ReleaseMemoryInfo(m) }
        if let s = decoderSession { api.pointee.ReleaseSession(s) }
        if let s = encoderSession { api.pointee.ReleaseSession(s) }
        if let e = env { api.pointee.ReleaseEnv(e) }
    }

    // MARK: - 公开接口（与 SherpaOnnxOnlineRecognizer 一致）

    /// 接收音频 samples（float32, -1.0~1.0 范围，内部会转 int16 范围）
    func acceptWaveform(samples: [Float], sampleRate: Int32 = 16000) {
        guard !samples.isEmpty else { return }
        // sherpa-onnx normalize_samples=false: 期望 int16 范围
        let scaled = samples.map { $0 * 32768.0 }
        fbank.acceptWaveform(samples: scaled)
    }

    /// 是否有足够帧做一次 decode
    func isReady() -> Bool {
        if isFinalProcessed { return false }
        let availableFrames = fbank.numFramesReady - processedFbankFrames
        return availableFrames >= chunkSize
    }

    /// 处理一个 chunk
    func decode() {
        guard !isFinalProcessed else { return }
        let availableFrames = fbank.numFramesReady - processedFbankFrames
        guard availableFrames >= chunkSize else { return }
        processChunk(isFinal: false)
    }

    /// 获取当前识别结果
    func getResult() -> String {
        var text = idsToText(resultTokenIds)
        // 移除中文和英文之间的空格（与 SherpaOnnxOnlineRecognizer 一致）
        text = text.replacingOccurrences(of: "([\\u4e00-\\u9fa5])\\s+([a-zA-Z0-9])", with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "([a-zA-Z0-9])\\s+([\\u4e00-\\u9fa5])", with: "$1$2", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 标记输入结束，处理剩余帧（final chunk）
    func inputFinished() {
        guard !isFinalProcessed else { return }
        fbank.inputFinished()

        let availableFrames = fbank.numFramesReady - processedFbankFrames
        if availableFrames > 0 {
            processChunk(isFinal: true)
        } else if cifAlphaRemainder > tailThreshold {
            // 没有剩余帧但 CIF 有残余 alpha，用 tail flush 生成最后一个 token
            flushCifTail()
        }
        isFinalProcessed = true
    }

    /// 重置全部状态
    func reset() {
        fbank.reset()
        initStreamState()
    }

    /// 离线一次性转录（用于调试和 benchmark 对比）
    /// 接收全部 samples，一次性 fbank → LFR → CMVN → encoder → CIF → decoder
    func transcribeOffline(samples: [Float]) -> String {
        reset()

        // 1. Fbank
        let scaled = samples.map { $0 * 32768.0 }
        fbank.acceptWaveform(samples: scaled)
        fbank.inputFinished()
        let numFrames = fbank.numFramesReady
        guard numFrames > 0 else { return "" }

        var rawFbank = [Float]()
        rawFbank.reserveCapacity(numFrames * 80)
        for i in 0..<numFrames {
            rawFbank.append(contentsOf: fbank.getFrame(i))
        }

        // 2. LFR
        let lfr = applyLFR(rawFbank, numFrames: numFrames)
        let lfrFrameCount = lfr.count / featureDim
        guard lfrFrameCount > 0 else { return "" }

        // 3. CMVN
        let cmvn = applyCMVN(lfr)

        // 4. Encoder
        guard let (enc, alphas) = encoderForward(features: cmvn, frameCount: lfrFrameCount) else {
            return ""
        }

        // 5. CIF
        let (embeds, numTokens) = cifIntegrate(
            enc: enc, alphas: alphas, frameCount: lfrFrameCount, isFinal: true
        )
        guard numTokens > 0 else { return "" }

        // 6. Decoder
        if let tokenIds = decoderForward(enc: enc, encLen: lfrFrameCount, embeds: embeds, numTokens: numTokens) {
            resultTokenIds = tokenIds
        }

        return getResult()
    }

    // MARK: - 流式状态初始化

    private func initStreamState() {
        processedFbankFrames = 0
        featCache = [Float](repeating: 0, count: (leftChunkSize + rightChunkSize) * featureDim)
        cifAlphaRemainder = 0.0
        cifHiddenCache = [Float](repeating: 0, count: encoderDim)
        decoderCaches = (0..<16).map { _ in [Float](repeating: 0, count: encoderDim * 10) }
        resultTokenIds = []
        isFinalProcessed = false
        isFirstChunk = true
    }

    // MARK: - Chunk 处理核心

    /// 处理一个 chunk（常规或 final）
    private func processChunk(isFinal: Bool) {
        // 1. 取 raw fbank 帧
        let availableFrames = fbank.numFramesReady - processedFbankFrames
        let framesToTake = isFinal ? availableFrames : chunkSize

        guard framesToTake > 0 else { return }

        // 收集 fbank 帧
        var rawFbank = [Float]()
        rawFbank.reserveCapacity(framesToTake * 80)
        for i in 0..<framesToTake {
            rawFbank.append(contentsOf: fbank.getFrame(processedFbankFrames + i))
        }
        processedFbankFrames += isFinal ? framesToTake : (chunkSize - 1)  // 1-frame overlap

        // 2. LFR 变换
        let lfr = applyLFR(rawFbank, numFrames: framesToTake)
        let lfrFrameCount = lfr.count / featureDim

        guard lfrFrameCount > 0 else { return }

        // 3. CMVN
        let cmvn = applyCMVN(lfr)

        // 4. 拼接 featCache（左上下文 + 当前 + 右上下文来自 cache）
        //    featCache 存储的是上一个 chunk 的最后 8 LFR 帧（5 left + 3 right）
        let cacheFrameCount = featCache.count / featureDim
        var encoderInput: [Float]
        if isFirstChunk {
            // 第一个 chunk 没有左上下文 cache
            encoderInput = cmvn
            isFirstChunk = false
        } else {
            // 拼接: featCache + cmvn
            encoderInput = featCache + cmvn
        }
        let encoderFrameCount = encoderInput.count / featureDim

        // 更新 featCache：保留当前 LFR 帧的最后 8 帧
        let cacheTotalFrames = leftChunkSize + rightChunkSize  // 8
        if lfrFrameCount >= cacheTotalFrames {
            let startIdx = (lfrFrameCount - cacheTotalFrames) * featureDim
            featCache = Array(cmvn[startIdx...])
        } else {
            // 不足 8 帧：保留 cache 的较新部分 + 全部新帧
            let keepFromOldCache = cacheTotalFrames - lfrFrameCount
            if keepFromOldCache > 0 && cacheFrameCount >= cacheTotalFrames {
                let oldStart = (cacheFrameCount - keepFromOldCache) * featureDim
                featCache = Array(featCache.suffix(from: oldStart)) + cmvn
            } else {
                featCache = cmvn
            }
            // 确保 cache 不超过 8 帧
            if featCache.count > cacheTotalFrames * featureDim {
                let excess = featCache.count - cacheTotalFrames * featureDim
                featCache.removeFirst(excess)
            }
        }

        // 5. Encoder forward
        guard let (enc, alphas) = encoderForward(features: encoderInput, frameCount: encoderFrameCount) else {
            logger.error("Encoder forward 失败")
            return
        }

        // 6. Alpha 置零（左/右上下文）
        var maskedAlphas = alphas
        let leftCtx: Int
        let rightCtx: Int

        if !isFirstChunk || encoderFrameCount > lfrFrameCount {
            // 有左上下文
            leftCtx = min(leftChunkSize, encoderFrameCount - lfrFrameCount)
            // 右上下文 = 剩余帧（如果 encoderFrameCount > leftCtx + lfrFrameCount）
            rightCtx = max(0, encoderFrameCount - leftCtx - lfrFrameCount)
        } else {
            leftCtx = 0
            rightCtx = 0
        }

        // 置零左上下文 alphas
        for i in 0..<leftCtx {
            maskedAlphas[i] = 0
        }

        // 置零右上下文 alphas（除非 final chunk）
        if !isFinal && rightCtx > 0 {
            for i in (encoderFrameCount - rightCtx)..<encoderFrameCount {
                maskedAlphas[i] = 0
            }
        }

        // 只取中心区域的 enc 和 alphas（排除左右上下文）
        let centerStart = leftCtx
        let centerEnd = isFinal ? encoderFrameCount : (encoderFrameCount - rightCtx)
        let centerLen = max(0, centerEnd - centerStart)

        guard centerLen > 0 else { return }

        let centerEnc = Array(enc[(centerStart * encoderDim)..<(centerEnd * encoderDim)])
        let centerAlphas = Array(maskedAlphas[centerStart..<centerEnd])

        // 7. CIF 积分
        let (embeds, numTokens) = cifIntegrate(
            enc: centerEnc,
            alphas: centerAlphas,
            frameCount: centerLen,
            isFinal: isFinal
        )

        guard numTokens > 0 else { return }

        // 8. Decoder forward
        if let newTokenIds = decoderForward(enc: centerEnc, encLen: centerLen, embeds: embeds, numTokens: numTokens) {
            resultTokenIds.append(contentsOf: newTokenIds)
        }
    }

    /// CIF tail flush（当 final 但没有新帧时使用）
    private func flushCifTail() {
        // 用残余 alpha + hidden 生成最后一个 token
        guard cifAlphaRemainder > tailThreshold else { return }

        // 需要最后一个 chunk 的 encoder 输出来做 decoder cross-attention
        // 此场景极少发生（需要所有帧刚好被常规 chunk 消化完且有 CIF 残余）
        // 如果没有保存则跳过
        logger.warning("CIF tail flush 但无 encoder 缓存，跳过")
    }

    // MARK: - LFR 变换

    /// Low Frame Rate: 拼 m=7 帧步长 n=6
    /// 输入: raw fbank [T, 80] flat array
    /// 输出: LFR [T_lfr, 560] flat array
    private func applyLFR(_ fbank: [Float], numFrames: Int) -> [Float] {
        let D = 80
        let T = numFrames

        // 左 padding: 复制首帧 (m-1)//2 = 3 次
        let padLeft = (lfrM - 1) / 2  // 3
        let TPadded = T + padLeft

        var padded = [Float](repeating: 0, count: TPadded * D)
        // 前 3 帧用首帧填充
        for i in 0..<padLeft {
            padded.replaceSubrange((i * D)..<((i + 1) * D), with: fbank[0..<D])
        }
        // 复制原始帧
        for i in 0..<T {
            let srcStart = i * D
            let dstStart = (i + padLeft) * D
            padded.replaceSubrange(dstStart..<(dstStart + D), with: fbank[srcStart..<(srcStart + D)])
        }

        // 计算 LFR 帧数
        let tLfr = max(0, (TPadded - lfrM) / lfrN + 1)
        guard tLfr > 0 else { return [] }

        var lfr = [Float](repeating: 0, count: tLfr * featureDim)
        for i in 0..<tLfr {
            let start = i * lfrN
            for j in 0..<lfrM {
                let srcOff = (start + j) * D
                let dstOff = i * featureDim + j * D
                lfr.replaceSubrange(dstOff..<(dstOff + D), with: padded[srcOff..<(srcOff + D)])
            }
        }

        return lfr
    }

    // MARK: - CMVN

    /// CMVN: (features + neg_mean) * inv_stddev
    private func applyCMVN(_ features: [Float]) -> [Float] {
        var result = features
        for i in 0..<result.count {
            let dim = i % featureDim
            result[i] = (result[i] + negMean[dim]) * invStddev[dim]
        }
        return result
    }

    // MARK: - Encoder Forward

    /// Encoder ONNX forward pass
    /// 输入: features [T, 560] flat, frameCount = T
    /// 输出: (enc [T*512] flat, alphas [T])
    private func encoderForward(features: [Float], frameCount: Int) -> (enc: [Float], alphas: [Float])? {
        guard let session = encoderSession else { return nil }
        let api = self.api

        // 创建 speech tensor (ORT allocator 拥有内存，无生命周期问题)
        let speechShape: [Int64] = [1, Int64(frameCount), Int64(featureDim)]
        guard let speechValue = createFloatTensor(features, shape: speechShape) else {
            logger.error("创建 speech tensor 失败")
            return nil
        }
        defer { api.pointee.ReleaseValue(speechValue) }

        // 创建 speech_lengths tensor
        let speechLensShape: [Int64] = [1]
        guard let speechLensValue = createInt32Tensor([Int32(frameCount)], shape: speechLensShape) else {
            logger.error("创建 speech_lengths tensor 失败")
            return nil
        }
        defer { api.pointee.ReleaseValue(speechLensValue) }

        // Run encoder
        let inputNames: [UnsafePointer<CChar>?] = [
            ("speech" as NSString).utf8String,
            ("speech_lengths" as NSString).utf8String,
        ]
        let outputNames: [UnsafePointer<CChar>?] = [
            ("enc" as NSString).utf8String,
            ("enc_len" as NSString).utf8String,
            ("alphas" as NSString).utf8String,
        ]
        var inputValues: [OpaquePointer?] = [speechValue, speechLensValue]
        var outputValues: [OpaquePointer?] = [nil, nil, nil]

        let runStatus = api.pointee.Run(
            session, nil,
            inputNames, &inputValues, 2,
            outputNames, 3, &outputValues
        )
        if let s = runStatus {
            logger.error("Encoder Run 失败: \(Self.errorMsg(api, s), privacy: .public)")
            api.pointee.ReleaseStatus(s)
            return nil
        }
        defer {
            for v in outputValues { if let v = v { api.pointee.ReleaseValue(v) } }
        }

        // 读取 encoder 输出
        guard let encValue = outputValues[0],
              let alphasValue = outputValues[2] else {
            logger.error("Encoder 输出为 nil")
            return nil
        }

        // enc [1, T, 512] → flat [T*512]
        var encDataPtr: UnsafeMutableRawPointer? = nil
        var status = api.pointee.GetTensorMutableData(encValue, &encDataPtr)
        guard status == nil, let encPtr = encDataPtr?.assumingMemoryBound(to: Float.self) else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }
        let enc = Array(UnsafeBufferPointer(start: encPtr, count: frameCount * encoderDim))

        // alphas [1, T] → flat [T]
        var alphasDataPtr: UnsafeMutableRawPointer? = nil
        status = api.pointee.GetTensorMutableData(alphasValue, &alphasDataPtr)
        guard status == nil, let aPtr = alphasDataPtr?.assumingMemoryBound(to: Float.self) else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }
        let alphas = Array(UnsafeBufferPointer(start: aPtr, count: frameCount))

        return (enc, alphas)
    }

    // MARK: - CIF 积分

    /// CIF 积分（跨 chunk 状态管理）
    /// 返回: (embeds [N*512] flat, numTokens)
    private func cifIntegrate(
        enc: [Float],
        alphas: [Float],
        frameCount: Int,
        isFinal: Bool
    ) -> (embeds: [Float], numTokens: Int) {
        var accumulate = cifAlphaRemainder
        var hiddenBuf = cifHiddenCache
        var embeds: [Float] = []

        for t in 0..<frameCount {
            let alpha = alphas[t]
            accumulate += alpha

            // hidden_buf += alpha * enc[t]
            let encOffset = t * encoderDim
            for d in 0..<encoderDim {
                hiddenBuf[d] += alpha * enc[encOffset + d]
            }

            if accumulate >= cifThreshold {
                let remainder = accumulate - cifThreshold
                // embed = hidden_buf - remainder * enc[t]
                var embed = [Float](repeating: 0, count: encoderDim)
                for d in 0..<encoderDim {
                    embed[d] = hiddenBuf[d] - remainder * enc[encOffset + d]
                }
                embeds.append(contentsOf: embed)

                // 新 token 从 remainder 开始
                accumulate = remainder
                for d in 0..<encoderDim {
                    hiddenBuf[d] = remainder * enc[encOffset + d]
                }
            }
        }

        // Tail flush: isFinal 时追加 tailThreshold
        if isFinal {
            accumulate += tailThreshold
            // hidden_buf 不变（tail 对应 zero hidden）
            if accumulate >= cifThreshold {
                // fire
                let embed = hiddenBuf  // 残余 hidden 直接作为最后一个 embedding
                embeds.append(contentsOf: embed)
                accumulate = 0
                hiddenBuf = [Float](repeating: 0, count: encoderDim)
            }
        }

        // 更新状态
        cifAlphaRemainder = accumulate
        cifHiddenCache = hiddenBuf

        let numTokens = embeds.count / encoderDim
        return (embeds, numTokens)
    }

    // MARK: - Decoder Forward

    /// Decoder ONNX forward pass
    /// 返回 token IDs（已过滤特殊 token）
    private func decoderForward(enc: [Float], encLen: Int, embeds: [Float], numTokens: Int) -> [Int32]? {
        guard let session = decoderSession, memoryInfo != nil else { return nil }
        let api = self.api

        // 准备输入
        let encData = enc
        let encShape: [Int64] = [1, Int64(encLen), Int64(encoderDim)]
        let encLenData = [Int32(encLen)]
        let encLenShape: [Int64] = [1]
        let embedsData = embeds
        let embedsShape: [Int64] = [1, Int64(numTokens), Int64(encoderDim)]
        let embedsLenData = [Int32(numTokens)]
        let embedsLenShape: [Int64] = [1]

        // 创建输入 tensors
        let encValue = createFloatTensor(encData, shape: encShape)
        let encLenValue = createInt32Tensor(encLenData, shape: encLenShape)
        let embedsValue = createFloatTensor(embedsData, shape: embedsShape)
        let embedsLenValue = createInt32Tensor(embedsLenData, shape: embedsLenShape)

        guard encValue != nil, encLenValue != nil, embedsValue != nil, embedsLenValue != nil else {
            logger.error("创建 decoder 输入 tensor 失败")
            [encValue, encLenValue, embedsValue, embedsLenValue].compactMap { $0 }.forEach { api.pointee.ReleaseValue($0) }
            return nil
        }

        // 创建 16 层 cache tensors
        var cacheValues: [OpaquePointer?] = []
        let cacheShape: [Int64] = [1, Int64(encoderDim), 10]
        for i in 0..<16 {
            let val = createFloatTensor(decoderCaches[i], shape: cacheShape)
            cacheValues.append(val)
        }

        // 准备所有输入
        var inputNames: [UnsafePointer<CChar>?] = [
            ("enc" as NSString).utf8String,
            ("enc_len" as NSString).utf8String,
            ("acoustic_embeds" as NSString).utf8String,
            ("acoustic_embeds_len" as NSString).utf8String,
        ]
        for i in 0..<16 {
            inputNames.append(("in_cache_\(i)" as NSString).utf8String)
        }

        var inputValues: [OpaquePointer?] = [encValue, encLenValue, embedsValue, embedsLenValue]
        inputValues.append(contentsOf: cacheValues)

        // 输出名
        var outputNames: [UnsafePointer<CChar>?] = [
            ("sample_ids" as NSString).utf8String,
        ]
        for i in 0..<16 {
            outputNames.append(("out_cache_\(i)" as NSString).utf8String)
        }

        var outputValues = [OpaquePointer?](repeating: nil, count: 17)

        // Run
        let runStatus = api.pointee.Run(
            session, nil,
            inputNames, &inputValues, inputNames.count,
            outputNames, outputNames.count, &outputValues
        )

        // 释放输入
        [encValue, encLenValue, embedsValue, embedsLenValue].forEach { if let v = $0 { api.pointee.ReleaseValue(v) } }
        cacheValues.forEach { if let v = $0 { api.pointee.ReleaseValue(v) } }

        if let s = runStatus {
            logger.error("Decoder Run 失败: \(Self.errorMsg(api, s), privacy: .public)")
            api.pointee.ReleaseStatus(s)
            return nil
        }
        defer {
            for v in outputValues { if let v = v { api.pointee.ReleaseValue(v) } }
        }

        // 读取 token IDs
        guard let sampleIdsValue = outputValues[0] else {
            logger.error("sample_ids 输出为 nil")
            return nil
        }

        var idsDataPtr: UnsafeMutableRawPointer? = nil
        let dataStatus = api.pointee.GetTensorMutableData(sampleIdsValue, &idsDataPtr)
        guard dataStatus == nil, let idsPtr = idsDataPtr?.assumingMemoryBound(to: Int64.self) else {
            if let s = dataStatus { api.pointee.ReleaseStatus(s) }
            return nil
        }

        var tokenIds: [Int32] = []
        for i in 0..<numTokens {
            let tid = Int32(idsPtr[i])
            if tid > 2 {  // 过滤 <blank>(0), <s>(1), </s>(2)
                tokenIds.append(tid)
            }
        }

        // 更新 decoder caches
        for i in 0..<16 {
            guard let cacheVal = outputValues[i + 1] else { continue }
            var cacheDataPtr: UnsafeMutableRawPointer? = nil
            let cs = api.pointee.GetTensorMutableData(cacheVal, &cacheDataPtr)
            if cs == nil, let ptr = cacheDataPtr?.assumingMemoryBound(to: Float.self) {
                decoderCaches[i] = Array(UnsafeBufferPointer(start: ptr, count: encoderDim * 10))
            } else if let s = cs {
                api.pointee.ReleaseStatus(s)
            }
        }

        return tokenIds
    }

    // MARK: - Token → Text

    private func idsToText(_ tokenIds: [Int32]) -> String {
        var result: [String] = []
        for tid in tokenIds {
            let id = Int(tid)
            guard let tok = tokens[id] else { continue }
            if tok == "<unk>" { continue }
            if tok.hasSuffix("@@") {
                result.append(String(tok.dropLast(2)))
            } else {
                result.append(tok)
            }
        }
        return result.joined()
    }

    // MARK: - Metadata 读取

    private func loadMetadata(from session: OpaquePointer) -> Bool {
        let api = self.api

        var metadata: OpaquePointer? = nil
        var status = api.pointee.SessionGetModelMetadata(session, &metadata)
        guard status == nil, let meta = metadata else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return false
        }
        defer { api.pointee.ReleaseModelMetadata(meta) }

        // 获取 allocator
        var allocator: UnsafeMutablePointer<OrtAllocator>? = nil
        status = api.pointee.GetAllocatorWithDefaultOptions(&allocator)
        guard status == nil, let alloc = allocator else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return false
        }

        // 读取 neg_mean
        guard let negMeanStr = readMetadataValue(meta, key: "neg_mean", allocator: alloc) else {
            logger.error("读取 neg_mean 失败")
            return false
        }
        self.negMean = negMeanStr.split(separator: ",").compactMap { Float(String($0)) }

        // 读取 inv_stddev
        guard let invStddevStr = readMetadataValue(meta, key: "inv_stddev", allocator: alloc) else {
            logger.error("读取 inv_stddev 失败")
            return false
        }
        self.invStddev = invStddevStr.split(separator: ",").compactMap { Float(String($0)) }

        guard self.negMean.count == self.featureDim, self.invStddev.count == self.featureDim else {
            logger.error("CMVN 维度不匹配: neg_mean=\(self.negMean.count), inv_stddev=\(self.invStddev.count), expected=\(self.featureDim)")
            return false
        }

        logger.info("CMVN 加载成功: dims=\(self.negMean.count)")
        return true
    }

    private func readMetadataValue(_ metadata: OpaquePointer, key: String, allocator: UnsafeMutablePointer<OrtAllocator>) -> String? {
        var valuePtr: UnsafeMutablePointer<CChar>? = nil
        let status = api.pointee.ModelMetadataLookupCustomMetadataMap(metadata, allocator, key, &valuePtr)
        guard status == nil, let ptr = valuePtr else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }
        let value = String(cString: ptr)
        // 释放分配的字符串
        allocator.pointee.Free(allocator, ptr)
        return value
    }

    // MARK: - Token 加载

    private static func loadTokens(path: String) -> [Int: String]? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var tokens: [Int: String] = [:]
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count >= 2, let idx = Int(parts[1]) else { continue }
            tokens[idx] = String(parts[0])
        }
        return tokens.isEmpty ? nil : tokens
    }

    // MARK: - Tensor 创建 helpers
    //
    // 使用 ORT allocator 分配内存 + memcpy 拷贝数据。
    // ORT 拥有 tensor 内存的生命周期，避免 Swift Array 指针失效问题。

    private func createFloatTensor(_ data: [Float], shape: [Int64]) -> OpaquePointer? {
        let api = self.api

        // 获取默认 allocator
        var allocator: UnsafeMutablePointer<OrtAllocator>? = nil
        var status = api.pointee.GetAllocatorWithDefaultOptions(&allocator)
        guard status == nil, let alloc = allocator else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }

        // ORT 分配 tensor 内存
        var value: OpaquePointer? = nil
        var mutableShape = shape
        status = mutableShape.withUnsafeMutableBufferPointer { shapeBuf in
            api.pointee.CreateTensorAsOrtValue(
                alloc,
                shapeBuf.baseAddress, shape.count,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                &value
            )
        }
        guard status == nil, let val = value else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }

        // 获取 ORT 分配的内存指针，拷贝数据
        var dataPtr: UnsafeMutableRawPointer? = nil
        status = api.pointee.GetTensorMutableData(val, &dataPtr)
        guard status == nil, let dst = dataPtr else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            api.pointee.ReleaseValue(val)
            return nil
        }
        data.withUnsafeBufferPointer { src in
            dst.copyMemory(from: src.baseAddress!, byteCount: data.count * MemoryLayout<Float>.stride)
        }

        return val
    }

    private func createInt32Tensor(_ data: [Int32], shape: [Int64]) -> OpaquePointer? {
        let api = self.api

        var allocator: UnsafeMutablePointer<OrtAllocator>? = nil
        var status = api.pointee.GetAllocatorWithDefaultOptions(&allocator)
        guard status == nil, let alloc = allocator else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }

        var value: OpaquePointer? = nil
        var mutableShape = shape
        status = mutableShape.withUnsafeMutableBufferPointer { shapeBuf in
            api.pointee.CreateTensorAsOrtValue(
                alloc,
                shapeBuf.baseAddress, shape.count,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
                &value
            )
        }
        guard status == nil, let val = value else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            return nil
        }

        var dataPtr: UnsafeMutableRawPointer? = nil
        status = api.pointee.GetTensorMutableData(val, &dataPtr)
        guard status == nil, let dst = dataPtr else {
            if let s = status { api.pointee.ReleaseStatus(s) }
            api.pointee.ReleaseValue(val)
            return nil
        }
        data.withUnsafeBufferPointer { src in
            dst.copyMemory(from: src.baseAddress!, byteCount: data.count * MemoryLayout<Int32>.stride)
        }

        return val
    }

    // MARK: - 错误信息

    private static func errorMsg(_ api: UnsafePointer<OrtApi>, _ status: OpaquePointer) -> String {
        if let msg = api.pointee.GetErrorMessage(status) {
            return String(cString: msg)
        }
        return "未知错误"
    }

    // MARK: - 离线对齐验证（DEBUG only）

    #if DEBUG
    /// 离线推理各环节的中间结果，用于与 Python 参考实现逐环节对比
    struct OfflineIntermediates {
        let samples: [Float]          // 缩放后 PCM (×32768)
        let fbankFrames: Int          // fbank 帧数 T
        let fbank: [Float]            // [T×80] flat
        let lfrFrames: Int            // LFR 帧数 T_lfr
        let lfr: [Float]             // [T_lfr×560] flat
        let cmvn: [Float]            // [T_lfr×560] flat
        let enc: [Float]             // [T_lfr×512] flat
        let alphas: [Float]          // [T_lfr]
        let numTokens: Int
        let acousticEmbeds: [Float]  // [numTokens×512] flat
        let tokenIds: [Int32]
        let text: String
    }

    /// 对一段完整音频运行离线 pipeline 并返回每个环节的中间结果。
    /// 不使用流式 chunk 调度——一次性处理全部帧，与 Python 参考实现一致。
    func transcribeOfflineWithIntermediates(samples: [Float]) -> OfflineIntermediates? {
        // 1. Fbank
        let fbankExtractor = ParaformerFbank()
        fbankExtractor.acceptWaveform(samples: samples)
        fbankExtractor.inputFinished()

        let fbankFrameCount = fbankExtractor.numFramesReady
        guard fbankFrameCount > 0 else { return nil }

        var fbankFlat = [Float]()
        fbankFlat.reserveCapacity(fbankFrameCount * 80)
        for i in 0..<fbankFrameCount {
            fbankFlat.append(contentsOf: fbankExtractor.getFrame(i))
        }

        // 2. LFR
        let lfrResult = applyLFR(fbankFlat, numFrames: fbankFrameCount)
        let lfrFrameCount = lfrResult.count / featureDim

        guard lfrFrameCount > 0 else { return nil }

        // 3. CMVN
        let cmvnResult = applyCMVN(lfrResult)

        // 4. Encoder forward（全量，无 chunk 切分）
        guard let (enc, alphas) = encoderForward(features: cmvnResult, frameCount: lfrFrameCount) else {
            return nil
        }

        // 5. CIF 积分（离线模式，直接 tail flush）
        // 临时保存/恢复 CIF 状态，避免干扰流式状态
        let savedAlpha = cifAlphaRemainder
        let savedHidden = cifHiddenCache
        cifAlphaRemainder = 0.0
        cifHiddenCache = [Float](repeating: 0, count: encoderDim)

        let (embeds, numTokens) = cifIntegrate(
            enc: enc, alphas: alphas,
            frameCount: lfrFrameCount, isFinal: true
        )

        cifAlphaRemainder = savedAlpha
        cifHiddenCache = savedHidden

        guard numTokens > 0 else {
            return OfflineIntermediates(
                samples: samples, fbankFrames: fbankFrameCount, fbank: fbankFlat,
                lfrFrames: lfrFrameCount, lfr: lfrResult, cmvn: cmvnResult,
                enc: enc, alphas: alphas, numTokens: 0,
                acousticEmbeds: [], tokenIds: [], text: ""
            )
        }

        // 6. Decoder forward
        // 临时保存/恢复 decoder cache
        let savedCaches = decoderCaches
        decoderCaches = (0..<16).map { _ in [Float](repeating: 0, count: encoderDim * 10) }

        let tokenIds = decoderForward(enc: enc, encLen: lfrFrameCount, embeds: embeds, numTokens: numTokens) ?? []

        decoderCaches = savedCaches

        // 7. Token → Text
        let text = idsToText(tokenIds)

        return OfflineIntermediates(
            samples: samples, fbankFrames: fbankFrameCount, fbank: fbankFlat,
            lfrFrames: lfrFrameCount, lfr: lfrResult, cmvn: cmvnResult,
            enc: enc, alphas: alphas, numTokens: numTokens,
            acousticEmbeds: embeds, tokenIds: tokenIds, text: text
        )
    }
    #endif
}
