#if DEBUG
import CoreGraphics
import Foundation
import MonsterCore

/// Debug builds only (`-MSStubObserver`): a pretend AI observer with a canned,
/// playful reading, so the reveal layout can be checked in the Simulator,
/// which can't run the real model.
nonisolated final class StubObservationModel: ObservationModel {
    let displayName = "STUB OBSERVER"

    func prewarm() async throws {}

    func observe(image: CGImage) async throws -> SubjectObservations {
        try await Task.sleep(for: .seconds(2))
        let raw = """
        {"hair_color":"hidden","eye_color":"unknown","shirt_color":"navy blue","age_band":"unknown",
         "expression":"smiling","expression_read":"like a happy, slightly sleepy explorer",
         "accessories":["hat","sunglasses"],"fun_details":["a top hat","two red balloons","a cup of coffee"],
         "vibe":"a whimsical, coffee-sipping adventurer on a magical journey","background_hint":"party"}
        """
        return try ObservationParser.parse(raw).get()
    }

    func writeDossier(_ input: DossierInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: ObservationError.notAvailableYet) }
    }

    func unload() {}
}
#endif
