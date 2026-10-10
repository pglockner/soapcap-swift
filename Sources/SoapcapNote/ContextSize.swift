import Foundation

/// Sizing a model's context window for a prompt. A context too small fails
/// silently: the model loses part of the prompt (often the rules, which come
/// first). 1.5 tokens a word is a safety margin over English's real rate.
public enum ContextSize {
    public static let cap = 32768

    static func need(_ prompt: String, headroom: Int) -> Int {
        prompt.split(whereSeparator: \.isWhitespace).count * 3 / 2 + headroom
    }

    /// True when the prompt plus `headroom` for the reply won't fit even the largest context.
    public static func exceedsCap(_ prompt: String, headroom: Int) -> Bool {
        need(prompt, headroom: headroom) > cap
    }

    /// At least `floor`, at most the cap, rounded up to a multiple of 1024.
    public static func estimate(_ prompt: String, headroom: Int, floor: Int = 0) -> Int {
        let size = min(max(need(prompt, headroom: headroom), floor), cap)
        return (size + 1023) / 1024 * 1024
    }
}
