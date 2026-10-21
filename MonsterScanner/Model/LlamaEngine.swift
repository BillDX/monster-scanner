// Thin Swift wrapper over the llama.cpp C API plus mtmd (vision input).
// Shared by the app (device builds) and Tools/LlamaProbe (Mac) via symlink,
// so it depends on nothing but Foundation and the `llama` framework.
// The prebuilt xcframework has no iOS Simulator slice, so Simulator builds
// skip this file and the app stays in Classic Mode there (DECISIONS.md D-016).
#if canImport(llama)
import Foundation
import llama

/// One loaded model + vision projector + context. All C pointers stay inside
/// this actor, which runs on its own serial queue so long inference calls
/// never block the cooperative thread pool.
actor LlamaEngine {
    nonisolated struct Configuration: Sendable {
        var modelPath: String
        var projectorPath: String
        var contextLength: UInt32 = 2048
        var batchSize: UInt32 = 512
        /// All layers on the GPU (Metal).
        var gpuLayers: Int32 = 99
        var threads: Int32 = 4
        /// Cap on image tokens (0 = model default). Fewer tokens = faster.
        var imageMaxTokens: Int32 = 0
    }

    /// Tightly packed RGB, 3 bytes per pixel.
    nonisolated struct RGBImage: Sendable {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    nonisolated struct Result: Sendable {
        var text = ""
        var promptTokens = 0
        var generatedTokens = 0
        /// Image encode + prompt decode.
        var prefillSeconds = 0.0
        var generateSeconds = 0.0
        var stoppedEarly = false
    }

    nonisolated enum EngineError: Error, Equatable {
        case modelLoadFailed, projectorLoadFailed, contextFailed, notLoaded, noVisionSupport
        case tokenizeFailed(Int32), promptTooLong(Int), evalFailed(Int32), decodeFailed(Int32)
        case grammarFailed, timedOut, cancelled
    }

    private let queue = DispatchSerialQueue(label: "monster.llama", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    let configuration: Configuration
    /// Owns the C handles and frees them when the engine goes away.
    private let handles = Handles()
    private var model: OpaquePointer? {
        get { handles.model }
        set { handles.model = newValue }
    }
    private var context: OpaquePointer? {
        get { handles.context }
        set { handles.context = newValue }
    }
    private var vision: OpaquePointer? {
        get { handles.vision }
        set { handles.vision = newValue }
    }

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    var isLoaded: Bool { model != nil }

    // MARK: Lifecycle

    /// Loads model, context and projector. Returns seconds taken (0 if already loaded).
    @discardableResult
    func load() throws -> Double {
        if model != nil { return 0 }
        let start = Date()
        Self.setUpBackend

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = configuration.gpuLayers
        guard let model = llama_model_load_from_file(configuration.modelPath, modelParams) else {
            throw EngineError.modelLoadFailed
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = configuration.contextLength
        contextParams.n_batch = configuration.batchSize
        contextParams.n_threads = configuration.threads
        contextParams.n_threads_batch = configuration.threads
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw EngineError.contextFailed
        }

        var visionParams = mtmd_context_params_default()
        visionParams.use_gpu = configuration.gpuLayers != 0
        visionParams.n_threads = configuration.threads
        visionParams.print_timings = false
        visionParams.warmup = true
        if configuration.imageMaxTokens > 0 { visionParams.image_max_tokens = configuration.imageMaxTokens }
        guard let vision = mtmd_init_from_file(configuration.projectorPath, model, visionParams) else {
            llama_free(context)
            llama_model_free(model)
            throw EngineError.projectorLoadFailed
        }
        guard mtmd_support_vision(vision) else {
            mtmd_free(vision)
            llama_free(context)
            llama_model_free(model)
            throw EngineError.noVisionSupport
        }

        self.model = model
        self.context = context
        self.vision = vision
        return Date().timeIntervalSince(start)
    }

    func unload() {
        handles.free()
    }

    // MARK: Generation

    /// Runs one chat turn. `onPiece` receives text as it is generated; return
    /// false to stop. Throws `.timedOut` past `deadline`, `.cancelled` if the
    /// calling task is cancelled.
    func generate(
        system: String?,
        user: String,
        image: RGBImage?,
        grammar: String?,
        maxTokens: Int,
        temperature: Float = 0,
        seed: UInt32 = 0,
        deadline: Date? = nil,
        onPiece: (@Sendable (String) -> Bool)? = nil
    ) throws -> Result {
        guard let model, let context, let vision else { throw EngineError.notLoaded }
        let vocab = llama_model_get_vocab(model)
        llama_memory_clear(llama_get_memory(context), true)
        var result = Result()
        let prefillStart = Date()

        // 1. Prompt in the model's chat format, with the image marker.
        let marker = String(cString: mtmd_default_marker())
        let userContent = image == nil ? user : marker + "\n" + user
        let prompt = Self.chatPrompt(model: model, system: system, user: userContent)

        // 2. Tokenize text + image into chunks.
        guard let chunks = mtmd_input_chunks_init() else { throw EngineError.tokenizeFailed(-1) }
        defer { mtmd_input_chunks_free(chunks) }
        var bitmap: OpaquePointer?
        if let image {
            bitmap = image.bytes.withUnsafeBufferPointer {
                mtmd_bitmap_init(UInt32(image.width), UInt32(image.height), $0.baseAddress)
            }
        }
        defer { if let bitmap { mtmd_bitmap_free(bitmap) } }
        let tokenized: Int32 = prompt.withCString { cText in
            var text = mtmd_input_text(text: cText, text_len: strlen(cText), add_special: true, parse_special: true)
            if let bitmap {
                var bitmaps: [OpaquePointer?] = [bitmap]
                return bitmaps.withUnsafeMutableBufferPointer {
                    mtmd_tokenize(vision, chunks, &text, $0.baseAddress, 1)
                }
            }
            return mtmd_tokenize(vision, chunks, &text, nil, 0)
        }
        guard tokenized == 0 else { throw EngineError.tokenizeFailed(tokenized) }
        let promptTokens = Int(mtmd_helper_get_n_tokens(chunks))
        result.promptTokens = promptTokens
        guard promptTokens + maxTokens < Int(llama_n_ctx(context)) else {
            throw EngineError.promptTooLong(promptTokens)
        }

        // 3. Encode the image and decode the prompt.
        var nPast: llama_pos = 0
        let evaluated = mtmd_helper_eval_chunks(
            vision, context, chunks, 0, 0, Int32(configuration.batchSize), true, &nPast
        )
        guard evaluated == 0 else { throw EngineError.evalFailed(evaluated) }
        result.prefillSeconds = Date().timeIntervalSince(prefillStart)
        try checkStop(deadline)

        // 4. Sample.
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw EngineError.grammarFailed
        }
        defer { llama_sampler_free(sampler) }
        // Top-k first, so the grammar only checks 40 candidates per step
        // instead of the whole ~150k vocabulary (about 2x faster on the Mac).
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        if let grammar {
            guard let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root") else {
                throw EngineError.grammarFailed
            }
            llama_sampler_chain_add(sampler, grammarSampler)
        }
        if temperature > 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed))
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        }

        let generateStart = Date()
        var pending: [UInt8] = []
        var pieceBuffer = [CChar](repeating: 0, count: 256)
        for _ in 0..<maxTokens {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            result.generatedTokens += 1

            let length = pieceBuffer.withUnsafeMutableBufferPointer {
                llama_token_to_piece(vocab, token, $0.baseAddress, Int32($0.count), 0, false)
            }
            if length > 0 {
                pending += pieceBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
                if let piece = Self.takeValidUTF8(&pending), !piece.isEmpty {
                    result.text += piece
                    if let onPiece, !onPiece(piece) { result.stoppedEarly = true; break }
                }
            }

            var next = token
            let decoded = withUnsafeMutablePointer(to: &next) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard decoded == 0 else { throw EngineError.decodeFailed(decoded) }
            try checkStop(deadline)
        }
        result.generateSeconds = Date().timeIntervalSince(generateStart)
        return result
    }

    // MARK: Helpers

    private func checkStop(_ deadline: Date?) throws {
        if Task.isCancelled { throw EngineError.cancelled }
        if let deadline, Date() > deadline { throw EngineError.timedOut }
    }

    /// The model's own chat template, or ChatML (Qwen's format) as a fallback.
    private static func chatPrompt(model: OpaquePointer, system: String?, user: String) -> String {
        var roles: [(String, String)] = []
        if let system { roles.append(("system", system)) }
        roles.append(("user", user))

        if let template = llama_model_chat_template(model, nil) {
            let cStrings = roles.map { (strdup($0.0), strdup($0.1)) }
            defer { cStrings.forEach { free($0.0); free($0.1) } }
            var messages = cStrings.map { llama_chat_message(role: $0.0, content: $0.1) }
            var buffer = [CChar](repeating: 0, count: 8192)
            let written = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, Int32(buffer.count))
            if written > 0 && Int(written) < buffer.count {
                return String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return roles.map { "<|im_start|>\($0.0)\n\($0.1)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"
    }

    /// Removes and returns the longest valid UTF-8 prefix; keeps a split
    /// multi-byte character for the next token.
    private static func takeValidUTF8(_ bytes: inout [UInt8]) -> String? {
        for cut in stride(from: bytes.count, through: max(0, bytes.count - 3), by: -1) {
            if let text = String(bytes: bytes.prefix(cut), encoding: .utf8) {
                bytes.removeFirst(cut)
                return text
            }
        }
        if bytes.count > 8 { // not UTF-8 at all; drop it
            bytes.removeAll()
        }
        return nil
    }

    /// Only ever touched on the engine's queue (or in deinit, when nothing
    /// else can reach it), hence `@unchecked Sendable`.
    private final class Handles: @unchecked Sendable {
        var model: OpaquePointer?
        var context: OpaquePointer?
        var vision: OpaquePointer?

        func free() {
            if let vision { mtmd_free(vision) }
            if let context { llama_free(context) }
            if let model { llama_model_free(model) }
            vision = nil
            context = nil
            model = nil
        }

        deinit { free() }
    }

    /// Runs once: backend init and quiet logging (warnings and errors only).
    private static let setUpBackend: Void = {
        llama_backend_init()
        let quiet: ggml_log_callback = { level, text, _ in
            guard level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue, let text else { return }
            fputs(text, stderr)
        }
        llama_log_set(quiet, nil)
        mtmd_helper_log_set(quiet, nil)
    }()
}
#endif
