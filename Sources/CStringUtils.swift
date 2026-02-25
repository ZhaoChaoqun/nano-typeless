import Foundation

/// 管理传递给 C API 配置结构体的字符串生命周期。
///
/// Sherpa-ONNX / QwenASR 的 C API 配置结构体持有 `const char*` 指针，
/// 这些指针必须在整个识别器生命周期内有效。
/// 此类使用 `strdup` 创建副本并在 `deinit` 时统一释放。
class CStringLifetime {
    private var pointers: [UnsafeMutablePointer<CChar>] = []

    /// 创建一个 C 字符串副本，生命周期由此实例管理。
    /// 返回的指针在 `CStringLifetime` 实例销毁时自动释放。
    func makeCString(_ string: String) -> UnsafePointer<CChar>? {
        guard let ptr = strdup(string) else { return nil }
        pointers.append(ptr)
        return UnsafePointer(ptr)
    }

    deinit {
        for ptr in pointers {
            free(ptr)
        }
    }
}
