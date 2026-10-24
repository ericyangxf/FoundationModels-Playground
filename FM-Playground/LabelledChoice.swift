import FoundationModels

/// An arbiter: a session whose whole answer is one of a few labels.
///
/// The date agent asks it to choose between readings by name —
/// "pastNMonths 3", "noDates" — never by position, and always with the
/// labels in both orders: a pick that changes with the order came from the
/// order, not from the readings, and doesn't count.
nonisolated struct LabelledChoice: Sendable {
    let model: SystemLanguageModel
    let instructions: String

    func pick(among labels: [String], prompt: String) async throws -> String {
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(
                name: "Choice",
                description: "The reading that is right.",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "pick",
                        schema: DynamicGenerationSchema(name: "Reading", anyOf: labels)
                    ),
                ]
            ),
            dependencies: []
        )
        let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
        let response = try await session.respond(
            to: prompt,
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        return try response.content.value(String.self, forProperty: "pick")
    }
}
