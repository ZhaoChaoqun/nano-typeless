import Foundation
import os

private let logger = Logger(subsystem: "com.typeless.app", category: "CloudRewriter")

/// Cloud LLM API 调用封装，用于 ASR 后处理（标点 + 纠错）
/// 支持 OpenAI 兼容 API（Cerebras, SiliconFlow 等）
class CloudRewriter {
    private let endpoint: String
    private let apiKey: String
    private let model: String
    private let session: URLSession

    private let systemPrompt = "你是一个ASR后处理助手。用户会给你一段语音识别的原始文本（无标点），请添加标点、纠正错别字。只输出修正后的文本，不要解释。"

    /// 从环境变量 CLOUD_REWRITE_API_KEY 读取 API Key 进行初始化
    /// - Parameters:
    ///   - endpoint: API base URL (默认 Cerebras)
    ///   - model: 模型名称
    /// - Returns: nil 如果环境变量未设置
    convenience init?(endpoint: String = "https://api.cerebras.ai/v1",
                      model: String = "gpt-oss-120b") {
        guard let apiKey = ProcessInfo.processInfo.environment["CLOUD_REWRITE_API_KEY"] else {
            logger.error("环境变量 CLOUD_REWRITE_API_KEY 未设置，CloudRewriter 初始化失败")
            return nil
        }
        self.init(endpoint: endpoint, apiKey: apiKey, model: model)
    }

    init(endpoint: String, apiKey: String, model: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        logger.info("CloudRewriter 初始化: endpoint=\(endpoint, privacy: .public), model=\(model, privacy: .public)")
    }

    /// 调用 Cloud LLM API 进行文本后处理
    /// 失败时返回原文
    func rewrite(text: String) async -> String {
        guard !text.isEmpty else { return text }

        let url = URL(string: "\(endpoint)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 2048,
            "temperature": 0.0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            logger.error("JSON 序列化失败: \(error.localizedDescription)")
            return text
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("非 HTTP 响应")
                return text
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.error("API 返回 \(httpResponse.statusCode): \(body, privacy: .public)")
                return text
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                logger.error("响应解析失败")
                return text
            }

            let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("Cloud Rewrite 完成: \(text.prefix(50), privacy: .public) → \(result.prefix(50), privacy: .public)")
            return result

        } catch {
            logger.error("Cloud Rewrite 请求失败: \(error.localizedDescription)")
            return text
        }
    }
}
